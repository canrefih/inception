# User Documentation — Inception

This document explains how to install, run, and use the Inception infrastructure from an end-user perspective. It does not cover internal implementation details — see `DEV_DOC.md` for that.

---

## 1. What This Project Does

Inception sets up a complete WordPress infrastructure secured with HTTPS, backed by a MariaDB database, with Redis caching, file transfer capabilities via FTP, web-based database administration via Adminer, and container monitoring via cAdvisor. All services run as Docker containers on your machine. Once started, you can browse to the site, log into WordPress as an administrator, use it like any normal WordPress installation, and access additional management and monitoring tools.

The infrastructure includes:

- **NGINX** — public-facing web server with HTTPS/TLS
- **WordPress** — WordPress CMS with PHP-FPM
- **MariaDB** — relational database
- **Redis** — object cache for WordPress
- **FTP** — file transfer access to WordPress data
- **Adminer** — web-based database administration
- **cAdvisor** — container resource monitoring and metrics

Additionally, a static personal showcase/CV website is hosted alongside WordPress.

---

## 2. Requirements

Before starting, make sure the following are installed on your machine:

- Docker
- Docker Compose
- Make
- A Linux virtual machine (recommended environment for this project)

---

## 3. First-Time Setup

### 3.1 Configure the domain

The infrastructure serves the site under the domain:

```text
recan.42.fr
```

This domain must resolve to your local machine. Add the following line to your `/etc/hosts` file:

```text
127.0.0.1 recan.42.fr
```

### 3.2 Configure environment variables

Environment values are stored in:

```text
srcs/.env
```

Example content:

```env
DOMAIN_NAME=recan.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
```

### 3.3 Configure secrets

Database and service passwords are kept out of the main configuration and stored in separate files:

```text
secrets/db_password.txt
secrets/db_root_password.txt
secrets/wp_admin_password.txt
secrets/ftp_password.txt
```

Put the desired passwords in these files before starting the project.

---

## 4. Starting the Project

From the root of the project, run:

```bash
make
```

This builds the Docker images (if needed) and starts all the containers in the background.

To confirm everything started correctly, list the running containers:

```bash
make ps
```

You should see seven containers running:

- `nginx`
- `wordpress`
- `mariadb`
- `redis`
- `ftp`
- `adminer`
- `cadvisor`

---

## 5. Accessing the Website

Open a browser and go to:

```text
https://recan.42.fr
```

Because the site uses a self-signed TLS certificate (not issued by a public certificate authority), your browser will show a security warning. This is expected — you can safely proceed past the warning for this local/development setup.

Note that only HTTPS is available. Visiting the HTTP version of the site will not work, since port 80 is intentionally not exposed:

```text
http://recan.42.fr   ← not available
```

---

## 6. Logging into WordPress

The WordPress administration dashboard is available at:

```text
https://recan.42.fr/wp-admin/
```

Use the administrator account created for the project. The admin username is:

```text
recan
```

Use the password you set up for the WordPress admin account during installation/configuration (from `secrets/wp_admin_password.txt`).

From the dashboard you can create posts, manage pages, install themes, and perform any standard WordPress administration task.

---

## 7. Accessing Additional Services

### 7.1 Showcase / Personal CV Website

A static personal showcase website is also hosted at:

```text
https://recan.42.fr/showcase/
```

This is a static HTML/CSS/JavaScript website served alongside WordPress and does not require PHP or database access.

### 7.2 Adminer — Web-Based Database Administration

Adminer provides a lightweight interface for managing the WordPress database:

```text
http://127.0.0.1:8080
or
http://recan.42.fr:8080
```

**To connect:**

- **Server:** `mariadb`
- **Port:** `3306`
- **Username:** (value from `MYSQL_USER` in `.env`)
- **Password:** (value from `secrets/db_password.txt`)
- **Database:** (value from `MYSQL_DATABASE` in `.env`)

