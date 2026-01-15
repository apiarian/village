# Village Docker Deployment Plan

## Overview

This document outlines the approach for containerizing the village_py application using Docker. The goal is to simplify deployment while maintaining the ability to run the application on a server without the complexity of manual Python environment management.

## Design Goals

1. **Simplicity**: Docker handles all dependencies and environment setup
2. **Isolation**: Application runs in a container, isolated from host system
3. **Persistence**: Data directory and logs persist outside the container
4. **No Registry**: Build and run locally, no need to push to Docker Hub/registry
5. **Production-Ready**: Optimized for server deployment, not development hot-reload
6. **Maintainability**: Easy to update, backup, and troubleshoot

## Architecture

### Container Structure

```
village/                       # Repository root
├── .dockerignore              # Files to exclude from build context (at repo root!)
├── village_py/                # Python application
│   ├── pyproject.toml
│   ├── poetry.lock
│   └── village/               # App code
└── village_docker/            # Docker deployment files
    ├── PLAN.md                # This file
    ├── Dockerfile             # Main container definition
    ├── entrypoint.sh          # Container startup script
    ├── village-docker.service # Systemd service (different from old village.service)
    ├── config/
    │   └── village.env.example
    ├── scripts/
    │   ├── build.sh           # Build the Docker image
    │   ├── deploy.sh          # Deploy on server (pull, build, restart)
    │   ├── start.sh           # Start container
    │   ├── stop.sh            # Stop container
    │   ├── logs.sh            # View logs
    │   ├── shell.sh           # Open shell in container
    │   ├── run-script.sh      # Run any poetry script
    │   └── backup.sh          # Backup data directory
    └── README.md              # Deployment instructions
```

**Build Context:**
The Docker build context is the repository root (`village/`), not `village_docker/`. This allows the Dockerfile to access files from both `village_py/` and `village_docker/`.

The `build.sh` script will run:
```bash
docker build -f village_docker/Dockerfile -t village:latest .
```
(Run from repository root, or adjust path accordingly)

**Customizing the User ID:**
To match an existing host user's UID:
```bash
# Default build (UID 10000) - for fresh installations
docker build -f village_docker/Dockerfile -t village:latest .

# Match existing village user's UID automatically
docker build --build-arg VILLAGE_UID=$(id -u village) -f village_docker/Dockerfile -t village:latest .
```

### Volume Mounts

**Persistent Data (survives container recreation):**
- `/opt/village/data` → Host volume for Village repository data
- `/opt/village/logs` → Host volume for application logs
- `/opt/village/config/village.env` → Host file for environment config

**Why these mounts?**
- Data persistence across updates/restarts
- Easy backup of important data
- Configuration changes without rebuilding container
- Log access without entering container

### File Ownership and Permissions

**Critical for proper operation:**

The container runs as user `village` with a configurable UID (default 10000). Docker's default behavior maps container UIDs directly to host UIDs, so:

- **Container UID** = **Host UID** (must match!)
- Files written by the container appear as owned by this UID on the host
- Container can only write to directories owned by this UID on the host
- Default UID 10000 chosen to avoid conflicts with existing system users (typically < 1000)

**Configuring the UID:**

The UID can be set at build time to match your host's village user:

```bash
# Check your host's village user UID
id -u village

# Build with matching UID automatically
docker build --build-arg VILLAGE_UID=$(id -u village) -f village_docker/Dockerfile -t village:latest .
```

**Host directory ownership:**
```bash
# Create village user on host (if doesn't exist) - adjust UID as needed
sudo useradd -r -s /bin/false -u 10000 village 2>/dev/null || true

# Set ownership (files must be owned by the same UID as container user)
sudo chown -R village:village /opt/village/data
sudo chown -R village:village /opt/village/logs
sudo chown village:village /opt/village/config/village.env
```

**Systemd service runs as root:**
- The systemd service (`village-docker.service`) runs as root
- This is required because Docker daemon operations need privileged access
- Root only manages the container lifecycle (start/stop/restart)
- The actual application inside the container runs as unprivileged `village` user
- File I/O happens as the configured UID, not root

**Summary:**
- Systemd: runs as root (manages Docker)
- Container: runs as village (configurable UID, default 10000)
- Host files: must be owned by village user with matching UID
- Security: achieved via container isolation, not host user isolation

