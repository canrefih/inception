*This project has been created as part of the 42 curriculum by recan.*

# Inception

## Description

The Inception project is a small infrastructure composed of different services using Docker Compose.

The goal is to build a complete WordPress infrastructure from custom Dockerfiles, without using ready-made service images. The infrastructure is composed of three services:

- **NGINX** — the only publicly exposed service, responsible for HTTPS/TLS connections.
- **WordPress** — running WordPress with PHP-FPM.
- **MariaDB** — providing the database used by WordPress.

The services communicate through a dedicated Docker bridge network and use persistent volumes backed by directories under `/home/recan/data/`.

This project strengthens your understanding of:

- Docker and Docker Compose
- Docker networks
- Custom Docker image creation
- NGINX and TLS/SSL configuration
- PHP-FPM
- MariaDB
- Docker volumes and data persistence
- Docker secrets
- Service initialization and dependencies
- Infrastructure automation

---

## Architecture

The infrastructure follows this structure:

```text
                         HTTPS :443
                             |
                             v
                    +-----------------+
                    |      NGINX      |
                    |   TLS / HTTPS   |
                    +--------+--------+
                             |
                         FastCGI
                             |
                             v
                    +-----------------+
                    |    WordPress    |
                    |    PHP-FPM      |
                    +--------+--------+
                             |
                         MariaDB
                             |
                             v
                    +-----------------+
                    |     MariaDB     |
                    |    Database     |
                    +-----------------+

                    Docker network:
                      srcs_inception
```

Only NGINX exposes a port to the host:

```text
Host :443 -> NGINX :443
```

MariaDB and PHP-FPM are accessible only through the internal Docker network.

NGINX communicates with PHP-FPM using:

```text
wordpress:9000
```

WordPress communicates with MariaDB using:

```text
mariadb:3306
```

No `network: host`, Docker links, or legacy `--link` mechanism is used.

---

## Services

### NGINX

NGINX is the public-facing service.

Its responsibilities are:

- Listen on port 443.
- Terminate TLS connections.
- Serve the WordPress files.
- Forward PHP requests to PHP-FPM.
- Keep port 80 inaccessible.
- Use a self-signed TLS certificate.

The NGINX configuration uses:

```nginx
listen 443 ssl;
server_name recan.42.fr;
```

TLS 1.2 and TLS 1.3 are enabled.

NGINX is the only container whose port is exposed to the host.

There is no NGINX installation inside the WordPress container.

### WordPress

The WordPress container is built from Debian 12 and installs:

- PHP 8.2
- PHP-FPM
- PHP MySQL extension
- PHP cURL
- PHP GD
- PHP mbstring
- PHP XML
- PHP ZIP
- MariaDB client
- curl
- ca-certificates
- tar

WordPress is downloaded during the initial container setup if it does not already exist in the persistent volume.

PHP-FPM listens on:

```text
0.0.0.0:9000
```

NGINX communicates with PHP-FPM through:

```text
wordpress:9000
```

The WordPress container does not expose port 9000 to the host.

### MariaDB

MariaDB provides the database used by WordPress.

The container installs:

- MariaDB Server
- MariaDB Client
- gosu

The database is initialized only once.

A marker file is used to detect whether initialization has already been completed:

```text
/var/lib/mysql/.inception_initialized
```

The initialization creates:

- The WordPress database
- The WordPress database user
- The required database privileges

The MariaDB data is stored persistently outside the container.

MariaDB does not expose its port to the host.

---

## Docker Network

All three services are connected to a dedicated Docker bridge network:

```text
srcs_inception
```

The network allows containers to communicate using their Docker service names.

For example:

```text
wordpress -> mariadb:3306
nginx     -> wordpress:9000
```

This keeps internal service communication isolated from the host network.

---

## Persistent Volumes

The project uses two persistent volumes.

### MariaDB

Host directory:

```text
/home/recan/data/db
```

Container directory:

```text
/var/lib/mysql
```

### WordPress

Host directory:

```text
/home/recan/data/wordpress
```

Container directory:

```text
/var/www/html
```

The Docker Compose configuration uses bind-backed Docker volumes so that data survives container removal and recreation.

---

## Docker Secrets

Passwords are not stored directly inside the Docker Compose configuration.

The following secret files are used:

```text
secrets/
├── db_password.txt
└── db_root_password.txt
```

They are exposed inside the appropriate containers through Docker Secrets:

```text
/run/secrets/db_password
/run/secrets/db_root_password
```

The initialization scripts read these files when configuring MariaDB and WordPress.

---

## Directory Structure

