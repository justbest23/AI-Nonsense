Okay, let's break down deploying STIG Manager with Podman quadlets to achieve external HTTPS access.

The core challenge, as you noted, is that the `stigman-api` requires TLS for non-localhost connections. The Nginx reverse proxy is the standard solution for this: it handles incoming HTTPS traffic, terminates the TLS, and forwards plain HTTP requests to the backend services (`stigman-api`, `keycloak`) within the pod's internal network (via `localhost`).

Here's a step-by-step guide and the corresponding quadlet files.

**Assumptions:**

1.  You are running Podman with systemd integration enabled.
2.  You have a valid domain name (e.g., `stigman.yourdomain.com`) pointing to the host machine where you'll run the pod.
3.  You have obtained valid TLS certificates (e.g., via Let's Encrypt/Certbot) for that domain (`fullchain.pem` and `privkey.pem`).
4.  You will place the quadlet files in `/etc/containers/systemd/` (for system-wide services) or `~/.config/containers/systemd/` (for user services). We'll use the system path here, adjust commands if using user services (`--user` flag).
5.  Replace placeholders like `<your_external_domain>`, `<generate_strong_password>`, `<your_admin_user>`, `<your_admin_password>`, `<client_secret_you_generate>` with actual values.

**1. Create Host Directories for Persistent Data and Configuration**

These directories will be mounted into the containers.

```bash
sudo mkdir -p /var/lib/stigman/mysql
sudo mkdir -p /var/lib/stigman/keycloak # Might not be strictly needed if Keycloak uses DB mainly, but good practice
sudo mkdir -p /etc/stigman/nginx/conf.d
sudo mkdir -p /etc/stigman/nginx/certs
sudo mkdir -p /var/lib/stigman/client # For STIG Manager Client static files
# Optional: Set permissions if needed, e.g., for MySQL data
# sudo chown -R 27:27 /var/lib/stigman/mysql # If MySQL runs as user 27 (common)
```

**2. Place TLS Certificates**

Copy your certificate and private key to the Nginx certs directory:

```bash
sudo cp /path/to/your/fullchain.pem /etc/stigman/nginx/certs/stigman.crt
sudo cp /path/to/your/privkey.pem /etc/stigman/nginx/certs/stigman.key
sudo chmod 600 /etc/stigman/nginx/certs/stigman.key # Secure the private key
```

**3. Prepare STIG Manager Client Files**

The standard STIG Manager deployment uses a separate client build. You need to download or build the static frontend files and place them in `/var/lib/stigman/client`.

* Go to the STIG Manager Client releases page on GitHub (part of the main STIG Manager repo usually).
* Download the latest release artifact (often a `.zip` or `.tar.gz` file containing the `build` directory).
* Extract the contents *into* `/var/lib/stigman/client`. After extraction, `/var/lib/stigman/client` should contain `index.html`, `static/`, etc.

```bash
# Example (adjust version/filename):
# cd /tmp
# wget https://github.com/NUWCDIVNPT/stig-manager/releases/download/v<client_version>/stig-manager-client-v<client_version>.zip
# sudo unzip stig-manager-client-v<client_version>.zip -d /var/lib/stigman/client
# sudo chown -R root:root /var/lib/stigman/client # Nginx usually runs as root initially
```

**4. Create the Nginx Configuration File**

Create `/etc/stigman/nginx/conf.d/stigman.conf`:

```nginx
# /etc/stigman/nginx/conf.d/stigman.conf

# Increase buffer size for large uploads/requests if needed
client_max_body_size 50M;

# Redirect HTTP to HTTPS (Optional but Recommended)
server {
    listen 80;
    server_name <your_external_domain>;

    # LetsEncrypt ACME challenge handling (if applicable)
    location /.well-known/acme-challenge/ {
        root /var/www/html; # Or adjust as needed for your ACME client
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# Main HTTPS Server
server {
    listen 443 ssl http2;
    server_name <your_external_domain>;

    ssl_certificate /etc/nginx/certs/stigman.crt;
    ssl_certificate_key /etc/nginx/certs/stigman.key;

    # Modern TLS settings (adjust as needed for compatibility)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;

    # HSTS (Optional but Recommended)
    # add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Resolve backend services within the pod via localhost
    resolver 127.0.0.11 valid=30s; # Podman's internal DNS resolver

    # Proxy Keycloak requests
    location /auth/ {
        proxy_pass http://localhost:8080/auth/; # Keycloak's default HTTP port
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme; # Crucial for Keycloak behind proxy
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_buffering on;
        proxy_http_version 1.1;
    }

    # Proxy API requests
    location /api/ {
        proxy_pass http://localhost:54000/api/; # STIGMan API default port
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_buffering on;
        proxy_http_version 1.1;
    }

    # Serve STIG Manager Client static files
    location / {
        root /usr/share/nginx/html; # Corresponds to the volume mount below
        try_files $uri $uri/ /index.html; # Standard setup for SPAs
    }

    # Optional: Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    # add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';" always; # Adjust CSP as needed

    access_log /var/log/nginx/stigman_access.log;
    error_log /var/log/nginx/stigman_error.log;
}
```

**5. Create Quadlet Files**

Place these files in `/etc/containers/systemd/` (or `~/.config/containers/systemd/`).

**a) Pod Definition (`stigman.pod`)**

