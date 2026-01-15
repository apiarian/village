# Village Docker Deployment

This directory contains Docker-based deployment files for the Village application. Docker simplifies deployment by handling all dependencies and environment setup in a container.

## Quick Start

### Prerequisites

- Docker installed and running
- Root/sudo access for initial setup
- Git installed

### Initial Setup

```bash
# 1. Clone repository (if not already done)
git clone <your-repo-url> ~/village
cd ~/village/village_docker

# 2. Run setup script (creates directories, user, deploys code, sets ownership)
sudo ./scripts/setup.sh

# 3. Edit configuration (REQUIRED - set secrets!)
sudo nano /opt/village/config/village.env
# IMPORTANT: Delete CONFIG_NOT_REVIEWED=true line after reviewing
# IMPORTANT: Change FLASK_SECRET_KEY to a secure random value

# 4. Build Docker image
./scripts/build.sh

# 5. Initialize repository (automatically runs as village user)
./scripts/run-script.sh initialize-repository

# 6. Create first user (automatically runs as village user)
./scripts/run-script.sh create-user

# 7. Install systemd service
sudo cp village-docker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable village-docker

# 8. Start the application
sudo systemctl start village-docker

# 9. Check status
sudo systemctl status village-docker
```

The application will be available at `http://localhost:8000`

### Updates

```bash
cd /opt/village/village/village_docker
./scripts/deploy.sh
```

This automatically pulls the latest code, rebuilds the image, and restarts the container via systemd.

## Architecture

### Container Design

- **Base Image**: `python:3.11-alpine` - minimal Alpine Linux with Python
- **User**: Runs as non-root `village` user (configurable UID, default 10000)
- **Port**: 8000 (bound to localhost only for security)
- **Server**: Gunicorn with gevent workers
- **Health Check**: Uses `/about` endpoint

### Directory Structure

```
/opt/village/
├── village/              # Git repository (deployed by setup.sh)
│   ├── village_py/       # Python application code
│   └── village_docker/   # Docker deployment files (this directory)
├── data/                 # Village repository data (git-annex)
├── logs/                 # Application logs (access.log, error.log)
├── config/               # Configuration files
│   └── village.env       # Environment variables (secrets)
└── backups/              # Backup files (created by backup.sh)
```

### Volume Mounts

The container mounts these directories from the host:

- `/opt/village/data` → Container: `/opt/village/data` (repository data)
- `/opt/village/logs` → Container: `/opt/village/logs` (application logs)
- `/opt/village/config/village.env` → Container: environment variables

**Why?** Data persists across container updates/restarts, and you can access logs without entering the container.

### File Ownership

The container runs as user `village` with a configurable UID (default: 10000). This UID must match the host user that owns the mounted directories.

**Default Setup:**
```bash
# setup.sh creates village user with UID 10000
sudo useradd -r -s /bin/false -u 10000 village

# All directories owned by this user (setup.sh does this automatically)
sudo chown -R village:village /opt/village/data
sudo chown -R village:village /opt/village/logs
sudo chown -R village:village /opt/village/village  # Git repository (for git pull operations)
```

**Custom UID:**
```bash
# If you have an existing village user with different UID
VILLAGE_UID=991 sudo ./scripts/setup.sh
./scripts/build.sh --uid 991
```

### Automatic Sync and Permission Handling

Several scripts automatically handle deployment and permissions:

- `run-script.sh` - Runs poetry scripts
- `start.sh` - Starts the container
- `shell.sh` - Opens a shell in the container

**How it works:**

1. You run the script from your personal clone (e.g., `~/village/village_docker/scripts/`)
2. Script syncs code to deployment location (`/opt/village/village/`)
3. Script re-executes from deployment location as `village` user
4. Village user only has access to `/opt/village/`, not your home directory

**Why?** 
- The configuration file (`/opt/village/config/village.env`) is owned by `village:village` with `chmod 600` for security
- Docker needs read access to this file
- Village user shouldn't have access to user home directories (principle of least privilege)
- Ensures production runs the latest code

