## Before Starting:

    Replace Placeholders: Carefully replace <your_external_domain>, <generate_strong_password>, <your_admin_user>, <your_admin_password>, and <client_secret_you_generate> in the files above with your actual values. Use strong, unique passwords and secrets.
    Create Host Directories:
```sh

sudo mkdir -p /var/lib/stigman/mysql
sudo mkdir -p /etc/stigman/nginx/conf.d
sudo mkdir -p /etc/stigman/nginx/certs
sudo mkdir -p /var/lib/stigman/client

# Optional: Set ownership if needed, e.g., for MySQL if it doesn't run as root
# sudo chown -R 27:27 /var/lib/stigman/mysql # Check MySQL image user ID if needed
```
Place Nginx Config: Save the Nginx configuration content into /etc/stigman/nginx/conf.d/stigman.conf on the host.
Place TLS Certificates: Copy your certificate (fullchain.pem or similar) and private key (privkey.pem or similar) to the host directory /etc/stigman/nginx/certs/. Rename them to stigman.crt and stigman.key respectively, as expected by the Nginx config and quadlet mount.

```sh

sudo cp /path/to/your/fullchain.pem /etc/stigman/nginx/certs/stigman.crt
sudo cp /path/to/your/privkey.pem /etc/stigman/nginx/certs/stigman.key
sudo chmod 600 /etc/stigman/nginx/certs/stigman.key # Secure the private key
```
Place STIG Manager Client Files: Download the STIG Manager Client build artifacts (usually a .zip or .tar.gz from the GitHub releases page) and extract its contents into /var/lib/stigman/client on the host. The index.html file should end up directly inside /var/lib/stigman/client.
```sh

    # Example (adjust version/filename):
    # cd /tmp
    # wget https://github.com/NUWCDIVNPT/stig-manager/releases/download/v<client_version>/stig-manager-client-v<client_version>.zip
    # sudo unzip stig-manager-client-v<client_version>.zip -d /var/lib/stigman/client
```
Save Quadlet Files: Place the .pod and .container files into /etc/containers/systemd/ (or ~/.config/containers/systemd/ if running as a user).

Deployment and Management:
```sh

# Reload systemd to recognize the new files
sudo systemctl daemon-reload

# Enable the pod to start automatically on boot (optional)
sudo systemctl enable stigman.pod

# Start the pod and all associated containers
sudo systemctl start stigman.pod

# Check the status of the pod and containers
sudo systemctl status stigman.pod mysql.service keycloak.service stigman-api.service nginx-revproxy.service

# Follow logs for the entire pod
sudo journalctl -u stigman.pod -f

# Follow logs for a specific container (e.g., stigman-api)
sudo journalctl -u stigman-api.service -f
```
Crucial Next Step: Keycloak Configuration

After the containers are running:

Access the Keycloak Admin Console: https://<your_external_domain>/auth/
Log in using the admin credentials you set (<your_admin_user>, <your_admin_password>). Change the admin password immediately.
Select the stigman realm from the dropdown (usually top-left).
Navigate to Clients in the left menu.
Click on the stig-manager client ID.
Go to the Credentials tab.
Set the Client secret field to the exact same value you used for STIGMAN_KEYCLOAK_CLIENT_SECRET in the stigman-api.container file.
Ensure Client authentication is ON.
Go back to the Settings tab for the stig-manager client.
Verify Valid redirect URIs includes https://<your_external_domain>/*.
Verify Web origins includes https://<your_external_domain>.
Save any changes.

Now you should be able to access STIG Manager at https://<your_external_domain>/. You'll be redirected to Keycloak for login and then back to the application.
