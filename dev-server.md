# Village Development Server

Work on this project is being done on a tiny Digital Ocean Fedora Droplet.

System setup and other information will be stored on this file for future
rebuilds and as a basis for deployment docs, if and when we need those.

## Machine Setup
- Get a minimal Digital Ocean Droplet running Fedora.
- Give it a domain name of some kind (subdomain is fine).
- Install useful software
  - `dnf install firewalld; systemctl enable firewalld; systemctl start firewalld`

## Reverse Proxy

Install nginx to act as a reverse proxy.
```
dnf install nginx
firewall-cmd --permanent --zone=public --add-service=http # to open port 80
firewall-cmd --permanent --zone=public --add-service=https # to open port 443
firewall-cmd --reload
systemctl enable nginx; systemctl start nginx;

mkdir -p /var/www/[domain]/html
chown -R adminuser:admingroup /var/www/[domain]/html
chmod -R 755 /var/www/[domain]
chcon -Rt httpd_sys_content_t /var/www
# put something interesting in /var/www/[domain]/html/index.html
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
```

Add the following to `/etc/nginx/sites-available/[domain].conf`
```
server {
  listen 80;
  listen [::]:80;

  root /var/www/[domain]/html;
  index index.html index.htm;

  server_name [domain];

  location / {
    try_files $uri $uri/ =404;
  }
}
```

```
ln -s /etc/nginx/sites-available/[domain].conf /etc/nginx/sites-enabled/
```

Replace the `include /etc/nginx/conf.d/*.conf` line with
`include /etc/nginx/sites-enabled/*.conf`, and comment out the `server { }`
block below it.


Enable ssl on the server...
```
dnf install certbot python-certbot-nginx
... tbd
```