```ini
# /etc/containers/systemd/stigman.pod

[Unit]
Description=Pod for STIG Manager Application Suite
Requires=network-online.target # Ensure network is up
After=network-online.target
Wants=mysql.service keycloak.service stigman-api.service nginx-revproxy.service # Start containers with the pod

[Pod]
PublishPort=80:80   # For HTTP->HTTPS redirect and ACME challenge
PublishPort=443:443 # Main HTTPS access

[Install]
WantedBy=multi-user.target # Or default.target if using user units
```

**b) MySQL Container (`mysql.container`)**

```ini
# /etc/containers/systemd/mysql.container

[Unit]
Description=MySQL Database for STIG Manager
Requires=stigman.pod
PartOf=stigman.pod
After=stigman.pod

[Container]
Image=docker.io/library/mysql:8.0
Pod=stigman.pod
Network=container: # Handled by Podman when Pod= is specified
Volume=/var/lib/stigman/mysql:/var/lib/mysql:Z # Use :Z for private SELinux context

Environment=MYSQL_ROOT_PASSWORD=<generate_strong_password>
Environment=MYSQL_DATABASE=stigman
Environment=MYSQL_USER=stigman
Environment=MYSQL_PASSWORD=<generate_strong_password> # Use a different password than root

# Add necessary MySQL arguments if needed, e.g., for character set
# Command=--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci

Restart=on-failure
SecurityLabelDisable=false # Keep SELinux enabled if possible

[Install]
WantedBy=stigman.pod
```
*Note on `MYSQL_PASSWORD`: Ensure this matches `STIGMAN_DB_PASSWORD` and `KC_DB_PASSWORD`.*

**c) Keycloak Container (`keycloak.container`)**

