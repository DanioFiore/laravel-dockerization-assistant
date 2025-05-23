
# Laravel Custom Setup Script

Setting up Laravel with Docker for every new project quickly became tedious and repetitive. That’s why I built this script—to completely streamline and automate Laravel’s Docker setup. With just a few prompts, it handles everything: from service selection and environment configuration to phpMyAdmin integration and port validation. Now, you can spin up a ready-to-code Laravel environment in seconds, every time.

This project provides a robust and user-friendly Bash script (`run.sh`) to automate the initial configuration and everyday usage of a Laravel development environment with Docker (using [Laravel Sail](https://laravel.com/docs/sail)).  
It handles project creation, service selection, environment configuration, port checks, and even integrates database clients like [phpMyAdmin](https://www.phpmyadmin.net/) / [pgAdmin](https://www.pgadmin.org).

---

## Features

- **Interactive one-time setup:**  
  Prompts for project name, desired services, and custom port configuration.
- **Robust input validation:**  
  Ensures service selection, project name and port numbers are correct and not already in use.
- **Automatic `.env` & Docker Compose updates:**  
  Injects chosen ports and services, edits config files safely.
- **phpMyAdmin and pgAdmin integration:**  
  Can automatically add a compatible phpMyAdmin or pgAdmin service if you select MySQL/PgSQL.
- **Easy repeated usage:**  
  On subsequent runs, containers are started without extra prompts.

---

## Prerequisites
- Linux or Mac
- [Docker](https://www.docker.com/)
- [curl](https://curl.se/)
- [awk](https://www.gnu.org/software/gawk/), [sed](https://www.gnu.org/software/sed/), [nc](https://nmap.org/ncat/) or [lsof](https://linux.die.net/man/8/lsof) (typically available by default on Linux/macOS)
- [npm](https://www.npmjs.com/) (for frontend dependencies)
- Bash shell (the script uses Bash syntax)

---

## Step-by-Step Usage

### 1. Place `run.sh` in your (empty or new) project directory.

If you are setting up a new Laravel project, make sure the directory is empty before you begin.

### 2. Give the script execute permission

chmod +x run.sh

### 3. Run the script

./run.sh

---

### What happens on **first run** (No existing Laravel project):

1. **Project Name Prompt:**  
   - Enter a valid project name (lowercase, numbers, `-` or `_`). No spaces allowed.
2. **Services Selection:**  
   - Choose from: `mysql`, `pgsql`, `mariadb`, `redis`, `memcached`, `meilisearch`, `selenium`, `mailpit`, `minio`.
   - You must enter valid service names only, using space or comma as separators.
3. **Port Configuration:**  
   - You’ll be prompted to choose a port for your Laravel app (`APP_PORT`, default 8000).
   - If you select MySQL, you will also be prompted for a port for phpMyAdmin (`PHPMYADMIN_PORT`, default 3000).
   - If you select Postgres, you will also be prompted for a port for pgAdmin (`PGADMIN_PORT`, default 5050).
   - The script verifies that each port is numeric, in the allowed range (1-65535), and **not already in use** on your system.
4. **Project Creation:**  
   - The script downloads and boots a fresh Laravel application with the selected services.
   - If MySQL is chosen, phpMyAdmin is automatically integrated and configured for your port.
   - If Postgres is chosen, pgAdmin is automatically integrated and configured for your port.
5. **Environment Configuration:**  
   - `.env` file is updated with your custom ports, `APP_URL`, and other helpful defaults (`WWWUSER`, `WWWGROUP`).
6. **Dependency Installation:**  
   - Runs database migrations.
   - Runs `npm install`.
7. **Boot & Access:**  
   - Docker containers are brought up and permissions on storage/cache are set.
   - The script drops you into the Laravel container’s bash shell.

---

### What happens on **subsequent runs** (when already set up):

- The script identifies an existing Laravel app.
- It reads your stored configuration and launches all required Docker containers.
- You are dropped into the container shell automatically.
- When you exit the container shell, all containers are stopped for convenience.

---

## Accessing Your Development Services

- **Laravel app:**  
  Visit [http://localhost:APP_PORT](http://localhost:APP_PORT) (`APP_PORT` as chosen, default 8000).
- **phpMyAdmin (If chosen):**  
  Visit [http://localhost:PHPMYADMIN_PORT](http://localhost:PHPMYADMIN_PORT) (`PHPMYADMIN_PORT` as chosen, default 3000).
- **pgAdmin (If chosen):**  
  Visit [http://localhost:PGADMIN_PORT](http://localhost:PGADMIN_PORT) (`PGADMIN_PORT` as chosen, default 5050).

---

## Notes and Recommendations

- You can re-run `run.sh` at any time. It’s safe and idempotent.
- Always wait for “Containers started successfully!” before interacting with your site or services.
- To change ports after setup, edit `.env` and `docker-compose.yml` (if custom service blocks are present), then restart the containers.
- Use cmd/ctrl + d to stop all the containers.

---

## Troubleshooting

- **“Port already in use”**: The script will prompt you for another if your first choice is taken.
- **Permissions errors**: The script attempts to set the correct permissions (in storage bootstrap/cache set the owner to current user and permissions to 700).
- **phpMyAdmin issues**: The image used is compatible with Linux, Windows, and Apple Silicon (ARM) Docker hosts.
- **Other errors**: Make sure all dependencies (see Prerequisites) are available in your system path.

---

## Customization

Feel free to edit or extend `run.sh` with more services or tweaks as needed for your workflow.

---

## License

MIT  
This script is provided as-is. Enjoy your modern Laravel setup!