**Important:** The UID in the container MUST match the UID of the host user that owns the mounted directories, or you'll get permission errors.

## Dockerfile Design

### Base Image
- **Choice**: `python:3.11-alpine`
- **Rationale**: Smallest footprint, good enough for this simple home server application
- **Note**: Will switch to slim if we encounter package compatibility issues

### Build Strategy
Multi-stage build:
1. **Builder stage**: Install Poetry, install dependencies, build wheels
2. **Runtime stage**: Copy only necessary files, install from wheels

**Benefits:**
- Smaller final image (no build tools)
- Faster subsequent builds (cached layers)
- More secure (fewer attack surfaces)

**Note on paths:**
The Dockerfile will reference paths relative to the repository root:
```dockerfile
COPY village_py/pyproject.toml village_py/poetry.lock /app/
COPY village_py/village /app/village/
COPY village_docker/entrypoint.sh /app/
```

### User Setup
- Create non-root `village` user with configurable UID
- Default UID: 10000 (avoids conflicts with existing system users)
- Can be customized at build time: `docker build --build-arg VILLAGE_UID=991 ...`
- All app files owned by `village`
- Container runs as `village` user
- Working directory: `/app` (contains the application code)

### Application Structure Inside Container
```
/app/
├── pyproject.toml
├── poetry.lock
├── village/           # Application code
│   ├── __init__.py
│   ├── app.py
│   └── ...
└── entrypoint.sh
```

**Note:** The working directory should be `/app` so that `village.app:app` resolves correctly for Gunicorn.

### Dependencies
- Install Poetry in builder stage
- Keep Poetry in runtime stage for running scripts
- Copy pyproject.toml and poetry.lock to ensure reproducible builds
- Install dependencies with `poetry install --no-dev --no-root` for production

## Docker Run Configuration

The container will be started with a simple `docker run` command:

```bash
docker run -d \
  --name village \
  --restart unless-stopped \
  -p 127.0.0.1:8000:8000 \
  -v /opt/village/data:/opt/village/data \
  -v /opt/village/logs:/opt/village/logs \
  --env-file /opt/village/config/village.env \
  village:latest
```

**Key parameters:**
- `-d`: Run detached (background)
- `--name village`: Container name for easy reference
- `--restart unless-stopped`: Auto-restart on failure or reboot
- `-p 127.0.0.1:8000:8000`: Bind port 8000 to localhost only
- `-v`: Bind mount data and logs directories
- `--env-file`: Load environment variables from file

**Healthcheck** will be defined in the Dockerfile (uses existing `/about` endpoint):
```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8000/about || exit 1
```

## Entrypoint Script

The `entrypoint.sh` script will be simple and fail-fast:
1. Validate required environment variables exist (FLASK_SECRET_KEY, etc.)
2. Check that data directory is mounted and writable
3. Verify repository is initialized (error if not - user must run `run-script.sh initialize-repository` first)
4. Start Gunicorn with proper configuration

**No waiting or retrying** - if something is wrong, fail immediately with a clear error message.

## Running Poetry Scripts

The `scripts/run-script.sh` helper runs any poetry script defined in `pyproject.toml`:

```bash
./scripts/run-script.sh <script-name> [args...]
```

**How it works:**
- Runs a one-off container with the same volumes and environment as the main container
- Executes `poetry run <script-name>` inside the container
- Container is removed after script completes (`--rm` flag)
- Interactive mode (`-it`) for scripts that need user input

**Examples:**
```bash
./scripts/run-script.sh initialize-repository
./scripts/run-script.sh create-user
./scripts/run-script.sh force-reset-password username
./scripts/run-script.sh update-thumbnail post-id
```

**Benefits:**
- Works even when main container isn't running
- Consistent environment with main container
- No need to remember docker commands
- Easy to add new scripts in the future

## Deployment Workflow

### Initial Setup (One-time)

```bash
# 1. On server, create directories
sudo mkdir -p /opt/village/data /opt/village/logs /opt/village/config

# 2. Clone repository
git clone <repo-url> /opt/village/village
cd /opt/village/village/village_docker

# 3. Configure environment
cp config/village.env.example /opt/village/config/village.env
sudo nano /opt/village/config/village.env  # Set FLASK_SECRET_KEY, etc.

# 4. Build and initialize
./scripts/build.sh
./scripts/run-script.sh initialize-repository
./scripts/run-script.sh create-user

# 5. Start the server
./scripts/start.sh
```

