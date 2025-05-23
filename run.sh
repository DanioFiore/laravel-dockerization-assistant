#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Platform check
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    echo -e "${RED}This script is intended for MacOS or Linux environments. For Windows, please use WSL or consider Laravel Herd:${NC} https://laravel.build/"
    exit 1
fi

# allowed Sail services for Laravel (taken from documentation)
ALLOWED_SERVICES="mysql pgsql mariadb redis memcached meilisearch selenium mailpit minio"

# convert allowed services to array
read -ra ALLOWED_ARRAY <<< "$ALLOWED_SERVICES"

# default services to install if not specified
SERVICES_RAW="mysql,redis"

# regex for project name validation
# only lowercase letters, numbers, dashes (-), and underscores (_) are allowed, you can change it if you want
project_name_regex='^[a-z0-9_-]+$'

# default environment variables
APP_NAME=${APP_NAME:-"my-laravel-app"}
APP_PORT=${APP_PORT:-8000}
PHPMYADMIN_PORT=${PHPMYADMIN_PORT:-3000}

# cleanup the containers
cleanup() {
    echo -e "\n${YELLOW}Stopping containers...${NC}"
    docker-compose down
    echo -e "${GREEN}Containers stopped successfully${NC}"
    exit 0
}

# check if the inserted port (for Laravel, phpMyAdmin..) is free
# if the port is free, return 0, otherwise return 1
free_port() {
    local port=\$1
    if command -v nc >/dev/null 2>&1; then
        nc -z 127.0.0.1 "$port" >/dev/null 2>&1
        [ $? -ne 0 ]
    else
        # Fallback: use lsof
        ! lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    fi
}

# secure permissions setters
set_secure_permissions() {
    for DIR in storage bootstrap/cache; do
        if [ -d "$DIR" ]; then
            # set owner to current user and permissions to 700
            chown -R "$(id -u):$(id -g)" "$DIR"
            chmod -R u+rwX,go-rwx "$DIR"
        fi
    done
}

# register the cleanup function to be called on the EXIT signal
trap cleanup EXIT SIGINT SIGTERM

# load environment variables from .env file if it exists
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo -e "${GREEN}=== ${APP_NAME} Setup ===${NC}"

