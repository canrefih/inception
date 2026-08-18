*This project has been created as part of the 42 curriculum by recan.*

# Inception

## Description

The **Inception** project is a containerized infrastructure built with Docker Compose as part of the 42 curriculum.

The goal is to design and operate a complete multi-service web infrastructure using custom Dockerfiles and Docker Compose, while applying principles such as service isolation, networking, persistent storage, secrets management, TLS encryption, and container monitoring.

The infrastructure is composed of **seven services**:

- **NGINX** — the public-facing web server and TLS/HTTPS termination point.
- **WordPress** — the main CMS running with PHP-FPM.
- **MariaDB** — the relational database used by WordPress.
- **Redis** — object caching for WordPress.
- **FTP** — file transfer access to the WordPress data volume.
- **Adminer** — a web-based database administration interface.
- **cAdvisor** — container resource monitoring and metrics collection.

In addition to the WordPress website, the infrastructure also hosts a static personal CV/showcase website available at:

```text
https://recan.42.fr/showcase/
```

This project strengthens your understanding of:

- Docker and Docker Compose
- Custom Docker image creation
- Docker networking and service discovery
- NGINX and TLS/SSL configuration
- PHP-FPM
- WordPress
- MariaDB and MySQL
- Redis caching
- FTP protocols
- Web-based database administration
- Container metrics and monitoring
- Docker volumes and data persistence
- Docker secrets management
- Service initialization and dependencies
- Infrastructure automation
- Linux administration and Bash scripting

---

## Architecture

The infrastructure consists of seven containers connected through a dedicated Docker bridge network:

```text
                           HTTPS :443
                               |
                               v
                      +----------------+
                      |     NGINX      |
                      |  TLS / HTTPS   |
                      +-------+--------+
                              |
                 +------------+-------------+
                 |                          |
                 | FastCGI                  | Static files
                 v                          v
          +-------------+          +----------------+
          |  WordPress  |          |    Showcase    |
          |   PHP-FPM   |          |  HTML/CSS/JS   |
          +------+------+          +----------------+
                 |
          +------+------+
          |             |
          v             v
    +-----------+   +---------+
    |  MariaDB  |   |  Redis  |
    | Database  |   |  Cache  |
    +-----------+   +---------+

    Additional services:

    +---------+       +----------+
    |   FTP   |       | Adminer  |
    +---------+       +----------+
         |                 |
         |                 |
         +------ Docker ---+
                Network

                 +----------+
                 | cAdvisor |
                 | Metrics  |
                 +----------+

                   Docker network:
                     srcs_inception
```

Only services that intentionally provide host-accessible interfaces expose ports:

- **443** → NGINX (HTTPS)
- **8080** → Adminer (Web-based DB admin)
- **8081** → cAdvisor (Metrics interface)
- **21** → FTP (Control connection)
- **50000-50100** → FTP (Passive mode)

Internal service communication uses Docker DNS and service names:

```text
NGINX      -> wordpress:9000
WordPress  -> mariadb:3306
WordPress  -> redis:6379
Adminer    -> mariadb:3306
```

No `network: host`, Docker links, or legacy `--link` mechanism is used.

---

## Services

### NGINX

NGINX is the public-facing web server and the main entry point for the infrastructure.

**Responsibilities:**

- TLS termination and HTTPS handling
- Serving WordPress requests
- Forwarding PHP requests to PHP-FPM via FastCGI
- Serving the static showcase website
- Restricting the infrastructure to HTTPS only
- Acting as the single entry point for the web application

**Configuration:**

```nginx
listen 443 ssl;
server_name recan.42.fr;
```

TLS 1.2 and TLS 1.3 are enabled.

NGINX communicates with PHP-FPM through:

```text
wordpress:9000
```

NGINX listens on port **443** and is the only service whose port is exposed to the host.

### WordPress

The WordPress container runs the CMS and PHP-FPM.

**Installed components:**

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

WordPress is downloaded during initialization if it does not already exist in the persistent volume.

**PHP-FPM Configuration:**

PHP-FPM listens on:

```text
0.0.0.0:9000
```

