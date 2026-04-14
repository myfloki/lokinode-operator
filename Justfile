set shell := ["bash", "-c"]

DOCKER_COMPOSE := if `docker compose version &> /dev/null` == "0" { "docker compose" } else { "docker-compose" }

# Onboard a new operator (create data folders, setup wallet, etc.)
setup:
    ./setup.sh

# Start the operator services
up:
    {{DOCKER_COMPOSE}} up -d

# Stop the operator services
down:
    {{DOCKER_COMPOSE}} down

# Restart the operator services
restart:
    {{DOCKER_COMPOSE}} restart

# View logs for all services
logs:
    {{DOCKER_COMPOSE}} logs -f

# View logs for flnd
logs-flnd:
    {{DOCKER_COMPOSE}} logs -f flnd

# View logs for lokihub
logs-lokihub:
    {{DOCKER_COMPOSE}} logs -f lokihub

# Show status of services
status:
    {{DOCKER_COMPOSE}} ps