### Updates

```bash
cd /opt/village/village/village_docker
git pull
./scripts/deploy.sh  # Pulls, rebuilds, restarts
```

## Security Considerations

1. **Port Binding**: Bind to 127.0.0.1 only, require reverse proxy
2. **Non-root User**: Container runs as unprivileged user
3. **Read-only Config**: Mount village.env as read-only
4. **Secrets**: FLASK_SECRET_KEY in environment file, not in image
5. **Network**: Use Docker's default bridge network (isolated)

## Backup Strategy

```bash
# Backup script creates timestamped tarball
./scripts/backup.sh
# Creates: /opt/village/backups/village-data-YYYYMMDD-HHMMSS.tar.gz
```

**What to backup:**
- `/opt/village/data` - All Village data
- `/opt/village/config/village.env` - Configuration

**What NOT to backup:**
- `/opt/village/logs` - Can be recreated, large
- Docker image - Can be rebuilt from Dockerfile

## Monitoring and Logs

```bash
# View live logs
./scripts/logs.sh

# View last 100 lines
docker logs village --tail 100

# Check container health
docker ps
docker inspect village | grep -A 10 Health
```

## Comparison to Direct Python Deployment

### Advantages of Docker

| Aspect | Direct Python | Docker |
|--------|---------------|--------|
| Setup Complexity | High (Poetry, venv, systemd) | Low (docker-compose up) |
| Dependency Conflicts | Possible with system packages | Isolated |
| Reproducibility | Hard (different Python versions) | Easy (pinned base image) |
| Updates | Complex (poetry update, restart) | Simple (rebuild, restart) |
| Rollback | Manual git checkout | Change image tag |
| Portability | Platform-dependent | Works anywhere Docker runs |

### Disadvantages of Docker

| Aspect | Direct Python | Docker |
|--------|---------------|--------|
| Resource Usage | Native | Small overhead (~100MB) |
| Debugging | Direct access | Need to exec into container |
| File Permissions | Native user | UID mapping considerations |
| Learning Curve | Familiar (systemd) | Need Docker knowledge |

## Migration Path

For users with existing `village_py_deployment` setup:

### Safe Transition Strategy

The Docker deployment uses a **different service name** (`village-docker`) to allow safe coexistence during testing:

1. **Backup current data**: 
   ```bash
   sudo tar czf ~/village-backup-$(date +%Y%m%d).tar.gz /opt/village/data
   ```

2. **Stop old service**:
   ```bash
   sudo systemctl stop village
   ```

3. **Install Docker** (if not present):
   ```bash
   sudo dnf install docker
   sudo systemctl enable --now docker
   ```

4. **Set up Docker deployment**:
   ```bash
   cd /opt/village/village/village_docker
   # Copy existing config or create new one
   cp /etc/village.env config/village.env.example
   sudo cp config/village.env.example /opt/village/config/village.env
   ./scripts/build.sh
   ```

5. **Start Docker service**:
   ```bash
   sudo cp village-docker.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl start village-docker
   ```

6. **Test thoroughly** - both services are installed but only Docker is running

7. **If Docker works**:
   ```bash
   sudo systemctl enable village-docker
   sudo systemctl disable village  # Old service won't start on boot
   ```

8. **If Docker has issues - rollback**:
   ```bash
   sudo systemctl stop village-docker
   sudo systemctl start village  # Back to old deployment
   ```

9. **After confirmed working** (days/weeks later):
   ```bash
   sudo systemctl disable village-docker
   sudo systemctl stop village-docker
   # Remove old deployment files if desired
   ```

**Service Names:**
- Old: `village.service` (systemd service for direct Python/Gunicorn)
- New: `village-docker.service` (systemd service that manages Docker container)

**Both use the same:**
- Data directory: `/opt/village/data`
- Port: `127.0.0.1:8000`
- Config location: Now at `/opt/village/config/village.env` (Docker) vs `/etc/village.env` (old)

**Note:** Only one can run at a time since they both bind to port 8000.

## Troubleshooting Guide

### Container won't start
```bash
docker logs village
./scripts/logs.sh
```

### Permission errors on volumes
```bash
sudo chown -R 1000:1000 /opt/village/data /opt/village/logs
```