```ini
# /etc/containers/systemd/keycloak.container

[Unit]
Description=Keycloak Authentication Server for STIG Manager
Requires=mysql.service stigman.pod
PartOf=stigman.pod
After=mysql.service

[Container]
Image=quay.io/keycloak/keycloak:21.1.1 # Use a specific, STIGMan-compatible version
Pod=stigman.pod
Network=container:

# Optional: Persist Keycloak themes/providers if customized
# Volume=/var/lib/stigman/keycloak:/opt/keycloak/data:Z

# Database Configuration (uses the same MySQL instance)
Environment=KC_DB=mysql
Environment=KC_DB_URL_HOST=localhost # Communicate within the pod
Environment=KC_DB_URL_PORT=3306
Environment=KC_DB_URL_DATABASE=stigman
Environment=KC_DB_USERNAME=stigman
Environment=KC_DB_PASSWORD=<generate_strong_password> # Must match MySQL user password

# Proxy and Hostname Configuration (CRITICAL)
Environment=KC_PROXY=edge # Tells Keycloak it's behind a reverse proxy
Environment=KC_HOSTNAME=<your_external_domain> # Public facing domain
Environment=KC_HTTP_ENABLED=true # Allow internal HTTP communication
Environment=KC_HTTP_RELATIVE_PATH=/auth # Base path expected by Nginx config

# Admin User (Change on first login!)
Environment=KEYCLOAK_ADMIN=<your_admin_user>
Environment=KEYCLOAK_ADMIN_PASSWORD=<your_admin_password>

# Keycloak Start Command (modern versions configure via ENV variables)
# Command=start --optimized # Or start-dev for initial setup/testing
# If using older Keycloak versions, adjust ENV vars and command accordingly

Restart=on-failure
SecurityLabelDisable=false

[Install]
WantedBy=stigman.pod
```
*Note on `KC_DB_PASSWORD`: Must match the `MYSQL_PASSWORD` set for the `stigman` user.*
*Note on `KC_HOSTNAME`: This MUST be the external domain name.*

**d) STIG Manager API Container (`stigman-api.container`)**

```ini
# /etc/containers/systemd/stigman-api.container

[Unit]
Description=STIG Manager API Server
Requires=mysql.service keycloak.service stigman.pod
PartOf=stigman.pod
After=keycloak.service # API depends on Keycloak being somewhat ready

[Container]
Image=docker.io/nuwcdivnpt/stig-manager-api:latest # Pin to a specific version for stability
Pod=stigman.pod
Network=container:

# Database Connection
Environment=STIGMAN_DB_HOST=localhost
Environment=STIGMAN_DB_PORT=3306
Environment=STIGMAN_DB_NAME=stigman
Environment=STIGMAN_DB_USER=stigman
Environment=STIGMAN_DB_PASSWORD=<generate_strong_password> # Must match MySQL user password

# OIDC/Keycloak Connection (CRITICAL)
Environment=STIGMAN_OIDC_PROVIDER=keycloak
Environment=STIGMAN_KEYCLOAK_AUTH_SERVER_URL=http://localhost:8080/auth # Internal URL to Keycloak
Environment=STIGMAN_KEYCLOAK_REALM=stigman # Default realm, confirm if changed
Environment=STIGMAN_KEYCLOAK_CLIENT_ID=stig-manager # Default client ID, confirm if changed
Environment=STIGMAN_KEYCLOAK_CLIENT_SECRET=<client_secret_you_generate> # MUST match secret in Keycloak client config
Environment=STIGMAN_API_URL=https://<your_external_domain>/api # Public API URL
Environment=STIGMAN_CLIENT_URL=https://<your_external_domain> # Public Client/UI URL

# Other Settings
Environment=NODE_ENV=production
# Environment=STIGMAN_LOG_LEVEL=info # Adjust log level if needed (debug, warn, error)

Restart=on-failure
SecurityLabelDisable=false

[Install]
WantedBy=stigman.pod
```
*Note on `STIGMAN_DB_PASSWORD`: Must match the `MYSQL_PASSWORD` set for the `stigman` user.*
*Note on `STIGMAN_KEYCLOAK_CLIENT_SECRET`: You need to configure this same secret within the Keycloak admin console for the `stig-manager` client in the `stigman` realm.*

**e) Nginx Reverse Proxy Container (`nginx-revproxy.container`)**

```ini
# /etc/containers/systemd/nginx-revproxy.container

[Unit]
Description=Nginx Reverse Proxy for STIG Manager
Requires=stigman-api.service keycloak.service stigman.pod
PartOf=stigman.pod
After=stigman-api.service keycloak.service # Start after backends are likely up

[Container]
Image=docker.io/library/nginx:stable
Pod=stigman.pod
Network=container:

Volume=/etc/stigman/nginx/conf.d:/etc/nginx/conf.d:ro,Z # Mount config read-only
Volume=/etc/stigman/nginx/certs:/etc/nginx/certs:ro,Z # Mount certs read-only
Volume=/var/lib/stigman/client:/usr/share/nginx/html:ro,Z # Mount client files read-only

# Create log directories if they don't exist inside container (Nginx might fail otherwise)
ExecStartPre=mkdir -p /var/log/nginx

Restart=on-failure
SecurityLabelDisable=false

[Install]
WantedBy=stigman.pod
```
*Note the `:ro,Z` flags for read-only mounts with SELinux context.*

