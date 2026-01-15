# Village Docker Deployment - Design Notes

## Overview

This document contains design decisions and architecture notes for the Village Docker deployment. For usage instructions, see [README.md](README.md).

## Design Goals

1. **Simplicity**: Docker handles all dependencies and environment setup
2. **Isolation**: Application runs in a container, isolated from host system
3. **Persistence**: Data directory and logs persist outside the container
4. **No Registry**: Build and run locally, no need to push to Docker Hub
5. **Production-Ready**: Optimized for server deployment with Gunicorn
6. **Maintainability**: Easy to update, backup, and troubleshoot

## Key Architecture Decisions

### Base Image: `python:3.11-alpine`
- **Why Alpine?** Smallest footprint (good for home server)
- **Fallback plan:** Switch to `python:3.11-slim` if package compatibility issues arise
- **Status:** Alpine works fine for our dependencies

### Multi-Stage Build
- **Builder stage:** Install Poetry and dependencies (includes build tools)
- **Runtime stage:** Copy only what's needed (smaller, more secure)
- **Result:** Faster builds (cached layers), smaller final image

### Build Context = Repository Root
- Docker build runs from repository root (`village/`)
- Dockerfile at `village_docker/Dockerfile` references both:
  - `village_py/` (application code)
  - `village_docker/` (deployment files)
- Build command: `docker build -f village_docker/Dockerfile -t village:latest .`

### Configurable UID (Default: 10000)
- Container runs as non-root `village` user
- UID configurable at build time: `--build-arg VILLAGE_UID=991`
- Default 10000 chosen to avoid conflicts with system users (typically < 1000)
- **Critical:** Container UID must match host UID for volume permissions
- Scripts auto-detect host UID and build accordingly

### Volume Mounts for Persistence
- `/opt/village/data` → Village repository data (git-annex)
- `/opt/village/logs` → Application logs (access.log, error.log)
- `/opt/village/config/village.env` → Environment variables (secrets)
- Code lives in container (`/app/`), data lives on host (survives updates)

### Systemd Service Required
- Service runs as root (Docker daemon requires it)
- Container runs as unprivileged `village` user (security)
- `Type=oneshot` with `RemainAfterExit=yes` (appropriate for container management)
- Auto-restart on failure, starts on boot

### No docker-compose
- Simple single-container application
- Wrapped in shell scripts (`start.sh`, `stop.sh`, etc.)
- No need for compose complexity

### Gunicorn Production Server
- 4 workers by default (configurable via env vars)
- `gevent` worker class for async I/O
- Separate access.log and error.log files
- Health check using `/about` endpoint

### Safety Checks in Entrypoint
- Refuses to start if `CONFIG_NOT_REVIEWED=true` is set
- Validates `FLASK_SECRET_KEY` is not default "CHANGE_ME"
- Validates `FLASK_SECRET_KEY` minimum length (32 chars)
- Checks repository is initialized (settings.yaml exists)
- Verifies data/logs directories are writable

## Dual-Clone Architecture

The setup supports a development workflow with two repository clones:

1. **Personal clone:** User's working copy (e.g., `~/village`)
   - For development, testing, running scripts
   - You work here, commit here, push from here

2. **Deployment clone:** Production copy at `/opt/village/village`
   - Created automatically by `setup.sh` (clones from your git remote)
   - Independent git repository (updates via `git pull`)
   - Used for building Docker images and running containers

**How it works:**
- `common.sh` detects where scripts are running from:
  - `SCRIPT_REPO`: Current location (could be `~/village` or `/opt/village/village`)
  - `REPO_DIR`: Always `/opt/village/village` (deployment location)
- `setup.sh`: Auto-clones to deployment location if you run it from personal clone
- `build.sh`: Builds from wherever you run it (uses `SCRIPT_REPO`)
- `deploy.sh`: Always targets deployment location (uses `REPO_DIR`)

**Result:** You can develop in `~/village` and deploy to `/opt/village/village` seamlessly.

## Container vs Host Paths

**Inside Container:**
```
/app/                          # Application code (copied during build)
├── pyproject.toml
├── poetry.lock
├── village/                   # Python package
└── entrypoint.sh

/opt/village/data              # Mounted from host (persistent)
/opt/village/logs              # Mounted from host (persistent)
```

**On Host:**
```
/opt/village/
├── village/                   # Git repository (deployment clone)
│   ├── village_py/            # Application source
│   └── village_docker/        # Deployment files (Dockerfile, scripts)
├── data/                      # Repository data (mounted to container)
├── logs/                      # Application logs (mounted to container)
├── config/
│   └── village.env            # Environment config (loaded as env vars)
└── backups/                   # Backup tarballs
```