### Need to run admin commands
```bash
# Run any poetry script
./scripts/run-script.sh create-user
./scripts/run-script.sh force-reset-password
./scripts/run-script.sh update-thumbnail

# Or get a shell if needed
./scripts/shell.sh
```

### Rebuild from scratch
```bash
./scripts/stop.sh
docker rmi village:latest
./scripts/build.sh
./scripts/start.sh
```

## Future Enhancements (If Needed)

1. **Automated Backups**: Cron job to run backup script
2. **Switch to slim base**: If Alpine has package compatibility issues

## Decisions Made

1. **Base Image**: `python:3.11-alpine` (smallest footprint, switch if needed)
2. **Poetry in Runtime**: Keep Poetry for consistency with dev
3. **Gunicorn Workers**: Default 4, configurable via `WORKERS` env var
4. **Health Check**: Use existing `/about` endpoint
5. **UID**: Use 1000 for simplicity
6. **No docker-compose**: Simple `docker run` commands wrapped in scripts
7. **No registry**: Build and run locally only
8. **No monitoring/metrics**: Simple home server, not needed
9. **No SSL in container**: Reverse proxy handles this

## Implementation Details

### Environment Variables Required

The container needs these environment variables (from `village.env`):

**Required:**
- `FLASK_SECRET_KEY` - Session encryption key (32+ chars)
- `FLASK_ENV` - Should be `production`
- `VILLAGE_REPOSITORY` - Path to data directory (default: `/opt/village/data`)

**Gunicorn Configuration:**
- `BIND_ADDRESS` - Inside container should be `0.0.0.0:8000`
- `WORKERS` - Number of Gunicorn workers (default: 4)
- `WORKER_CLASS` - Worker class (default: `gevent`)
- `WORKER_CONNECTIONS` - Max connections per worker (default: 1000)
- `MAX_REQUESTS` - Restart worker after N requests (default: 1000)
- `MAX_REQUESTS_JITTER` - Random jitter for max_requests (default: 50)
- `TIMEOUT` - Worker timeout in seconds (default: 30)
- `LOG_LEVEL` - Logging level (default: `info`)

**Note:** The entrypoint.sh will start Gunicorn using these environment variables.

### Systemd Service Requirements

The `village-docker.service` file should:
- Run as root (Docker commands require it, but container runs as unprivileged user)
- Use `ExecStart` to run the docker run command (or call start.sh script)
- Use `ExecStop` to stop the container gracefully
- Set `Restart=on-failure` for reliability
- Depend on `docker.service`

Example structure:
```ini
[Unit]
Description=Village Web Application (Docker)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/village/village/village_docker/scripts/start.sh
ExecStop=/opt/village/village/village_docker/scripts/stop.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### .dockerignore Contents

Place at repository root to exclude:
```
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
venv/
env/
ENV/

# Village
village_py/.pytest_cache/
village_py/.mypy_cache/
village_py/tests/

# Git
.git/
.gitignore

# Deployment (old)
village_py_deployment/

