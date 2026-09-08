
COMPOSE_FILE   = src/docker-compose.yml
DATA_DIR       = /home/sel-ghai/data
LOGIN          ?= $(shell whoami)

all: up

up:
	@echo "Creating data directories if missing..."
	@mkdir -p $(DATA_DIR)/db
	@mkdir -p $(DATA_DIR)/wordpress
	@echo "Starting containers..."
	docker compose -f $(COMPOSE_FILE) up --build -d

down:
	@echo "Stopping containers (data preserved)..."
	docker compose -f $(COMPOSE_FILE) down

stop:
	docker compose -f $(COMPOSE_FILE) stop

start:
	docker compose -f $(COMPOSE_FILE) start

restart: down up

ps:
	docker compose -f $(COMPOSE_FILE) ps

logs:
	docker compose -f $(COMPOSE_FILE) logs -f

logs-db:
	docker compose -f $(COMPOSE_FILE) logs -f mariadb

logs-php:
	docker compose -f $(COMPOSE_FILE) logs -f wordpress

logs-nginx:
	docker compose -f $(COMPOSE_FILE) logs -f nginx

clean: down
	@echo "Removing containers, networks and named volumes..."
	docker compose -f $(COMPOSE_FILE) down -v

fclean: clean
	@echo "Wiping host data directories..."
	sudo rm -rf $(DATA_DIR)/db
	sudo rm -rf $(DATA_DIR)/wordpress
	@echo "Pruning dangling Docker images/build cache..."
	docker system prune -af

re: fclean up

.PHONY: all up down stop start restart ps logs logs-db logs-php logs-nginx clean fclean re