## Testing Checklist

### Fresh Installation Test
- [ ] Clone repository to personal location (e.g., `~/village`)
- [ ] Run `sudo ./scripts/setup.sh` from personal clone
- [ ] Verify deployment clone created at `/opt/village/village`
- [ ] Edit `/opt/village/config/village.env` (set FLASK_SECRET_KEY)
- [ ] Run `./scripts/build.sh` from either location
- [ ] Run `./scripts/run-script.sh initialize-repository`
- [ ] Run `./scripts/run-script.sh create-user`
- [ ] Install systemd service: `sudo cp village-docker.service /etc/systemd/system/`
- [ ] Enable service: `sudo systemctl enable village-docker`
- [ ] Start service: `sudo systemctl start village-docker`
- [ ] Verify container running: `docker ps | grep village`
- [ ] Verify application accessible: `curl http://localhost:8000/about`
- [ ] Check logs: `sudo journalctl -u village-docker -n 50`
- [ ] Create a post, verify data persists in `/opt/village/data`
- [ ] Restart service: `sudo systemctl restart village-docker`
- [ ] Verify data still present after restart

### Update/Deploy Test
- [ ] Run `./scripts/deploy.sh` from either location
- [ ] Verify it pulls code in `/opt/village/village` (not personal clone)
- [ ] Verify it rebuilds and restarts via systemd
- [ ] Verify application still works after deploy

### Backup/Restore Test
- [ ] Create backup: `./scripts/backup.sh`
- [ ] Create backup with config: `./scripts/backup.sh --include-config`
- [ ] Verify tarballs created in `/opt/village/backups/`
- [ ] Stop service: `sudo systemctl stop village-docker`
- [ ] Modify some data in `/opt/village/data`
- [ ] Restore backup: `sudo tar -xzf /opt/village/backups/village-data-*.tar.gz -C /`
- [ ] Start service: `sudo systemctl start village-docker`
- [ ] Verify data restored correctly

### UID Configuration Test
- [ ] Check current village user UID: `id -u village`
- [ ] Rebuild with custom UID: `./scripts/build.sh --uid 991`
- [ ] Verify container runs with specified UID
- [ ] Verify file permissions work correctly

### Script Portability Test
- [ ] Run `./scripts/build.sh` from personal clone (`~/village/village_docker/scripts/`)
- [ ] Run `./scripts/build.sh` from deployment (`/opt/village/village/village_docker/scripts/`)
- [ ] Verify both work and build from correct location
- [ ] Same test for `start.sh`, `stop.sh`, `logs.sh`, `shell.sh`, `run-script.sh`

### Migration from Old Deployment Test
- [ ] Set up old non-Docker deployment (if you have one)
- [ ] Backup old data: `sudo tar czf ~/village-old-backup.tar.gz /opt/village/data`
- [ ] Stop old service: `sudo systemctl stop village`
- [ ] Install Docker
- [ ] Run Docker setup: `sudo ./scripts/setup.sh`
- [ ] Copy config: `sudo cp /etc/village.env /opt/village/config/village.env`
- [ ] Build and start Docker version
- [ ] Verify all data present
- [ ] Test rollback: stop Docker, start old service

## Known Issues / Edge Cases

### None Currently
All identified issues have been fixed:
- ✅ Error messages now say "village user" instead of hardcoded UIDs
- ✅ Permission issues with config file automatically handled (2026-01-15)

## Future Enhancements (If Needed)

These are NOT needed now, but possible if requirements change:

1. **Health endpoint improvements:** Custom health check beyond `/about`
2. **Metrics/monitoring:** Prometheus exporter if needed
3. **SSL in container:** Currently expects reverse proxy to handle
4. **docker-compose:** Only if we add more containers (database, redis, etc.)
5. **Switch to slim:** Only if Alpine has package compatibility issues

---

**Status:** Implementation complete, awaiting testing
**Next Steps:**
1. Test on fresh host (validate entire workflow)
2. Test migration from existing direct Python deployment

**Recent Changes:**
- 2026-01-15: Added automatic sync and permission handling to run-script.sh, start.sh, and shell.sh
  - Scripts detect if running from personal clone (~/village) vs deployment location (/opt/village/village)
  - If from personal clone: syncs code to deployment, then execs deployment script as village user
  - If from deployment: just execs as village user
  - Village user only needs access to /opt/village (not user home directories)
  - Fixes "permission denied" errors on /opt/village/config/village.env
  - Users can run from ~/village without permission issues

**Last Updated:** 2026-01-15