Port 9000 is not exposed to the host.

NGINX communicates with WordPress using:

```text
wordpress:9000
```

The WordPress container communicates with:

```text
mariadb:3306
redis:6379
```

### MariaDB

MariaDB provides the relational database used by WordPress.

**Installed components:**

- MariaDB Server
- MariaDB Client
- gosu

**Initialization Process:**

The database is initialized through a custom entrypoint script with the following sequence:

1. Read passwords from Docker Secrets
2. Detect whether the database has already been initialized
3. Start a temporary MariaDB instance when necessary
4. Wait for MariaDB to become available
5. Create the WordPress database
6. Create the WordPress database user
7. Grant the required privileges
8. Stop the temporary instance
9. Create an initialization marker
10. Start MariaDB normally in the foreground

**Initialization Marker:**

```text
/var/lib/mysql/.inception_initialized
```

MariaDB does not expose port 3306 to the host.

### Redis

Redis is used as an object cache for WordPress.

The Redis service is available to WordPress through the internal Docker network:

```text
redis:6379
```

Redis does not expose its port to the host. The service is built using a custom Dockerfile.

Redis helps reduce repeated database operations and improves application responsiveness when caching is used by WordPress.

### FTP

The FTP service provides file transfer access to the WordPress data.

**Configuration:**

- Uses the same persistent WordPress volume
- Mounts `/home/recan/data/wordpress` inside the container at `/home/ftpuser/wordpress`
- Control connection on port **21**
- Passive mode on ports **50000-50100**
- FTP password provided through Docker Secrets

FTP allows files in the WordPress data directory to be managed without directly accessing the host filesystem.

### Adminer

Adminer provides a web-based database administration interface.

**Access:**

```text
http://127.0.0.1:8080
or
http://recan.42.fr:8080
```

**Configuration:**

- Communicates with MariaDB through the Docker network
- MariaDB host: `mariadb`
- Database port: `3306`

Adminer is useful for inspecting and managing the WordPress database without exposing MariaDB itself to the host.

### cAdvisor

cAdvisor is used to monitor container resource consumption.

**Metrics exposure:**

```text
http://127.0.0.1:8081
```

**Available metrics:**

- CPU usage
- Memory usage
- Container filesystem information
- Container runtime information
- Docker container metrics

**Metrics endpoint:**

```text
http://127.0.0.1:8081/metrics
```

**Example queries:**

```bash
# CPU usage
curl -s http://127.0.0.1:8081/metrics | grep 'container_cpu_usage_seconds_total'

# Filter by container name
curl -s http://127.0.0.1:8081/metrics | grep 'container_cpu_usage_seconds_total' | grep 'name="wordpress"'

# Memory metrics
curl -s http://127.0.0.1:8081/metrics | grep 'container_memory_working_set_bytes'

# WordPress memory metrics
curl -s http://127.0.0.1:8081/metrics | grep 'container_memory_working_set_bytes' | grep 'name="wordpress"'
```

cAdvisor accesses required host Docker and system information through read-only mounts.

### Static Showcase Website

In addition to WordPress, the infrastructure contains a static personal showcase/CV website.

**Access:**

```text
https://recan.42.fr/showcase/
```

**Technology stack:**

- HTML
- CSS
- JavaScript

**Content:**

- Professional summary
- Education
- Professional experience
- Technical skills
- AI and software development experience
- RPA experience
- Projects
- Certifications
- Additional training
- Interests

The static website is served directly by NGINX and does not require PHP-FPM or WordPress.

This demonstrates that the same NGINX infrastructure can serve both WordPress/PHP content and static HTML/CSS/JavaScript content without dependency overhead.

---

## Docker Network

All seven services are connected to a dedicated Docker bridge network:

```text
srcs_inception
```

The network provides internal service discovery through Docker DNS.

**Service Communication Examples:**

```text
nginx     -> wordpress:9000
wordpress -> mariadb:3306
wordpress -> redis:6379
adminer   -> mariadb:3306
```

Services communicate using service names instead of hard-coded container IP addresses, keeping internal communication isolated from the host network.