**User Experience:**
```bash
# Run from your personal clone - it handles everything automatically:
cd ~/village/village_docker
./scripts/start.sh                        # Syncs to /opt/village/village, then runs as village user
./scripts/run-script.sh initialize-repository  # Same automatic behavior
./scripts/shell.sh                        # Same automatic behavior

# Or run directly from deployment location:
cd /opt/village/village/village_docker
./scripts/start.sh                        # Already at deployment location, just runs as village user
```

**Note:** You may be prompted for your sudo password.

## Helper Scripts

All scripts are in `village_docker/scripts/` and can be run from anywhere.

### Build & Deployment

- **`build.sh`** - Build the Docker image
  ```bash
  ./scripts/build.sh              # Build with auto-detected UID
  ./scripts/build.sh --uid 991    # Build with custom UID
  ./scripts/build.sh --no-cache   # Full rebuild (clear cache)
  ```

- **`deploy.sh`** - Full deployment (pull, build, restart)
  ```bash
  ./scripts/deploy.sh                    # Normal deployment
  ./scripts/deploy.sh --no-pull          # Skip git pull
  ./scripts/deploy.sh --no-build         # Skip rebuild
  ./scripts/deploy.sh --force            # Force restart
  ./scripts/deploy.sh --branch develop   # Deploy from different branch
  ```

### Container Management

- **`start.sh`** - Start the container (automatically runs as village user)
  ```bash
  ./scripts/start.sh          # Start normally
  ./scripts/start.sh --force  # Force recreate
  ```
  
  Note: The script automatically re-executes with `sudo -u village` if needed for proper permissions.

- **`stop.sh`** - Stop the container
  ```bash
  ./scripts/stop.sh                    # Graceful stop (10s timeout)
  ./scripts/stop.sh --timeout 30       # Custom timeout
  ./scripts/stop.sh --force            # Force kill if needed
  ./scripts/stop.sh --remove           # Remove after stopping
  ```

- **`logs.sh`** - View logs
  ```bash
  ./scripts/logs.sh                # View all container logs
  ./scripts/logs.sh --follow       # Follow logs in real-time
  ./scripts/logs.sh --tail 100     # Last 100 lines
  ./scripts/logs.sh --access       # View access.log file
  ./scripts/logs.sh --error        # View error.log file
  ./scripts/logs.sh --timestamps   # Show timestamps
  ```

### Utilities

- **`shell.sh`** - Open shell in container (automatically runs as village user)
  ```bash
  ./scripts/shell.sh                          # Interactive shell
  ./scripts/shell.sh --command "ls -la"       # Run single command
  ./scripts/shell.sh --command "python -V"    # Check Python version
  ```
  
  Note: The script automatically re-executes with `sudo -u village` if needed for proper permissions.

- **`run-script.sh`** - Run poetry scripts (automatically runs as village user)
  ```bash
  ./scripts/run-script.sh initialize-repository
  ./scripts/run-script.sh create-user
  ./scripts/run-script.sh force-reset-password username
  ./scripts/run-script.sh update-thumbnail post-id
  ```
  
  Note: The script automatically re-executes with `sudo -u village` if needed for proper permissions.

- **`backup.sh`** - Backup data directory
  ```bash
  ./scripts/backup.sh                          # Backup data only
  ./scripts/backup.sh --include-config         # Include config (secrets!)
  ./scripts/backup.sh --output /mnt/backup     # Custom output directory
  ./scripts/backup.sh --compress xz            # Better compression
  ./scripts/backup.sh --no-verify              # Skip verification
  ```

## Configuration

### Environment Variables

Configuration is in `/opt/village/config/village.env`. This file is created from `config/village.env.example` during setup.

**Required Variables:**

- `FLASK_SECRET_KEY` - Session encryption key (must be 32+ random characters)
- `FLASK_ENV` - Set to `production`
- `VILLAGE_REPOSITORY` - Path to data directory (default: `/opt/village/data`)

**Safety Checks:**

