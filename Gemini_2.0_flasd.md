Okay, I understand the challenge. You want to deploy STIG Manager with external accessibility using Podman Quadlets, which involves setting up four containers (Keycloak, MySQL, stigman-api, and a reverse Nginx proxy) within a Pod, with the Nginx proxy exposed.

Let's break down how we can achieve this using Quadlets. We'll need to create four .container files and one .pod file.

Here's a potential structure for your Quadlet files:

1. stigman.pod: This file will define the Pod that will contain all four containers.
```Ini, TOML

[Pod]
Name=stigman
```
2. keycloak.container: This file will define the Keycloak container. You'll need to find the appropriate Keycloak image and configure its environment variables.
```Ini, TOML

[Container]
Pod=stigman
Image=<your_keycloak_image>
Name=keycloak
Ports=8080:8080,8443:8443
Environment=KEYCLOAK_USER=<your_admin_user>
Environment=KEYCLOAK_PASSWORD=<your_admin_password>
# Add other Keycloak environment variables as needed
```
3. mysql.container: This file will define the MySQL container. You'll need the MySQL image and configure environment variables for the database.
```Ini, TOML

[Container]
Pod=stigman
Image=<your_mysql_image>
Name=mysql
Ports=3306:3306
Environment=MYSQL_ROOT_PASSWORD=<your_mysql_root_password>
Environment=MYSQL_DATABASE=stigman
Environment=MYSQL_USER=stigman
Environment=MYSQL_PASSWORD=<your_stigman_db_password>
Volumes=mysql_data:/var/lib/mysql
```
4. stigman-api.container: This file will define the STIG Manager API container. This is where the TLS requirement for external access comes in. We'll need to handle the TLS configuration here or in the Nginx proxy. For simplicity in this initial setup, let's assume we'll handle TLS in Nginx.
```Ini, TOML

[Container]
Pod=stigman
Image=<your_stigman_api_image>
Name=stigman-api
Ports=8000:8000 # Internal API port
Environment=SPRING_DATASOURCE_URL=jdbc:mysql://mysql:3306/stigman
Environment=SPRING_DATASOURCE_USERNAME=stigman
Environment=SPRING_DATASOURCE_PASSWORD=<your_stigman_db_password>
Environment=KEYCLOAK_AUTH_URL=http://keycloak:8080/realms/master # Adjust realm if needed
# Potentially other STIG Manager API environment variables
```
5. reverse-nginx.container: This file will define the reverse Nginx proxy. This container will handle external access, potentially TLS termination, and proxy requests to the stigman-api container.
```Ini, TOML

[Container]
Pod=stigman
Image=nginx:latest
Name=reverse-nginx
Ports=80:80,443:443 # External HTTP and HTTPS ports
Volumes=./nginx.conf:/etc/nginx/nginx.conf:ro
# You might need to mount TLS certificates here as well
# Volumes=./certs:/etc/nginx/certs:ro
```
## Important Considerations and Next Steps:

- Image Names: Replace <your_keycloak_image>, <your_mysql_image>, and <your_stigman_api_image> with the actual Docker image names for each service.
-  Environment Variables: Adjust the environment variables in each container definition according to the requirements of each application (usernames, passwords, database URLs, etc.).
-   Networking within the Pod: Containers within the same Pod can typically communicate with each other using their container names as hostnames (e.g., http://keycloak:8080, mysql:3306).
-   Nginx Configuration: You'll need to create an nginx.conf file to configure the reverse proxy. This configuration will listen on ports 80 and 443 and proxy requests to the stigman-api container (likely on http://stigman-api:8000). If you want TLS, you'll need to configure that within nginx.conf and mount your TLS certificates.
-   TLS: Since the API server requires TLS for non-localhost connections, you have two main options:
  -        Terminate TLS in Nginx: This is the more common approach for external access. Nginx handles the TLS certificates, and the traffic within the Pod to the stigman-api can be HTTP.
  -        Configure TLS in the stigman-api container: This would involve providing certificates to the API container and configuring it to listen on HTTPS. Then, Nginx would likely just proxy the HTTPS traffic.

Let's start with the first approach (TLS termination in Nginx) as it's generally simpler for external access.

Could you provide the following information so we can refine the Quadlet files?

    The Docker image names you intend to use for Keycloak, MySQL, and stigman-api.
    Do you have TLS certificates you want to use for external HTTPS access? If so, where would you like to store them relative to your Quadlet files?

Once I have this information, I can help you create the nginx.conf and finalize the Quadlet configurations.
