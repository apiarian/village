# Village (Python Implementation) Deployment on Fedora

This repository contains all necessary scripts and configuration files to deploy the Python implementation of Village on a Fedora server.

## Overview

This deployment setup:
- Runs the village_py implementation on http://127.0.0.1:8000 using Gunicorn
- Includes systemd service for automatic startup and management
- Implements security hardening and proper logging
- Assumes cloudflared or another reverse proxy is already configured

## Files Included

- `setup.sh` - Main installation script
- `village.env` - Environment configuration for village_py
- `village.service` - Systemd service for village_py/Gunicorn
- `village-logrotate` - Log rotation configuration
- `maintenance.sh` - Maintenance and update script
- `health-check.sh` - Health monitoring script
- `firewall-setup.sh` - Firewall configuration script

## Quick Start

1. **Clone and setup:**
   ```bash
   # Clone the village repository
   git clone <village-repo-url> village
   cd village
   
   # Run the setup script
   cd village_py_deployment
   chmod +x *.sh
   ./setup.sh
   ```

3. **Configure environment variables:**
   ```bash
   sudo nano /etc/village.env
   # Set FLASK_SECRET_KEY to a random 32+ character string
   # Adjust timezone and other settings as needed
   ```

4. **Initialize Village:**
   ```bash
   # Initialize the repository
   sudo -u village bash -c 'cd /opt/village/village_py && /opt/village/venv/bin/poetry run initialize-repository'

   # Create your first user
   sudo -u village bash -c 'cd /opt/village/village_py && /opt/village/venv/bin/poetry run create-user'
   ```

5. **Start the service:**
   ```bash
   sudo systemctl enable --now village.service
   ```

6. **Configure your reverse proxy:**
   - If using cloudflared, configure it to proxy to http://127.0.0.1:8000
   - If using nginx or another reverse proxy, point it to http://127.0.0.1:8000

## Service Management

### Starting/Stopping Services
```bash
# Village service
sudo systemctl start village.service
sudo systemctl stop village.service
sudo systemctl restart village.service
sudo systemctl status village.service


```

### Viewing Logs
```bash
# Village logs
sudo journalctl -u village.service -f
tail -f /opt/village/logs/access.log
tail -f /opt/village/logs/error.log


```

## Maintenance

Use the included maintenance script for updates:
```bash
sudo ./maintenance.sh
```

This will:
- Pull latest code changes
- Update dependencies
- Restart services
- Run any migrations

## Security Notes

1. **Never expose port 8000 directly** - Always use a reverse proxy
2. **Keep secrets secure**:
   - Flask secret key in `/etc/village.env`
3. **Regular updates** - Run maintenance script weekly
4. **Monitor logs** - Check for unusual activity

## Backup

Important directories to backup:
- `/opt/village/data` - Village data and repository
- `/etc/village.env` - Configuration

## Troubleshooting

### Village service won't start
1. Check logs: `sudo journalctl -u village.service -n 100`
2. Verify environment file: `sudo cat /etc/village.env`
3. Test manually: `sudo -u village /opt/village/venv/bin/poetry run -- gunicorn -b 127.0.0.1:8000 village.app:app`

### Reverse proxy connection issues
1. Ensure Village is running on 127.0.0.1:8000
2. Check reverse proxy configuration
3. Verify firewall rules allow localhost connections

### Permission errors
```bash
# Fix ownership
sudo chown -R village:village /opt/village
sudo chmod 750 /opt/village/data
```

## Post-Installation Checklist

### ✅ Required Steps

1. **Environment Configuration**
   - [ ] Edit `/etc/village.env`
   - [ ] Set `FLASK_SECRET_KEY` to a secure random string (32+ characters)
   - [ ] Verify `FLASK_ENV=production`
   - [ ] Set correct timezone in `VILLAGE_DISPLAY_TIMEZONE`
   - [ ] Configure admin users if needed in `VILLAGE_ADMINS`

2. **Initialize Village Repository**
   ```bash
   sudo -u village bash -c 'cd /opt/village/village_py && /opt/village/venv/bin/poetry run initialize-repository'
   ```
   - [ ] Repository initialized successfully
   - [ ] Data directory created at `/opt/village/data`

3. **Create Initial Users**
   ```bash
   sudo -u village bash -c 'cd /opt/village/village_py && /opt/village/venv/bin/poetry run create-user'
   ```
   - [ ] At least one admin user created
   - [ ] Passwords set securely

4. **Reverse Proxy Setup**
   - [ ] Configured reverse proxy (cloudflared, nginx, etc.)
   - [ ] Proxies to `http://127.0.0.1:8000`
   - [ ] SSL/TLS properly configured

5. **Firewall Configuration**
   ```bash
   sudo ./firewall-setup.sh
   ```
   - [ ] Port 8000 blocked from external access
   - [ ] Only localhost can access port 8000

6. **Start Service**
   ```bash
   sudo systemctl enable --now village.service
   ```
   - [ ] Service started successfully
   - [ ] Service enabled for auto-start

7. **Verification**
   ```bash
   ./health-check.sh
   ```
   - [ ] All health checks pass
   - [ ] Village responds on http://127.0.0.1:8000
   - [ ] Public URL is accessible through reverse proxy

### 📋 Optional but Recommended

**Security Hardening**
- [ ] SELinux configured (if using)
- [ ] Regular system updates scheduled
- [ ] Backup strategy implemented
- [ ] Monitoring/alerting configured

**Performance Tuning**
- [ ] Adjust Gunicorn workers in `/etc/village.env` based on CPU cores
- [ ] Configure Nginx as reverse proxy (optional, for static files)
- [ ] Enable Cloudflare caching and security features

**Maintenance Planning**
- [ ] Schedule weekly maintenance runs
- [ ] Set up log monitoring
- [ ] Document custom configurations

### 🎉 Success Indicators

When everything is working correctly:
1. Village is accessible via your public URL
2. Users can log in and create posts
3. No errors in service logs
4. Services restart automatically after reboot
5. Regular backups are being created

## Support

For Village specific issues, refer to the Village documentation.
For deployment issues, check:
1. Service logs
2. Reverse proxy logs
3. System logs: `sudo journalctl -xe`