The project does not use `network: host`, Docker links, or the legacy `--link` mechanism.

---

## Persistent Volumes

The project uses persistent storage for application and database data.

### MariaDB

**Host directory:**

```text
/home/recan/data/db
```

**Container directory:**

```text
/var/lib/mysql
```

### WordPress

**Host directory:**

```text
/home/recan/data/wordpress
```

**Container directory:**

```text
/var/www/html
```

The Docker Compose configuration uses bind-backed Docker volumes, allowing important data to survive container removal and recreation.

The static showcase website is kept as part of the NGINX application configuration rather than relying on the WordPress data volume.

---

## Docker Secrets

Passwords are not stored directly in the Docker Compose configuration.

The project uses Docker Secrets for sensitive credentials.

**Secret files:**

```text
secrets/
├── db_password.txt
├── db_root_password.txt
├── wp_admin_password.txt
└── ftp_password.txt
```

Inside containers, secrets are available under:

```text
/run/secrets/
```

**Examples:**

```text
/run/secrets/db_password
/run/secrets/db_root_password
/run/secrets/wp_admin_password
/run/secrets/ftp_password
```

Initialization scripts read these files when configuring the corresponding services.

---

## Directory Structure

The project follows the structure required by the 42 Inception subject:

```text
inception/
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
│
├── secrets/
│   ├── .gitkeep
│   ├── db_password.txt
│   ├── db_root_password.txt
│   ├── wp_admin_password.txt
│   └── ftp_password.txt
│
└── srcs/
    ├── .env
    ├── docker-compose.yml
    │
    └── requirements/
        │
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
        │      └── setup-nginx.sh
        |
        ├── wordpress/
        │   ├── Dockerfile
        │   └── tools/
        │       └── setup-wordpress.sh
        |
        │── website/
        │       ├── index.html
        │       ├── style.css
        │       └── script.js
        │
        ├── redis/
        │   ├── Dockerfile
        │   └── tools/
        │       └── ...
        │
        ├── ftp/
        │   ├── Dockerfile
        │   └── tools/
        │       └── ...
        │
        ├── adminer/
        │   ├── Dockerfile
        │   └── tools/
        │       └── ...
        │
        └── cadvisor/
            ├── Dockerfile
            └── tools/
                └── ...
```

Each service has its own directory containing its Dockerfile and configuration files, keeping the infrastructure modular and making individual services easier to understand and rebuild.

---

## Prerequisites

The following software is required:

- Docker
- Docker Compose
- Make
- Linux environment

The project is designed to run on a Linux virtual machine.

The configured domain is:

```text
recan.42.fr
```

For local testing, `/etc/hosts` can contain:

```text
127.0.0.1 recan.42.fr
```

---

## Configuration

The main environment configuration is stored in:

```text
srcs/.env
```

**Example:**

```env
DOMAIN_NAME=recan.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
```

Sensitive passwords are stored separately in:

```text
secrets/
```

and are provided to containers through Docker Secrets.

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

This starts the complete infrastructure using Docker Compose.

### Check containers

```bash
make ps
```

Expected services:

- mariadb
- wordpress
- nginx
- redis
- ftp
- adminer
- cadvisor

### Stop services

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

This removes the project's containers, images and volumes according to the Makefile configuration.

### Rebuild everything

```bash
make re
```

---

## Accessing the Services

### WordPress

```text
https://recan.42.fr/
```

Because the project uses a self-signed certificate, the browser may display a certificate warning. This is expected in the local development environment.

### WordPress Administration

```text
https://recan.42.fr/wp-admin/
```

The administrator account created for the project can be used to access the dashboard.

**Administrator username:**

```text
recan
```

The username does not contain `admin` or `Admin`.

### Showcase / CV

```text
https://recan.42.fr/showcase/
```

The showcase is a static HTML/CSS/JavaScript website and does not depend on PHP.

### Adminer

```text
http://127.0.0.1:8080
```

Adminer can be used to connect to MariaDB using:

- **Server:** mariadb
- **Port:** 3306

### cAdvisor

**Web interface:**