The application **will not start** if:
- `CONFIG_NOT_REVIEWED=true` is present (you must delete this line after reviewing)
- `FLASK_SECRET_KEY` is set to default `"CHANGE_ME"`
- `FLASK_SECRET_KEY` is less than 32 characters

**Gunicorn Configuration:**

- `BIND_ADDRESS` - Bind address (default: `0.0.0.0:8000`)
- `WORKERS` - Number of worker processes (default: `4`)
- `WORKER_CLASS` - Worker type (default: `gevent`)
- `WORKER_CONNECTIONS` - Max connections per worker (default: `1000`)
- `MAX_REQUESTS` - Restart worker after N requests (default: `1000`)
- `MAX_REQUESTS_JITTER` - Random jitter (default: `50`)
- `TIMEOUT` - Worker timeout in seconds (default: `30`)
- `LOG_LEVEL` - Logging level (default: `info`)

**Generating a Secure Secret Key:**

```bash
# Python method
python3 -c 'import secrets; print(secrets.token_hex(32))'

# OpenSSL method
openssl rand -hex 32

# /dev/urandom method
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1
```

### After Configuration Changes

If you change `/opt/village/config/village.env`, restart the container:

```bash
sudo systemctl restart village-docker
```

## Systemd Service

The systemd service is the standard way to manage the Village Docker container. It provides automatic startup on boot, managed restarts on failure, and integration with system logs.

**The systemd service should be installed during initial setup** (see Quick Start above).

### Usage

```bash
# Start
sudo systemctl start village-docker

# Stop
sudo systemctl stop village-docker

# Restart
sudo systemctl restart village-docker

# Check status
sudo systemctl status village-docker

# View logs
sudo journalctl -u village-docker -f

# View detailed logs
sudo journalctl -u village-docker -n 100

# Follow logs in real-time
sudo journalctl -u village-docker -f
```

### Manual Control (Without Systemd)

The helper scripts can also control the container directly, useful for testing:

```bash
# Start container directly (not managed by systemd)
./scripts/start.sh

# Stop container
./scripts/stop.sh

# View logs
./scripts/logs.sh --follow
```

**Note:** If systemd service is enabled, use `systemctl` commands instead to avoid conflicts.

### Custom Installation Path

If you installed to a different location than `/opt/village/village`, edit the service file before copying:

```ini
[Service]
ExecStart=/your/custom/path/village/village_docker/scripts/start.sh
ExecStop=/your/custom/path/village/village_docker/scripts/stop.sh
```

## Troubleshooting

### Container Won't Start

```bash
# Check systemd status
sudo systemctl status village-docker

# Check systemd logs
sudo journalctl -u village-docker -n 50

# Check container logs
./scripts/logs.sh

# Check Docker status
docker ps -a
docker inspect village

# Restart service
sudo systemctl restart village-docker

# Check configuration
sudo cat /opt/village/config/village.env
```

**Common Issues:**

1. **CONFIG_NOT_REVIEWED error**: Delete `CONFIG_NOT_REVIEWED=true` line from village.env
2. **FLASK_SECRET_KEY error**: Set to a secure random value (not "CHANGE_ME")
3. **Permission denied**: Run `sudo ./scripts/setup.sh` to fix ownership
4. **Port already in use**: Another process using port 8000 (check with `sudo netstat -tlnp | grep 8000`)
5. **Repository not initialized**: Run `./scripts/run-script.sh initialize-repository`

### Permission Errors

**Most permission issues are handled automatically.** Scripts like `start.sh`, `run-script.sh`, and `shell.sh` automatically re-execute as the village user when needed.

If you still see "Permission denied" errors:

```bash
# Fix ownership of data and logs directories
sudo chown -R village:village /opt/village/data
sudo chown -R village:village /opt/village/logs

# Or re-run setup to fix all ownership
sudo ./scripts/setup.sh
```

**Note:** If you get "permission denied" on `/opt/village/config/village.env`, the scripts should handle this automatically. If they don't, you may need to check that the village user exists (`id village`).

