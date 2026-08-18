# User Documentation — Inception

This document explains how to install, run, and use the Inception infrastructure from an end-user perspective. It does not cover internal implementation details — see `DEV_DOC.md` for that.

---

## 1. What This Project Does

Inception sets up a working WordPress website, secured with HTTPS, backed by a MariaDB database, all running as Docker containers on your machine. Once started, you can browse to the site, log into WordPress as an administrator, and use it like any normal WordPress installation.

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

Database passwords are kept out of the main configuration and stored in separate files:

```text
secrets/db_password.txt
secrets/db_root_password.txt
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

You should see three containers running:

- `nginx`
- `wordpress`
- `mariadb`

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
https://recan.42.fr/wp-admin
```

Use the administrator account created for the project. The admin username is:

```text
recan
```

Use the password you set up for the WordPress admin account during installation/configuration.

From the dashboard you can create posts, manage pages, install themes, and perform any standard WordPress administration task.

---

## 7. Common Operations

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

## 8. Data Persistence

Your WordPress files and database content are stored outside the containers, on your host machine, in:

```text
/home/recan/data/wordpress
/home/recan/data/db
```

This means that stopping, removing, or rebuilding the containers does **not** delete your website content, users, posts, or database — as long as these host directories are not manually deleted.

After restarting your computer, simply run:

```bash
make
```

and your existing WordPress site, with all its data, will be available again.

---

## 9. Troubleshooting

**The browser shows a certificate warning.**
This is expected behavior because the project uses a self-signed TLS certificate. Proceed past the warning to access the site.

**The site is not reachable.**
- Confirm `/etc/hosts` contains the line `127.0.0.1 recan.42.fr`.
- Confirm all three containers are running with `make ps`.
- Check the logs with `make logs` for errors.

**HTTP (`http://recan.42.fr`) doesn't load.**
This is expected — only HTTPS is exposed by design.

**I forgot my WordPress admin password.**
Passwords are configured via the `secrets/` files and the WordPress setup process; check those files, or reset the password directly from within WordPress if you still have another admin account, or via the database if necessary (see `DEV_DOC.md` for direct database access instructions).

---

## 10. Getting Help

For details about how the infrastructure is built internally — architecture, Dockerfiles, initialization scripts, and networking — refer to `DEV_DOC.md` and the main `README.md`.
