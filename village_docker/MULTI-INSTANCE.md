# Multi-Instance Village Docker Design

## Overview

Support running multiple Village Docker instances on a single host. Each
instance has its own data, config, logs, and backups, but all share a single
Docker image and a single `village` system user.

## Directory Layout

```
/opt/village/
├── village/                    # Shared git repository (deployment clone)
│   ├── village_py/
│   └── village_docker/
└── instances/
    ├── mysite/
    │   ├── data/               # Village repository data
    │   ├── logs/               # Application logs
    │   ├── config/
    │   │   └── village.env     # Instance configuration
    │   └── backups/
    ├── photos/
    │   ├── data/
    │   ├── logs/
    │   ├── config/
    │   │   └── village.env
    │   └── backups/
    └── ...
```

## Naming Conventions

Everything derives from the instance name:

| Thing              | Pattern                                           | Example (instance: `mysite`)                         |
|--------------------|---------------------------------------------------|------------------------------------------------------|
| Base directory     | `/opt/village/instances/<name>`                    | `/opt/village/instances/mysite`                       |
| Data directory     | `/opt/village/instances/<name>/data`               | `/opt/village/instances/mysite/data`                  |
| Logs directory     | `/opt/village/instances/<name>/logs`               | `/opt/village/instances/mysite/logs`                  |
| Config file        | `/opt/village/instances/<name>/config/village.env` | `/opt/village/instances/mysite/config/village.env`    |
| Backups directory  | `/opt/village/instances/<name>/backups`            | `/opt/village/instances/mysite/backups`               |
| Container name     | `village-<name>`                                   | `village-mysite`                                      |
| Systemd service    | `village-docker@<name>.service`                    | `village-docker@mysite.service`                       |
| Host port          | Configured in village.env (`HOST_PORT`)            | e.g., `HOST_PORT=8001`                                |

## How Scripts Work

Every script requires `VILLAGE_INSTANCE` to be set. There are two ways to
provide it:

1. **Environment variable**: `VILLAGE_INSTANCE=mysite ./scripts/start.sh`
2. **Command-line flag**: `./scripts/start.sh --instance mysite`

The `--instance` flag is checked first and overrides the environment variable.

If `VILLAGE_INSTANCE` is not set and `--instance` is not provided, the script
prints an error and exits.

### common.sh Changes

`common.sh` reads `VILLAGE_INSTANCE` and derives all paths:

```bash
VILLAGE_INSTANCE="${VILLAGE_INSTANCE:?VILLAGE_INSTANCE is required}"
VILLAGE_BASE_DIR="/opt/village/instances/${VILLAGE_INSTANCE}"
CONTAINER_NAME="village-${VILLAGE_INSTANCE}"
# ... rest derived from VILLAGE_BASE_DIR as before
```

The shared repo stays at `/opt/village/village` (the `REPO_DIR` variable).

### Instance-Aware Scripts

All scripts that currently exist continue to work, but they now operate on a
specific instance. The `--instance` flag is parsed early (before other flags)
and stripped from the argument list so downstream parsing is unaffected.

Scripts that need the "run as village user" pattern (`start.sh`,
`run-script.sh`, `shell.sh`) pass `VILLAGE_INSTANCE` through when re-executing.

## Port Configuration

Each instance's `village.env` must define `HOST_PORT`:

```bash
# In /opt/village/instances/mysite/config/village.env
HOST_PORT=8001
```

`start.sh` reads `HOST_PORT` from the env file and uses it for the `-p` flag:

```bash
-p 127.0.0.1:${HOST_PORT}:8000
```

The container always listens on 8000 internally. Only the host-side port
varies.

The `village.env.example` file gets `HOST_PORT` added with a comment
explaining that each instance needs a unique port.

## setup.sh Changes

`setup.sh` creates the instance directory structure:

```bash
sudo ./scripts/setup.sh --instance mysite
```

This:
1. Creates the `village` user (if needed) — same as before
2. Creates `/opt/village/instances/mysite/{data,logs,config,backups}`
3. Sets ownership to `village:village`
4. Copies `village.env.example` to the instance config dir
5. Prints next steps (edit config, build image, initialize, create user)