# IDE
.vscode/
.idea/
*.swp
*.swo
```

## Next Steps

1. ✅ Create this plan document
2. ✅ Write Dockerfile with multi-stage build
3. ✅ Create entrypoint.sh script
4. ✅ Create village-docker.service systemd unit
5. ✅ Create setup.sh script (idempotent, creates directories, sets ownership)
6. ⬜ Create .dockerignore at repo root
7. ⬜ Write helper scripts (build, deploy, start, stop, logs, etc.)
8. ✅ Create example village.env
9. ⬜ Write comprehensive README.md
10. ⬜ Test on fresh system
11. ⬜ Test migration from old deployment

---

**Status**: Implementation In Progress
**Last Updated**: 2026-01-14

## Implementation Notes

### Step 2: Dockerfile (COMPLETED)
- Multi-stage build working correctly
- Builder stage successfully installs Poetry 1.7.1 and all dependencies
- Runtime stage uses Alpine base with minimal dependencies
- Build tested up to step 16/22 (fails on missing entrypoint.sh as expected)
- All paths and COPY commands verified correct
- No issues with Alpine compatibility for our dependencies
- Build context correctly uses repository root
- Non-root user (village:1000) created successfully

### Step 3: entrypoint.sh script (COMPLETED)
- Fail-fast design - exits immediately on any error
- **Safety validations**:
  - Checks for CONFIG_NOT_REVIEWED variable and refuses to start if present
  - Validates FLASK_SECRET_KEY is not default "CHANGE_ME" value
  - Validates FLASK_SECRET_KEY minimum length (32 characters)
  - Provides clear error messages with instructions to fix
- Validates all required environment variables
- Sets sensible defaults for Gunicorn configuration
- Checks data directory exists and is writable
- Verifies repository is initialized (checks for settings.yaml file)
- Checks logs directory exists and is writable
- Starts Gunicorn with all configuration from environment variables
- Uses colored output for better readability (INFO/WARN/ERROR)
- Logs access and errors to separate files in logs directory
- Uses exec to replace shell process with Gunicorn (proper signal handling)
- Fixed: Repository check now looks for settings.yaml (not git/annex files)

### Step 4: village-docker.service systemd unit (COMPLETED)
- Type: oneshot with RemainAfterExit=yes (appropriate for Docker container management)
- Runs as root (required for Docker daemon operations)
- Container itself runs as unprivileged village user (configurable UID, default 10000)
- Depends on docker.service and network-online.target
- Cleans up any existing container before starting (ExecStartPre)
- Calls start.sh and stop.sh scripts for container lifecycle
- Restart=on-failure with 10-second delay for reliability
- Security: PrivateTmp=yes, NoNewPrivileges=true
- Default paths assume /opt/village/village installation
- Documented how to customize paths if installed elsewhere
- Added clear installation instructions in comments
- Updated Dockerfile to accept VILLAGE_UID build argument
- Documented UID configuration in PLAN.md (must match host user UID)
- Example: `docker build --build-arg VILLAGE_UID=991 ...`

### Step 5: setup.sh script (COMPLETED)
- Idempotent design - can be run multiple times safely
- Creates all required directories: village (repo deployment), data, logs, config, backups
- Gracefully handles village user creation:
  - If user exists: uses existing UID automatically (no conflicts)
  - If user doesn't exist: creates with UID 10000 (or custom via VILLAGE_UID env var)
  - If UID 10000 is taken: lets system assign available UID automatically
- Sets proper ownership on all directories (village:village)
- Sets appropriate directory permissions (755)
- **Automatically deploys repository code**:
  - Auto-detects current working repo location (where script is run from)
  - Gets the git remote URL from your current clone
  - If /opt/village/village is empty, automatically does a fresh git clone from the same remote
  - This creates an independent git repository that can be updated with git pull
  - If already deployed, skips deployment
  - Exits with error if deployment directory is not empty and not a repo
- **Automatically sets up configuration file**:
  - Copies village.env.example to /opt/village/config/village.env
  - Sets ownership to village:village
  - Sets permissions to 600 (read/write owner only, contains secrets)
  - Checks if FLASK_SECRET_KEY still has default value and warns if so
  - Provides clear instructions for required edits
- Provides helpful next steps with full paths based on detected configuration
- Uses colored output for better readability
- Exits with error if not run as root
- Supports VILLAGE_UID environment variable for customization
- Sources common.sh for shared configuration and UID detection
- Workflow: Run setup.sh from your personal clone (e.g., ~/village), it automatically clones a fresh copy to /opt/village/village
- Created common.sh helper library:
  - Provides shared functions (info, warn, error, debug)
  - Centralizes configuration (paths including REPO_DIR, container name, image name)
  - Auto-detects village user UID with get_village_uid() function
  - **Auto-detects script location**: SCRIPT_REPO (where you're running from) vs REPO_DIR (deployment location)
  - Scripts work from both personal clone (~/village) and deployment location (/opt/village/village)
  - Can be sourced by all future scripts for consistency
  - Supports DEBUG=1 environment variable for verbose output
- Created village.env.example:
  - Comprehensive configuration template with comments
  - All required and optional environment variables
  - Clear instructions for generating FLASK_SECRET_KEY
  - Sensible defaults for Gunicorn configuration
  - **Safety check**: CONFIG_NOT_REVIEWED=true prevents app from starting
  - User MUST delete this line after reviewing config
  - Also validates FLASK_SECRET_KEY is not default "CHANGE_ME" value
  - Entrypoint.sh validates and refuses to start with unsafe config