### Image Not Found

If `start.sh` says image doesn't exist:

```bash
# Build the image
./scripts/build.sh

# Check images
docker images | grep village
```

### Need to Rebuild

If you need to rebuild from scratch:

```bash
# Stop service
sudo systemctl stop village-docker

# Remove old image
docker rmi village:latest

# Rebuild
./scripts/build.sh --no-cache

# Start service
sudo systemctl start village-docker
```

### UID Mismatch

If the container UID doesn't match your host UID:

```bash
# Check current village user UID
id -u village

# Rebuild with matching UID
./scripts/build.sh --uid $(id -u village)

# Fix directory ownership
sudo chown -R village:village /opt/village/data
sudo chown -R village:village /opt/village/logs
```

### View Container Details

```bash
# Interactive shell in running container
./scripts/shell.sh

# Run commands in container
./scripts/shell.sh --command "python -V"
./scripts/shell.sh --command "poetry show"
./scripts/shell.sh --command "ls -la /opt/village/data"

# Check environment variables
./scripts/shell.sh --command "env | sort"

# Check permissions
./scripts/shell.sh --command "id"
./scripts/shell.sh --command "ls -la /opt/village"
```

## Backup and Restore

### Creating Backups

```bash
# Stop service first (recommended for consistent backups)
sudo systemctl stop village-docker

# Backup data only (recommended for regular backups)
./scripts/backup.sh

# Backup data + config (includes secrets - secure this file!)
./scripts/backup.sh --include-config

# Backup to external storage
./scripts/backup.sh --output /mnt/external/backups

# Maximum compression (slower, smallest file)
./scripts/backup.sh --compress xz

# Restart service
sudo systemctl start village-docker
```

Backups are created as timestamped tarballs:
- `village-data-YYYYMMDD-HHMMSS.tar.gz`

### Restoring from Backup

```bash
# 1. Stop service
sudo systemctl stop village-docker

# 2. Extract backup (preserves directory structure)
sudo tar xzf /opt/village/backups/village-data-20260114-120000.tar.gz -C /

# 3. Fix ownership (if needed)
sudo ./scripts/setup.sh

# 4. Start service
sudo systemctl start village-docker
```

### Backup Strategy

**What to backup:**
- Data directory (`/opt/village/data`) - All Village content
- Config file (`/opt/village/config/village.env`) - Contains secrets

**What NOT to backup:**
- Logs (`/opt/village/logs`) - Regenerated, large
- Docker images - Rebuilt from Dockerfile
- Application code - Tracked in git

**Recommended schedule:**
- Daily: `./scripts/backup.sh` (data only)
- Weekly: `./scripts/backup.sh --include-config` (data + config)
- Before updates: Always backup before running `./scripts/deploy.sh`

**Automation:**

Create a cron job for automated backups:

```bash
# Edit crontab
sudo crontab -e

# Add daily backup at 2 AM
0 2 * * * /opt/village/village/village_docker/scripts/backup.sh

# Add weekly config backup on Sunday at 3 AM
0 3 * * 0 /opt/village/village/village_docker/scripts/backup.sh --include-config
```

## Migration from Old Deployment

If you have an existing non-Docker deployment:

### Safe Migration Strategy

1. **Backup existing data**
   ```bash
   sudo tar czf ~/village-backup-$(date +%Y%m%d).tar.gz /opt/village/data
   ```

2. **Stop old service**
   ```bash
   sudo systemctl stop village
   ```

3. **Install Docker** (if not present)
   ```bash
   sudo dnf install docker  # Fedora/RHEL
   sudo apt install docker.io  # Ubuntu/Debian
   sudo systemctl enable --now docker
   ```

4. **Run Docker setup**
   ```bash
   cd /opt/village/village/village_docker
   sudo ./scripts/setup.sh
   
   # Copy or create config (may differ from old /etc/village.env)
   sudo cp /etc/village.env /opt/village/config/village.env
   sudo nano /opt/village/config/village.env  # Update if needed
   ```