# check if laravel project is already installed or not. If not, create a new laravel project
if [ ! -f "artisan" ]; then
    echo -e "${GREEN}First time setup: Laravel project will be created.${NC}"

    # project name prompt
    while true; do
        echo -e "${YELLOW}Enter a project name (lowercase, numbers, dashes -, or underscores _, no spaces):${NC}"
        read -r APP_NAME
        if [[ "$APP_NAME" =~ $project_name_regex ]]; then
            break
        else
            echo -e "${RED}Invalid project name! Use only lowercase letters, numbers, dashes -, or underscores _. No spaces allowed.${NC}"
        fi
    done

    # prompt user for services to install
    while true; do
        echo -e "${YELLOW}Enter space or comma-separated Sail services to install (default: mysql,redis):${NC}"
        echo -e "${YELLOW}Available services:${NC} $ALLOWED_SERVICES"
        read -r SERVICES_RAW
        SERVICES_RAW=${SERVICES_RAW:-"mysql,redis"}

        # Convert input into array, splitting by comma or space
        IFS=', ' read -ra SERVICE_ARRAY <<< "$SERVICES_RAW"
        ALL_VALID=true

        # For pretty formatting
        SERVICE_ARRAY_TRIM=()

        # Loop through each service and check if it's valid
        for S in "${SERVICE_ARRAY[@]}"; do
            S_LOWER=$(echo "$S" | tr '[:upper:]' '[:lower:]' | xargs)
            IS_VALID=false
            for allowed in "${ALLOWED_ARRAY[@]}"; do
                if [[ "$S_LOWER" == "$allowed" ]]; then
                    IS_VALID=true
                    SERVICE_ARRAY_TRIM+=("$S_LOWER")
                    break
                fi
            done
            if ! $IS_VALID; then
                echo -e "${RED}Service '$S' is not valid! Please re-enter the list.${NC}"
                ALL_VALID=false
                break
            fi
        done
        if $ALL_VALID && ((${#SERVICE_ARRAY_TRIM[@]} > 0)); then
            SERVICES=$(IFS=, ; echo "${SERVICE_ARRAY_TRIM[*]}")
            break
        fi
    done

    echo -e "${GREEN}Selected services: $SERVICES${NC}"

    # Use official build tool to create project
    curl -s https://laravel.build/${APP_NAME}?with=${SERVICES//,/%2C} | bash

    # move all files up
    if [ -d "${APP_NAME}" ]; then
        shopt -s dotglob nullglob
        mv ${APP_NAME}/* . 2>/dev/null
        rm -rf "${APP_NAME}"
        shopt -u dotglob nullglob
    fi

    echo -e "${YELLOW}Ignore the above "Get started" message, we are already in the project folder :)${NC}"

    # check if MySQL was selected during service selection, if so, ask if want to add phpMyAdmin
    if [[ ",$SERVICES," == *"mysql"* ]]; then

        # prompt user for phpMyAdmin installation
        while true; do
            echo -e "${YELLOW}Do you want to add phpMyAdmin for MySQL? (y/n) [default: y]:${NC}"
            read -r ADD_PHPMYADMIN
            ADD_PHPMYADMIN=${ADD_PHPMYADMIN:-y}
            case "$ADD_PHPMYADMIN" in
                [Yy]* ) break ;;
                [Nn]* ) break 2 ;;
                * ) echo -e "${RED}Please answer yes or no (y/n).${NC}" ;;
            esac
        done

        if [[ "$ADD_PHPMYADMIN" =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}phpMyAdmin will not be installed.${NC}"
        else
            echo -e "${GREEN}phpMyAdmin will be installed.${NC}"
            echo -e "${GREEN}Adding phpMyAdmin service to docker-compose.yml...${NC}"

            # append phpmyadmin service if not already present
            if ! grep -q "phpmyadmin" docker-compose.yml; then
                # insert in "services" section, we use awk to find the line with "services:" and insert after it
                # Use lscr.io/linuxserver/phpmyadmin:latest as image because it can support also Mac with Apple Silicon
                awk '
                    /^services:/ {
                        print
                        print "    phpmyadmin:"
                        print "        image: lscr.io/linuxserver/phpmyadmin:latest"
                        print "        ports:"
                        print "            - \"${PHPMYADMIN_PORT:-3000}:80\""
                        print "        environment:"
                        print "            PMA_HOST: mysql"
                        print "            MYSQL_ROOT_PASSWORD: \"${DB_PASSWORD}\""
                        print "        networks:"
                        print "            - sail"
                        print "        depends_on:"
                        print "            - mysql"
                        next
                    }
                    { print }
                ' docker-compose.yml > docker-compose.temp.yml && mv docker-compose.temp.yml docker-compose.yml && rm -f docker-compose.temp.yml

                echo -e "${GREEN}phpMyAdmin service added to docker-compose.yml!${NC}"
            else
                echo -e "${YELLOW}phpMyAdmin service already exists in docker-compose.yml.${NC}"
            fi

            # prompt for phpMyAdmin port (PHPMYADMIN_PORT)
            while true; do
                echo -e "${YELLOW}Insert the port for phpMyAdmin (default: 3000):${NC}"
                read -r PHPMYADMIN_PORT
                PHPMYADMIN_PORT=${PHPMYADMIN_PORT:-3000}
                if [[ "$PHPMYADMIN_PORT" =~ ^[0-9]+$ ]] && [ "$PHPMYADMIN_PORT" -ge 1 ] && [ "$PHPMYADMIN_PORT" -le 65535 ]; then
                    if free_port "$PHPMYADMIN_PORT"; then
                        break
                    else
                        echo -e "${RED}Port $PHPMYADMIN_PORT is already in use. Choose another one.${NC}"
                    fi
                else
                    echo -e "${RED}Port not valid. Insert a number between 1 e 65535.${NC}"
                fi
            done

            # Edit/add PHPMYADMIN_PORT in .env file
            if grep -q '^PHPMYADMIN_PORT=' .env; then
                sed -i.bak "s|^PHPMYADMIN_PORT=.*|PHPMYADMIN_PORT=${PHPMYADMIN_PORT}|" .env
            else
                echo "PHPMYADMIN_PORT=${PHPMYADMIN_PORT}" >> .env
            fi

            # add PHPMYADMIN_PORT in .env.example file if not present
            if ! grep -q '^PHPMYADMIN_PORT=' .env.example; then
                echo "PHPMYADMIN_PORT=''" >> .env.example
            fi
        fi
    fi

    # check if PostgreSQL (pgsql) is among the selected services
    if [[ ",$SERVICES," == *"pgsql"* ]]; then
        
        # prompt user for pgAdmin installation
        while true; do
            echo -e "${YELLOW}Do you want to add pgAdmin for PostgreSQL? (y/n) [default: y]:${NC}"
            read -r ADD_PGADMIN
            ADD_PGADMIN=${ADD_PGADMIN:-y}
            case "$ADD_PGADMIN" in
                [Yy]* ) break ;;
                [Nn]* ) break 2 ;;
                * ) echo -e "${RED}Please answer yes or no (y/n).${NC}" ;;
            esac
        done

        if [[ "$ADD_PGADMIN" =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}pgAdmin will not be installed.${NC}"
        else
            echo -e "${GREEN}pgAdmin will be installed.${NC}"

            # add pgAdmin service to docker-compose.yml
            if ! grep -q "pgadmin" docker-compose.yml; then
                echo -e "${GREEN}Adding pgAdmin service to docker-compose.yml...${NC}"
                
                # Modify the Docker Compose file dynamically
                awk -v port="$PGADMIN_PORT" '
                    /^services:/ {
                        print
                        print "    pgadmin:"
                        print "        image: dpage/pgadmin4:latest"
                        print "        ports:"
                        print "            - \"${PGADMIN_PORT:-5050}:80\""
                        print "        environment:"
                        print "            PGADMIN_DEFAULT_EMAIL: admin@admin.com"
                        print "            PGADMIN_DEFAULT_PASSWORD: admin"
                        print "        depends_on:"
                        print "            - pgsql"
                        print "        networks:"
                        print "            - sail"
                        print "        volumes:"
                        print "            - ./pgadmin-data:/var/lib/pgadmin"
                        next
                    }
                    { print }
                ' docker-compose.yml > docker-compose.temp.yml && mv docker-compose.temp.yml docker-compose.yml && rm -f docker-compose.temp.yml
                
                echo -e "${GREEN}pgAdmin service added to docker-compose.yml!${NC}"
            else
                echo -e "${YELLOW}pgAdmin service already exists in docker-compose.yml.${NC}"
            fi

            # default pgAdmin port
            while true; do
                echo -e "${YELLOW}Enter the port for pgAdmin (default: 5050):${NC}"
                read -r PGADMIN_PORT
                PGADMIN_PORT=${PGADMIN_PORT:-5050}
                if [[ "$PGADMIN_PORT" =~ ^[0-9]+$ ]] && [ "$PGADMIN_PORT" -ge 1 ] && [ "$PGADMIN_PORT" -le 65535 ]; then
                    if free_port "$PGADMIN_PORT"; then
                        break
                    else
                        echo -e "${RED}Port $PGADMIN_PORT is already in use. Choose another one.${NC}"
                    fi
                else
                    echo -e "${RED}Port not valid. Insert a number between 1 and 65535.${NC}"
                fi
            done

            # add PGADMIN_PORT to .env if not present
            if grep -q '^PGADMIN_PORT=' .env; then
                sed -i.bak "s|^PGADMIN_PORT=.*|PGADMIN_PORT=${PGADMIN_PORT}|" .env
            else
                echo "PGADMIN_PORT=${PGADMIN_PORT}" >> .env
            fi

            # add PGADMIN_PORT in .env.example file if not present
            if ! grep -q '^PGADMIN_PORT=' .env.example; then
                echo "PGADMIN_PORT=''" >> .env.example
            fi
        fi
    fi

    echo -e "${GREEN}Laravel project created successfully!${NC}"

    # prompt for Laravel port (APP_PORT)
    while true; do
        echo -e "${YELLOW}Insert the port for Laravel (default: 8000):${NC}"
        read -r APP_PORT
        APP_PORT=${APP_PORT:-8000}
        if [[ "$APP_PORT" =~ ^[0-9]+$ ]] && [ "$APP_PORT" -ge 1 ] && [ "$APP_PORT" -le 65535 ]; then
            if free_port "$APP_PORT"; then
                break
            else
                echo -e "${RED}The port $APP_PORT is already in use. Choose another one.${NC}"
            fi
        else
            echo -e "${RED}Port not valid. Insert a number between 1 e 65535.${NC}"
        fi
    done

    echo -e "${YELLOW}Setting up environment variables...${NC}"

    # edit/add APP_PORT in .env file
    if grep -q '^APP_PORT=' .env; then
        sed -i.bak "s|^APP_PORT=.*|APP_PORT=${APP_PORT}|" .env
    else
        echo "APP_PORT=${APP_PORT}" >> .env
    fi

    # add APP_PORT in .env.example file if not present
    if ! grep -q '^APP_PORT=' .env.example; then
        echo "APP_PORT=''" >> .env.example
    fi

    # edit the port in APP_URL
    if grep -q '^APP_URL=' .env; then
        sed -i.bak "s|^APP_URL=.*|APP_URL=http://localhost:${APP_PORT}|" .env
    else
        echo "APP_URL=http://localhost:${APP_PORT}" >> .env
    fi
    
    # add WWWUSER=1000 to .env if not present
    if ! grep -q "^WWWUSER=" .env; then
        echo "WWWUSER=1000" >> .env
    else
        sed -i "s/^WWWUSER=.*/WWWUSER=1000/" .env
    fi

    # add WWWUSER in .env.example file if not present
    if ! grep -q '^WWWUSER=' .env.example; then
        echo "WWWUSER=''" >> .env.example
    fi

    # add WWWGROUP=1000 to .env if not present
    if ! grep -q "^WWWGROUP=" .env; then
        echo "WWWGROUP=1000" >> .env
    else
        sed -i "s/^WWWGROUP=.*/WWWGROUP=1000/" .env
    fi

    # add WWWGROUP in .env.example file if not present
    if ! grep -q '^WWWGROUP=' .env.example; then
        echo "WWWGROUP=''" >> .env.example
    fi

    # remove eventual backup created from sed (.bak)
    rm -f .env.bak

    # run migrations
    echo -e "${GREEN}Running database migrations...${NC}"
    docker-compose run --rm laravel.test php artisan migrate

    # install npm dependencies
    echo -e "${GREEN}Installing npm dependencies...${NC}"
    docker-compose run --rm laravel.test npm install
else
    echo -e "${GREEN}Laravel already installed, proceeding with container setup...${NC}"
fi

echo -e "${GREEN}Starting Docker containers...${NC}"

# stop and remove the containers if they are already running
docker-compose down

# start containers in detached mode
docker-compose up -d --build

# check container status
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Containers started successfully!${NC}"
    echo -e "${YELLOW}Available URLs:${NC}"

    echo "Laravel: http://localhost:${APP_PORT}"

    if grep -q '^PHPMYADMIN_PORT=' .env; then
        echo "PhpMyAdmin: http://localhost:${PHPMYADMIN_PORT}"
    fi

    if grep -q '^PGADMIN_PORT=' .env; then
        echo "PgAdmin: http://localhost:${PGADMIN_PORT}"
    fi
    echo "Vite: run 'npm run dev' in the container to start Vite server"

    echo -e "${GREEN}Setting permissions...${NC}"
    set_secure_permissions
    echo -e "${GREEN}Permissions set successfully!${NC}"

    echo -e "${GREEN}Waiting to setup everything...${NC}"

    # extra wait time for the containers to be fully up
    sleep 5

    echo -e "${GREEN}Entering container bash...${NC}"
    docker-compose exec laravel.test bash
else
    echo -e "${RED}Error starting containers${NC}"
    exit 1
fi