The shared repo at `/opt/village/village` is managed separately — `setup.sh`
still creates/updates it, but it's shared across all instances.

## Systemd Template Unit

Replace `village-docker.service` with `village-docker@.service` (systemd
template unit):

```ini
[Unit]
Description=Village Web Application (Docker) - %i
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=VILLAGE_INSTANCE=%i
WorkingDirectory=/opt/village/village/village_docker
ExecStartPre=-/usr/bin/docker stop village-%i
ExecStartPre=-/usr/bin/docker rm village-%i
ExecStart=/opt/village/village/village_docker/scripts/start.sh --instance %i
ExecStop=/opt/village/village/village_docker/scripts/stop.sh --instance %i
Restart=on-failure
RestartSec=10
PrivateTmp=yes
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

Usage:
```bash
sudo systemctl enable village-docker@mysite
sudo systemctl start village-docker@mysite
sudo systemctl status village-docker@mysite
```

## deploy.sh Changes

`deploy.sh` always pulls code and rebuilds the image, regardless of whether
it's deploying one instance or all. The pull and build are idempotent — if
nothing changed, they're fast no-ops.

It gains an `--all` flag in addition to `--instance`:

- `./scripts/deploy.sh --instance mysite` — pull, build, restart one instance
- `./scripts/deploy.sh --all` — pull, build, restart all instances

With `--all`, it iterates over `/opt/village/instances/*/` and restarts each
container after the single shared pull and build.

## Instance Management: instances.sh

New script `instances.sh` for listing and managing instances:

```bash
# List all instances with status
./scripts/instances.sh list

# Output:
# INSTANCE    PORT    CONTAINER         STATUS
# mysite      8001    village-mysite    running
# photos      8002    village-photos    stopped
```

This is a simple convenience wrapper — it scans
`/opt/village/instances/*/config/village.env` for `HOST_PORT` and checks
Docker container status.

## Migration Script: migrate.sh

For migrating an existing single-instance deployment to the new layout:

```bash
sudo ./scripts/migrate.sh --instance mysite
```

This:
1. Checks that the old layout exists (`/opt/village/{data,logs,config}`)
2. Creates the new instance directory structure
3. Moves data: `/opt/village/data` → `/opt/village/instances/mysite/data`
4. Moves logs: `/opt/village/logs` → `/opt/village/instances/mysite/logs`
5. Moves config: `/opt/village/config` → `/opt/village/instances/mysite/config`
6. Moves backups: `/opt/village/backups` → `/opt/village/instances/mysite/backups`
7. Adds `HOST_PORT=8000` to the migrated `village.env` (preserving existing port)
8. Sets ownership
9. Removes/uninstalls old `village-docker.service`
10. Installs new `village-docker@mysite.service`
11. Prints summary and next steps

The script is cautious — it checks for conflicts, won't overwrite existing
instance directories, and can be run with `--dry-run` to preview changes.

## Changes Summary

| File                          | Change                                                        |
|-------------------------------|---------------------------------------------------------------|
| `common.sh`                  | Require `VILLAGE_INSTANCE`, derive all paths from it          |
| `start.sh`                   | Read `HOST_PORT` from env file, use for port mapping          |
| `stop.sh`                    | Add `--instance` flag (via common.sh)                         |
| `build.sh`                   | No `--instance` flag — image is shared across all instances   |
| `deploy.sh`                  | Add `--instance` and `--all` flags; always pulls and rebuilds |
| `setup.sh`                   | Add `--instance` flag, create instance dirs                   |
| `run-script.sh`              | Add `--instance` flag (via common.sh)                         |
| `shell.sh`                   | Add `--instance` flag (via common.sh)                         |
| `logs.sh`                    | Add `--instance` flag (via common.sh)                         |
| `backup.sh`                  | Add `--instance` flag (via common.sh)                         |
| `village-docker.service`     | Replace with `village-docker@.service` template               |
| `config/village.env.example` | Add `HOST_PORT` variable                                      |
| `instances.sh` (new)         | List instances with status                                    |
| `migrate.sh` (new)           | Migrate old single-instance layout to new multi-instance      |
| `README.md`                  | Update for multi-instance                                     |
| `PLAN.md`                    | Update for multi-instance                                     |