The project follows the directory structure required by the 42 Inception subject:

```text
inception/
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/
│   ├── .gitkeep
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── my.cnf
        │   └── tools/
        │       └── init-db.sh
        │
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── nginx.conf
        │   └── tools/
        │       └── setup-nginx.sh
        │
        └── wordpress/
            ├── Dockerfile
            └── tools/
                └── setup-wordpress.sh
```

Keeping each service in its own directory makes the infrastructure easier to understand, build and maintain.

---

## Prerequisites

The following software is required:

- Docker
- Docker Compose
- Make

The project is designed to run on a Linux virtual machine.

The domain used by this configuration is:

```text
recan.42.fr
```

The domain should resolve to the local machine.

For example, `/etc/hosts` can contain:

```text
127.0.0.1 recan.42.fr
```

---

## Configuration

The main environment configuration is stored in:

```text
srcs/.env
```

Example:

```env
DOMAIN_NAME=recan.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
```

Passwords are stored separately in:

```text
secrets/db_password.txt
secrets/db_root_password.txt
```

---

## Compilation and Execution

The project is managed through the root Makefile.

### Build the images

```bash
make build
```

### Start the infrastructure

```bash
make
```

or:

```bash
make up
```

This runs:

```bash
docker compose -f srcs/docker-compose.yml up -d
```

### Check the containers

```bash
make ps
```

Expected services:

- mariadb
- wordpress
- nginx

### Stop the services

```bash
make stop
```

### Start stopped services

```bash
make start
```

### Restart the infrastructure

```bash
make restart
```

### View logs

```bash
make logs
```

### Stop and remove containers

```bash
make down
```

### Full cleanup

```bash
make fclean
```

This removes the Compose containers, volumes and project images.

### Rebuild everything

```bash
make re
```

---

## Accessing WordPress

Once the infrastructure is running, access:

```text
https://recan.42.fr
```

Because the project uses a self-signed certificate, the browser may display a certificate warning. This is expected.

HTTP is intentionally not exposed:

```text
http://recan.42.fr
```

Only HTTPS is available:

```text
https://recan.42.fr
```

---

## WordPress Administration

The WordPress administration dashboard is available at:

```text
https://recan.42.fr/wp-admin
```

The administrator account created for the project can be used to access the dashboard.

The administrator username is:

```text
recan
```

The username does not contain `admin` or `Admin`.

---

## Database Access

MariaDB is not exposed directly to the host.

To access the database from inside the MariaDB container:

```bash
docker exec -it mariadb sh
```

Then:

```bash
mariadb \
  -u"$MYSQL_USER" \
  -p"$(cat /run/secrets/db_password)" \
  "$MYSQL_DATABASE"
```

For example, to verify the WordPress tables:

```sql
SHOW TABLES;
```

The database contains WordPress tables such as:

- wp_posts
- wp_users
- wp_options
- wp_comments
- wp_postmeta

---

## Verification

### Check containers

```bash
docker compose -f srcs/docker-compose.yml ps
```

All three containers should be running:

- mariadb
- wordpress
- nginx

### Check the Docker network

```bash
docker network ls
```

The project network should be visible:

```text
srcs_inception
```

### Check volumes

```bash
docker volume ls
```

Inspect the WordPress volume:

```bash
docker volume inspect srcs_wordpress_data
```

The configuration should reference:

```text
/home/recan/data/wordpress
```

Inspect the MariaDB volume:

```bash
docker volume inspect srcs_db_data
```

The configuration should reference:

```text
/home/recan/data/db
```

### Check HTTPS

```bash
curl -k -I https://recan.42.fr/
```

A successful response should return:

```text
HTTP/1.1 200 OK
```

### Check HTTP

```bash
curl -I http://recan.42.fr/
```

Port 80 should not be accessible.

### Check TLS

NGINX is configured to support:

- TLSv1.2
- TLSv1.3

These can be tested with:

```bash
curl -k -I --tlsv1.2 https://recan.42.fr/
```

and:

```bash
curl -k -I --tlsv1.3 https://recan.42.fr/
```

---

## Persistence

The project separates application data from container lifecycles.

### WordPress data

```text
/home/recan/data/wordpress
```

### MariaDB data

```text
/home/recan/data/db
```

Therefore, removing and recreating containers does not remove the application and database data as long as the persistent host directories are preserved.

After a system reboot, the infrastructure can be started again with:

```bash
make
```

The existing WordPress installation, users, posts and database data remain available.

---

## Configuration Modification

The infrastructure allows individual service configurations to be modified and rebuilt independently.