```text
http://127.0.0.1:8081/containers/
```

**Metrics:**

```text
http://127.0.0.1:8081/metrics
```

### FTP

FTP is available on:

- **Port 21** (Control connection)
- **Ports 50000-50100** (Passive mode)

---

## Database Access

MariaDB is not directly exposed to the host.

To access the MariaDB container:

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

To inspect WordPress tables:

```sql
SHOW TABLES;
```

**Typical WordPress tables:**

- wp_posts
- wp_users
- wp_options
- wp_comments
- wp_postmeta

---

## Verification

### Check all containers

```bash
docker compose -f srcs/docker-compose.yml ps
```

All seven services should be running:

- mariadb
- wordpress
- nginx
- redis
- ftp
- adminer
- cadvisor

### Check the Docker network

```bash
docker network ls
```

The project network should be visible:

```text
srcs_inception
```

Inspect it with:

```bash
docker network inspect srcs_inception
```

### Check volumes

```bash
docker volume ls
```

The project volumes should include:

```text
srcs_db_data
srcs_wordpress_data
```

**Inspect the WordPress volume:**

```bash
docker volume inspect srcs_wordpress_data
```

The configuration should reference:

```text
/home/recan/data/wordpress
```

**Inspect the MariaDB volume:**

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

A successful response should return an HTTP success response.

### Check the Showcase

```bash
curl -k -I https://recan.42.fr/showcase/
```

The static website should be served by NGINX without involving PHP-FPM.

### Check HTTP

```bash
curl -I http://recan.42.fr/
```

Port 80 is intentionally not exposed. The infrastructure is designed to use HTTPS only.

### Check TLS

NGINX supports TLS 1.2 and TLS 1.3.

**Test TLS 1.2:**

```bash
curl -k -I --tlsv1.2 https://recan.42.fr/
```

**Test TLS 1.3:**

```bash
curl -k -I --tlsv1.3 https://recan.42.fr/
```

### Check cAdvisor Metrics

**CPU metrics:**

```bash
curl -s http://127.0.0.1:8081/metrics | grep 'container_cpu_usage_seconds_total'
```

**WordPress CPU metrics:**

```bash
curl -s http://127.0.0.1:8081/metrics | grep 'container_cpu_usage_seconds_total' | grep 'name="wordpress"'
```

**Memory metrics:**

```bash
curl -s http://127.0.0.1:8081/metrics | grep 'container_memory_working_set_bytes'
```

**WordPress memory metrics:**

```bash
curl -s http://127.0.0.1:8081/metrics | grep 'container_memory_working_set_bytes' | grep 'name="wordpress"'
```

---

## Persistence

The project separates application data from container lifecycles.

**WordPress:**

```text
/home/recan/data/wordpress
```

**MariaDB:**

```text
/home/recan/data/db
```

Removing and recreating containers does not remove application or database data as long as the persistent host directories are preserved.

After a system reboot, the infrastructure can be started again using:

```bash
make
```

Existing WordPress users, posts, configuration and database data remain available.

The static showcase website is part of the NGINX application configuration and can be recreated from the project source during an image rebuild.

---

## Configuration Modification

Individual services can be rebuilt independently.

For example, after changing the NGINX configuration:

```bash
docker compose -f srcs/docker-compose.yml build nginx
docker compose -f srcs/docker-compose.yml up -d nginx
```

Check the service:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Test HTTPS:

```bash
curl -k -I https://recan.42.fr/
```

Test the showcase:

```bash
curl -k -I https://recan.42.fr/showcase/
```

---

## Technical Implementation

### 1. Custom Docker Images

Each service has its own Dockerfile:

```text
srcs/requirements/mariadb/Dockerfile
srcs/requirements/wordpress/Dockerfile
srcs/requirements/nginx/Dockerfile
srcs/requirements/redis/Dockerfile
srcs/requirements/ftp/Dockerfile
srcs/requirements/adminer/Dockerfile
srcs/requirements/cadvisor/Dockerfile
```

The images are built locally using Docker Compose.

**Image names include:**