Adminer allows you to inspect and modify the WordPress database without exposing MariaDB directly to the host.

### 7.3 cAdvisor — Container Monitoring

cAdvisor provides monitoring and metrics about container resource usage:

**Web interface:**

```text
http://127.0.0.1:8081/containers/
```

**Metrics endpoint:**

```text
http://127.0.0.1:8081/metrics
```

You can monitor CPU usage, memory usage, and other container metrics in real-time. The metrics can be queried via curl:

```bash
curl -s http://127.0.0.1:8081/metrics | grep 'container_cpu_usage_seconds_total'
curl -s http://127.0.0.1:8081/metrics | grep 'container_memory_working_set_bytes'
```

### 7.4 FTP — File Transfer

FTP provides direct file access to the WordPress data:

- **Port:** `21` (control connection)
- **Passive mode:** `50000-50100`
- **Username:** `ftpuser`
- **Password:** (value from `secrets/ftp_password.txt`)

Connect with any FTP client to transfer files to/from the WordPress directory without direct host filesystem access.

---

## 8. Common Operations

### Stop the infrastructure (containers stay, but are stopped)

```bash
make stop
```

### Start previously stopped containers

```bash
make start
```

### Restart everything

```bash
make restart
```

### View logs from the running services

```bash
make logs
```

### Stop and remove the containers

```bash
make down
```

### Full cleanup (removes containers, volumes, and images)

```bash
make fclean
```

### Rebuild everything from scratch

```bash
make re
```

---

## 9. Data Persistence

Your WordPress files, database content, and all service data are stored outside the containers, on your host machine, in:

```text
/home/recan/data/wordpress
/home/recan/data/db
```

This means that stopping, removing, or rebuilding the containers does **not** delete your website content, users, posts, or database — as long as these host directories are not manually deleted.

After restarting your computer, simply run:

```bash
make
```

and your existing WordPress site, with all its data and configurations, will be available again.

---

## 10. Troubleshooting

**The browser shows a certificate warning.**
This is expected behavior because the project uses a self-signed TLS certificate. Proceed past the warning to access the site.

**The site is not reachable.**
- Confirm `/etc/hosts` contains the line `127.0.0.1 recan.42.fr`.
- Confirm all seven containers are running with `make ps`.
- Check the logs with `make logs` for errors.
- Ensure Docker and Docker Compose are properly installed and running.

**HTTP (`http://recan.42.fr`) doesn't load.**
This is expected — only HTTPS is exposed by design.

**I forgot my WordPress admin password.**
Passwords are configured via the `secrets/` files and the WordPress setup process; check those files, or reset the password directly from within WordPress if you still have another admin account, or via Adminer or the database if necessary (see `DEV_DOC.md` for direct database access instructions).

**Adminer won't connect to the database.**
Verify that:
- The MariaDB container is running (`make ps`).
- You're using `mariadb` as the server name (not an IP address).
- The port is `3306`.
- Your username and password are correct (from `.env` and `secrets/` files).

**FTP connection fails.**
Verify that:
- The FTP container is running (`make ps`).
- You're connecting to port `21` for the control connection.
- Your username is `ftpuser` and password is correct (from `secrets/ftp_password.txt`).
- Your FTP client supports passive mode (ports 50000-50100).

**cAdvisor metrics are unavailable.**
Verify that:
- The cAdvisor container is running (`make ps`).
- You're accessing `http://127.0.0.1:8081` (not HTTPS).
- No other service is using port 8081.

**One or more containers won't start.**
- Check the logs: `make logs`
- Verify the secrets files exist and contain valid data.
- Ensure the host directories (`/home/recan/data/wordpress` and `/home/recan/data/db`) exist and are readable.
- Try a full rebuild: `make fclean && make`.

---

## 11. Getting Help

For details about how the infrastructure is built internally — architecture, Dockerfiles, initialization scripts, networking, and all seven services — refer to `DEV_DOC.md` and the main `README.md`.