For example, after changing the NGINX configuration:

```bash
docker compose -f srcs/docker-compose.yml build nginx
docker compose -f srcs/docker-compose.yml up -d
```

The modified service can then be tested with:

```bash
docker compose -f srcs/docker-compose.yml ps
```

and:

```bash
curl -k -I https://recan.42.fr/
```

---

## Technical Implementation

### 1. Custom Docker Images

Each service has its own Dockerfile:

```text
srcs/requirements/mariadb/Dockerfile
srcs/requirements/wordpress/Dockerfile
srcs/requirements/nginx/Dockerfile
```

All services are built from Debian 12.

The resulting images are:

```text
mariadb:inception
wordpress:inception
nginx:inception
```

The images are built locally using Docker Compose.

### 2. MariaDB Initialization

The MariaDB entrypoint performs the following sequence:

1. Read passwords from Docker Secrets.
2. Check whether the database has already been initialized.
3. Start a temporary local MariaDB instance when initialization is required.
4. Wait until MariaDB is ready.
5. Create the WordPress database.
6. Create the WordPress database user.
7. Grant the required privileges.
8. Shut down the temporary instance.
9. Create the initialization marker.
10. Start MariaDB normally in the foreground.

This ensures that database initialization happens only once.

The initialization marker is:

```text
/var/lib/mysql/.inception_initialized
```

### 3. WordPress Initialization

The WordPress entrypoint:

1. Creates the WordPress directory.
2. Downloads WordPress if it is not already present.
3. Waits for MariaDB to become available.
4. Creates `wp-config.php` if it does not exist.
5. Configures the database connection.
6. Sets appropriate ownership for WordPress files.
7. Starts PHP-FPM in the foreground.

The database connection uses:

```text
DB_HOST=mariadb
```

because MariaDB is running in a separate container.

PHP-FPM listens on:

```text
0.0.0.0:9000
```

### 4. NGINX Configuration

NGINX serves WordPress and forwards PHP requests to PHP-FPM.

Static and WordPress requests are handled through:

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}
```

PHP requests are forwarded using FastCGI:

```nginx
location ~ \.php$ {
    include fastcgi_params;

    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param HTTP_HOST $host;

    fastcgi_pass wordpress:9000;
}
```

NGINX listens only on HTTPS:

```nginx
listen 443 ssl;
server_name recan.42.fr;
```

Port 80 is not exposed.

### 5. TLS

The NGINX entrypoint generates a self-signed certificate when one does not already exist.

The certificate is generated with OpenSSL using:

```text
CN=recan.42.fr
```

NGINX uses:

```text
/etc/nginx/ssl/inception.crt
/etc/nginx/ssl/inception.key
```

TLS 1.2 and TLS 1.3 are enabled.

The self-signed certificate is intended for the local development environment required by the project.

---

## Why Docker?

Docker provides process isolation while sharing the host kernel, making containers lighter than full virtual machines.

For this project, Docker isolates:

- Web server
- PHP runtime
- Database

Each service has its own filesystem, dependencies and process while communicating through a private Docker network.

Docker also makes the infrastructure reproducible because the environment can be recreated from the Dockerfiles and Docker Compose configuration.

---

## Docker Compose

Docker Compose defines the complete infrastructure in:

```text
srcs/docker-compose.yml
```

It describes:

- Services
- Networks
- Volumes
- Secrets
- Dependencies
- Port mappings
- Build contexts
- Restart policies

Without Compose, each container would have to be created and configured manually.

With Compose, the complete infrastructure can be started with:

```bash
make
```

---

## Data Persistence

The project uses persistent storage so that important data is not lost when containers are recreated.

### WordPress data

```text
/home/recan/data/wordpress
```

### MariaDB data

```text
/home/recan/data/db
```

This allows WordPress content, users and database information to survive container recreation and system reboots.

---

## Resources

- 42 Inception Subject
- Docker Documentation
- Docker Compose Documentation
- Debian Documentation
- NGINX Documentation
- PHP-FPM Documentation
- MariaDB Documentation
- WordPress Documentation
- OpenSSL Documentation

---

## AI Usage Disclosure

AI assistance was used for:

- Structuring and formatting this README.
- Improving documentation clarity and readability.
- Reviewing the Docker Compose configuration against the project requirements.
- Helping identify configuration and evaluation issues during development.
- Assisting with troubleshooting Docker, NGINX, PHP-FPM and MariaDB commands.

AI was not used as a replacement for understanding the infrastructure or the implementation. The Dockerfiles, configuration files and scripts were developed, tested and validated as part of the project implementation.