```text
mariadb:inception
wordpress:inception
nginx:inception
redis:inception
ftp:inception
adminer:inception
cadvisor:inception
```

### 2. MariaDB Initialization

The MariaDB entrypoint performs the following sequence:

1. Read passwords from Docker Secrets
2. Check whether the database has already been initialized
3. Start a temporary local MariaDB instance if necessary
4. Wait for MariaDB to become ready
5. Create the WordPress database
6. Create the WordPress database user
7. Grant the required privileges
8. Shut down the temporary instance
9. Create the initialization marker
10. Start MariaDB normally in the foreground

This prevents the database from being recreated every time the container starts.

**Marker location:**

```text
/var/lib/mysql/.inception_initialized
```

### 3. WordPress Initialization

The WordPress entrypoint:

1. Creates the WordPress directory
2. Downloads WordPress if it is not already present
3. Waits for MariaDB to become available
4. Creates `wp-config.php` if it does not exist
5. Configures the database connection
6. Configures the WordPress installation
7. Sets appropriate file ownership
8. Starts PHP-FPM in the foreground

**Database configuration:**

- **Host:** mariadb
- **Port:** 3306

**PHP-FPM configuration:**

```text
0.0.0.0:9000
```

### 4. Redis Integration

Redis provides object caching capabilities for WordPress.

The WordPress service reaches Redis through:

```text
redis:6379
```

Redis is isolated from the host and accessible only through the internal Docker network.

### 5. NGINX Configuration

NGINX serves WordPress and forwards PHP requests to PHP-FPM.