**6. Deploy and Manage**

```bash
# Reload systemd to detect new unit files
sudo systemctl daemon-reload

# Enable the pod to start on boot (optional)
sudo systemctl enable stigman.pod

# Start the pod and all its containers
sudo systemctl start stigman.pod

# Check the status
sudo systemctl status stigman.pod mysql.service keycloak.service stigman-api.service nginx-revproxy.service

# View logs for the whole pod
sudo journalctl -u stigman.pod -f

# View logs for a specific container
sudo journalctl -u mysql.service -f
sudo journalctl -u keycloak.service -f
sudo journalctl -u stigman-api.service -f
sudo journalctl -u nginx-revproxy.service -f
# Or using podman
# sudo podman logs <container_name_or_id>
```

**7. Initial Keycloak Configuration (Crucial!)**

1.  Access Keycloak Admin Console: Go to `https://<your_external_domain>/auth/` and click on "Administration Console".
2.  Login: Use the `KEYCLOAK_ADMIN`/`KEYCLOAK_ADMIN_PASSWORD` you set. **Change this password immediately.**
3.  Select Realm: Make sure you are in the `stigman` realm (it might be created automatically based on STIGMan docs/scripts, or you might need to import/create it - consult STIG Manager setup docs).
4.  Configure Client:
    * Navigate to `Clients`.
    * Find the `stig-manager` client.
    * Go to the `Credentials` tab.
    * Set the `Client secret` to the exact value you used for `STIGMAN_KEYCLOAK_CLIENT_SECRET` in the `stigman-api.container` file.
    * Ensure `Client authentication` is enabled and `Valid redirect URIs` includes `https://<your_external_domain>/*` (or more specific paths if known). Check `Web origins` and `Root URL` are also set correctly (`https://<your_external_domain>`). Save changes.

**8. Access STIG Manager**

Navigate to `https://<your_external_domain>/`. You should be redirected to Keycloak for login, and then back to the STIG Manager interface.

**Important Considerations:**

* **Passwords & Secrets:** The passwords are shown in plain text here. For production, use Podman secrets or another secrets management solution. Avoid committing files with plain text secrets to version control.
* **Keycloak Setup:** Keycloak might need initial setup beyond just the client secret (e.g., realm import if not automatic). Refer to the official STIG Manager documentation for the exact Keycloak setup steps.
* **Database Initialization:** The first time `stigman-api` starts, it should run database migrations. Check its logs (`journalctl -u stigman-api.service -f`) for any errors.
* **SELinux:** The `:Z` flag on volume mounts tells Podman to relabel the host directory content for the container's exclusive use. If multiple containers need shared write access (not the case here), you might use `:z`. If SELinux still causes issues, check `sudo ausearch -m avc -ts recent` and consider temporary permissive mode (`sudo setenforce 0`) for debugging, but aim to fix the policy.
* **Firewall:** Ensure your host's firewall allows incoming traffic on ports 80 and 443.
* **Resource Limits:** Add `Memory=` and `CPU=` limits to the `[Container]` sections if needed to prevent resource exhaustion.
* **Updates:** Remember to update the image tags (`mysql:8.0`, `keycloak:21.1.1`, `stig-manager-api:latest`, `nginx:stable`) periodically and test updates carefully. Pinning to specific versions (like for Keycloak) is generally safer than `latest`.

This setup provides a robust, systemd-managed deployment of STIG Manager accessible externally via HTTPS using Podman quadlets. Remember to replace all placeholders and carefully follow the Keycloak client configuration steps.