5. **Build and start**
   ```bash
   ./scripts/build.sh
   ./scripts/start.sh
   ```

6. **Install and start systemd service**
   ```bash
   sudo cp village-docker.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable village-docker
   sudo systemctl start village-docker
   ```

7. **Test thoroughly**
   - Visit http://localhost:8000
   - Log in with existing user
   - Create a post
   - Check status: `sudo systemctl status village-docker`
   - Check logs: `sudo journalctl -u village-docker -f`

8. **Disable old service** (after confirming Docker works)
   ```bash
   sudo systemctl disable village  # Old service
   ```

### Rollback if Needed

If you encounter issues:

```bash
# Stop Docker service
sudo systemctl stop village-docker

# Restart old deployment
sudo systemctl start village
```

Both services use port 8000, so only one can run at a time.

## Security Considerations

### Container Security

- **Non-root user**: Container runs as unprivileged `village` user
- **Port binding**: Bound to `127.0.0.1` only (requires reverse proxy for external access)
- **Isolation**: Container has limited access to host system
- **Read-only config**: Environment file mounted read-only

### Host Security

- **Secrets**: `FLASK_SECRET_KEY` stored in `/opt/village/config/village.env` (mode 600)
- **File permissions**: All Village files owned by `village` user
- **Systemd**: Runs as root (required for Docker), but container runs as unprivileged user
- **Backups**: Backups with `--include-config` contain secrets (secure appropriately)

### Best Practices

1. **Use a reverse proxy** (nginx, Apache) for SSL/TLS
2. **Restrict access** to village.env (chmod 600)
3. **Regular updates**: Run `./scripts/deploy.sh` for latest code
4. **Monitor logs**: Check for suspicious activity
5. **Backup regularly**: Automate with cron
6. **Rotate secrets**: Change FLASK_SECRET_KEY periodically (invalidates sessions)

## Performance Tuning

### Gunicorn Workers

Adjust workers in `village.env`:

```bash
# Formula: (2 x CPU cores) + 1
WORKERS=9  # For 4-core system

# More workers = more concurrent requests, more memory
# Fewer workers = less memory, slower under load
```

### Worker Connections

For high-traffic sites:

```bash
WORKER_CONNECTIONS=2000
MAX_REQUESTS=5000
```

### Container Resources

Limit container resource usage:

```bash
# In start.sh, add flags:
docker run ... \
  --memory="1g" \
  --cpus="2.0" \
  ...
```

## Development vs. Production

**This Docker deployment is for PRODUCTION use.**

Key differences from development:

| Aspect | Development | Production (Docker) |
|--------|-------------|---------------------|
| Server | Flask dev server | Gunicorn |
| Workers | Single-threaded | Multi-process |
| Auto-reload | Yes | No (restart required) |
| Debug mode | Enabled | Disabled |
| Environment | `development` | `production` |
| Dependencies | Includes dev packages | Only production packages |

For development, use the direct Poetry installation in `village_py/`.

## Additional Resources

- **Detailed plan**: See [PLAN.md](PLAN.md) for architecture decisions
- **Docker documentation**: https://docs.docker.com/
- **Gunicorn configuration**: https://docs.gunicorn.org/
- **Village application**: See `village_py/README.md`

## Getting Help

**Check logs first:**
```bash
./scripts/logs.sh --follow
```

**Common commands:**
```bash
# Status
docker ps
sudo systemctl status village-docker

# Restart
sudo systemctl restart village-docker

# Check configuration
sudo cat /opt/village/config/village.env

# Check file ownership
ls -la /opt/village/data
ls -la /opt/village/logs

# Interactive debugging
./scripts/shell.sh
```

**If stuck:**
1. Check logs: `./scripts/logs.sh`
2. Check systemd: `sudo systemctl status village-docker`
3. Check container: `docker ps -a`
4. Review configuration: `sudo cat /opt/village/config/village.env`
5. Try rebuilding: `./scripts/build.sh --no-cache`
6. Check PLAN.md for troubleshooting section

## License

[Same as main Village project]