**WordPress request handling:**

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}
```

**PHP request forwarding:**

```nginx
location ~ \.php$ {
    include fastcgi_params;

    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param HTTP_HOST $host;

    fastcgi_pass wordpress:9000;
}
```

**Listening configuration:**

```nginx
listen 443 ssl;
server_name recan.42.fr;
```

### 6. Static Showcase Routing

The `/showcase/` route is handled directly by NGINX.

The static website consists of:

- index.html
- style.css
- script.js

No PHP processing is required for the showcase. The route allows the infrastructure to provide a static website alongside the WordPress application.

### 7. TLS Configuration

The NGINX setup generates a self-signed certificate when required.

**Certificate details:**

- **Generated for:** recan.42.fr
- **Certificate path:** /etc/nginx/ssl/inception.crt
- **Key path:** /etc/nginx/ssl/inception.key
- **TLS versions supported:** TLS 1.2 and TLS 1.3

The self-signed certificate is intended for the local development environment required by the project.

### 8. FTP Service

The FTP service provides access to the WordPress persistent data.

**Configuration:**

- Mounts `wordpress_data` at `/home/ftpuser/wordpress`
- Exposes port 21 for control connection
- Exposes ports 50000-50100 for passive mode
- Credentials supplied using Docker Secrets

### 9. Adminer

Adminer provides a lightweight database administration interface.

**Configuration:**

- Communicates with MariaDB through the Docker network: `adminer -> mariadb:3306`
- Exposed on port 8080
- Allows inspection of the WordPress database without exposing MariaDB directly to the host

### 10. cAdvisor Monitoring

cAdvisor collects resource usage information for running containers.

**Read-only mounts:**

```text
/rootfs
/var/run
/sys
/var/lib/docker
```

**Exposure:**

- Interface on port 8081
- Metrics endpoint at `/metrics`

These mounts allow cAdvisor to collect Docker container metrics without modifying the host filesystem.

---

## Docker Compose

The complete infrastructure is defined in:

```text
srcs/docker-compose.yml
```

Docker Compose describes:

- Services
- Build contexts and Dockerfiles
- Networks
- Volumes
- Secrets
- Dependencies
- Port mappings
- Restart policies
- Environment configuration

The complete infrastructure can be started with:

```bash
make
```

This makes the infrastructure reproducible and avoids manually creating and configuring each container.

---

## Data Persistence

The project uses persistent storage for important data.

**WordPress data:**

```text
/home/recan/data/wordpress
```

**MariaDB data:**

```text
/home/recan/data/db
```

**Persistence ensures:**

- WordPress files survive container recreation
- Uploaded media survives container recreation
- WordPress configuration survives container recreation
- Database contents survive container recreation
- Users and posts remain available

However, deleting the persistent host directories intentionally resets the corresponding data.

**Example clean reset:**

```bash
sudo rm -rf /home/recan/data/db
sudo rm -rf /home/recan/data/wordpress
```

This should only be used when a complete clean initialization is intended.

---

## Clean Installation

For a completely clean evaluation or rebuild, Docker resources can be removed and the persistent directories can be recreated.

```bash
docker stop $(docker ps -qa)
docker rm $(docker ps -qa)
docker rmi -f $(docker images -qa)
docker volume rm $(docker volume ls -q)
docker network rm $(docker network ls -q) 2>/dev/null
```

Then recreate the persistent directories:

```bash
sudo mkdir -p /home/recan/data/db
sudo mkdir -p /home/recan/data/wordpress
```

Finally:

```bash
make
```

The MariaDB and WordPress initialization scripts will recreate the required application state.

The static showcase website is rebuilt as part of the NGINX image and does not depend on the WordPress persistent volume.

---

## Why Docker?

Docker provides process and filesystem isolation while sharing the host kernel.

For this project, Docker separates:

- Web server (NGINX)
- PHP runtime (PHP-FPM)
- Database (MariaDB)
- Cache layer (Redis)
- File transfer service (FTP)
- Database administration interface (Adminer)
- Monitoring infrastructure (cAdvisor)

Each service has its own dependencies, filesystem and process environment while communicating through a private Docker network.

Docker also makes the infrastructure reproducible because the complete environment can be recreated from:

- Dockerfiles
- Docker Compose configuration
- Configuration files
- Initialization scripts
- Secrets

---

## Project Objectives

The project demonstrates practical knowledge of:

**Infrastructure:**

- Docker
- Docker Compose
- Linux administration
- Bash scripting
- Networking
- Containers
- Persistent storage
- Web infrastructure

**Web Technologies:**

- NGINX
- HTTPS and TLS/SSL
- PHP-FPM
- WordPress
- Databases and MariaDB/MySQL
- Redis caching
- FTP protocols
- SQL

**Supporting Services:**

- Adminer (database administration)
- cAdvisor (monitoring and metrics)

**Development Languages:**

- Python
- C
- C++
- Java
- C#
- JavaScript
- HTML
- CSS
- PHP
- Bash

**AI and Automation:**

- Machine Learning
- Natural Language Processing (NLP)
- Large Language Models (LLMs)
- Computer Vision
- Robotic Process Automation (RPA)
- Automation platforms (UiPath, Automation Anywhere, Robusta, n8n)

---

## Resources

- [42 Inception Subject](https://github.com/42School/42cursus)
- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Debian Documentation](https://www.debian.org/doc/)
- [NGINX Documentation](https://nginx.org/en/docs/)
- [PHP Documentation](https://www.php.net/docs.php)
- [PHP-FPM Documentation](https://www.php.net/manual/en/install.fpm.php)
- [MariaDB Documentation](https://mariadb.com/kb/en/)
- [Redis Documentation](https://redis.io/documentation)
- [WordPress Documentation](https://wordpress.org/documentation/)
- [Adminer Documentation](https://www.adminer.org/)
- [cAdvisor Documentation](https://github.com/google/cadvisor)
- [OpenSSL Documentation](https://www.openssl.org/docs/)

---

## AI Usage Disclosure

AI assistance was used during the development and documentation process for:

- Structuring and formatting documentation
- Improving documentation clarity and readability
- Reviewing Docker Compose configuration
- Reviewing project requirements and evaluation criteria
- Troubleshooting Docker, NGINX, PHP-FPM, MariaDB, Redis and networking issues
- Assisting with debugging commands and configuration
- Reviewing the infrastructure architecture
- Improving the static showcase website structure and styling

AI assistance was not used as a replacement for understanding the infrastructure or the implementation.

The Dockerfiles, Docker Compose configuration, initialization scripts, service configuration and infrastructure were implemented, tested and validated as part of the project development process.
