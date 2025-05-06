I understand your goal. You're trying to deploy STIG Manager using Podman quadlets instead of Docker Compose, and you need to make it externally accessible while maintaining the required TLS security.

Let's create a solution with four containers in a pod, with the nginx reverse proxy exposed externally. I'll guide you through creating the necessary quadlet files for this deployment.

First, let's analyze what we need based on the STIG Manager architecture:
- A pod containing all four containers
- MySQL for database
- Keycloak for authentication
- STIG Manager API 
- Nginx reverse proxy with TLS enabled and exposed externally

Here's how we can set this up with Podman quadlets:

## 1. First, let's create the pod quadlet:

```ini
# stigman-pod.kube
[Kube]
Yaml=podman-pod.yml
```

```yaml
# podman-pod.yml
apiVersion: v1
kind: Pod
metadata:
  name: stigman-pod
spec:
  containers: []  # We'll define containers separately
```

## 2. Now let's create the container quadlets:

### MySQL Container

```ini
# stigman-mysql.container
[Unit]
Description=MySQL Database for STIG Manager
After=network.target
Requires=stigman-pod.service
After=stigman-pod.service

[Container]
PodmanArgs=--pod=stigman-pod
Image=mysql:8.0
Environment=MYSQL_ROOT_PASSWORD=rootpassword
Environment=MYSQL_DATABASE=stigman
Environment=MYSQL_USER=stigman
Environment=MYSQL_PASSWORD=stigman
Volume=stigman-mysql-data:/var/lib/mysql:Z

[Install]
WantedBy=default.target
```

### Keycloak Container

```ini
# stigman-keycloak.container
[Unit]
Description=Keycloak Authentication for STIG Manager
After=network.target
Requires=stigman-pod.service stigman-mysql.service
After=stigman-pod.service stigman-mysql.service

[Container]
PodmanArgs=--pod=stigman-pod
Image=quay.io/keycloak/keycloak:22.0.1
Environment=KEYCLOAK_ADMIN=admin
Environment=KEYCLOAK_ADMIN_PASSWORD=admin
Environment=KC_DB=mysql
Environment=KC_DB_URL=jdbc:mysql://localhost:3306/keycloak
Environment=KC_DB_USERNAME=stigman
Environment=KC_DB_PASSWORD=stigman
Environment=KC_HOSTNAME_STRICT=false
Environment=KC_PROXY=edge
Environment=KC_HTTP_ENABLED=true
Environment=KC_HTTP_PORT=8080
Command=start-dev

[Install]
WantedBy=default.target
```

### STIG Manager API Container

```ini
# stigman-api.container
[Unit]
Description=STIG Manager API
After=network.target
Requires=stigman-pod.service stigman-mysql.service stigman-keycloak.service
After=stigman-pod.service stigman-mysql.service stigman-keycloak.service

[Container]
PodmanArgs=--pod=stigman-pod
Image=nuwcdivnpt/stig-manager:latest
Environment=STIGMAN_API_AUTHORITY=http://localhost:8080/realms/stigman
Environment=STIGMAN_API_KEYCLOAK_ADMIN=admin
Environment=STIGMAN_API_KEYCLOAK_PASSWORD=admin
Environment=STIGMAN_API_CLIENT_CERTIFICATE_CHECK=false
Environment=STIGMAN_API_CLIENT_CERTIFICATE_HEADER=X-SSL-Client-Cert
Environment=STIGMAN_DB_HOST=localhost
Environment=STIGMAN_DB_PORT=3306
Environment=STIGMAN_DB_DATABASE=stigman
Environment=STIGMAN_DB_USER=stigman
Environment=STIGMAN_DB_PASSWORD=stigman
Environment=STIGMAN_API_PORT=54000
Environment=STIGMAN_INIT=true
Environment=STIGMAN_CLASSIFICATION=U
Environment=STIGMAN_IMPORT_DISABLED=false
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
```

### Nginx Reverse Proxy Container

```ini
# stigman-nginx.container
[Unit]
Description=Nginx Reverse Proxy for STIG Manager
After=network.target
Requires=stigman-pod.service stigman-api.service stigman-keycloak.service
After=stigman-pod.service stigman-api.service stigman-keycloak.service

[Container]
PodmanArgs=--pod=stigman-pod
Image=nginx:stable
PublishPort=443:443
PublishPort=80:80
Volume=./nginx.conf:/etc/nginx/nginx.conf:ro,Z
Volume=./certs:/etc/nginx/certs:ro,Z

[Install]
WantedBy=default.target
```

## 3. Let's create a volume for MySQL data persistence:

```ini
# stigman-mysql-data.volume
[Volume]
Label=app=stigman,component=mysql
```

## 4. Now let's create the nginx configuration file:

## 5. Generating SSL certificates 

You'll need self-signed certificates for development (replace with real ones in production):

```bash
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout certs/server.key -out certs/server.crt
```

## 6. Create a simple deployment script:

## 7. How to Use These Files

1. Create a new directory for your deployment and place all the quadlet files (*.container, *.kube, *.volume) in it.
2. Create the nginx.conf file as shown above.
3. Make the deploy script executable: `chmod +x deploy-stigman.sh`
4. Run the deployment script: `./deploy-stigman.sh`

## Key Points About This Setup:

1. **Pod Network**: All containers share the same network namespace because they're in the same pod. This allows them to communicate via `localhost`.

2. **Service Dependencies**: The quadlet files have proper dependencies so that containers start in the correct order.

3. **External Access**: The Nginx container has ports 80 and 443 published, making the application accessible from outside.

4. **TLS Configuration**: The Nginx reverse proxy handles TLS termination, satisfying the requirement that the API server needs TLS for external access.

5. **Data Persistence**: The MySQL data is stored in a named volume for persistence.

## Customization

You'll want to modify:
- Change all passwords from the default values
- Use proper certificates instead of self-signed ones in production
- Adjust memory limits and other resource constraints as needed
- Customize nginx.conf to match your specific domain and requirements

Would you like me to explain any specific part of this setup in more detail or make any adjustments to better fit your environment?
