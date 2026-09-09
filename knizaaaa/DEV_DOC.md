# Developer Documentation

Technical reference for setting up, building, and operating this project as a developer. See `USER_DOC.md` for end-user/admin instructions, and `README.md` for the overall architecture and design-choice rationale.

## 1. Setting up the environment from scratch

### 1.1 Prerequisites

- Docker Engine with the Compose plugin (`docker compose`).
- `make`.
- A Linux host (or VM) with `sudo` access — required by `make fclean`, which removes host directories.
- A domain name (or a hosts-file entry pointing a local domain at `127.0.0.1`) if you want to reach the site by a real hostname rather than an IP.

### 1.2 Repository layout

```
.
├── Makefile
└── srcs/
    ├── docker-compose.yml
    ├── .env                    # not committed — created by you, see below
    └── requirements/
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/            # nginx.conf
        │   └── tools/            # TLS cert generation, if not done in-Dockerfile
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── conf/              # www.conf (php-fpm pool)
        │   └── tools/               # entrypoint.sh (wp-cli install/user provisioning)
        └── mariadb/
            ├── Dockerfile
            ├── conf/
            └── tools/               # entrypoint.sh (DB init/user provisioning)
```

### 1.3 Configuration files and secrets

Nothing will start correctly without an `.env` file (referenced via `env_file:` for both `wordpress` and `mariadb` in `docker-compose.yml`). Create one at the path `docker-compose.yml` expects, containing at minimum:

```dotenv
DOMAIN_NAME=yourlogin.42.fr

MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
MYSQL_PASSWORD=change_me
MYSQL_ROOT_PASSWORD=change_me_too

WP_ADMIN_USER=admin_login
WP_ADMIN_PASSWORD=change_me
WP_ADMIN_EMAIL=admin@example.com

WP_USER=second_user
WP_EMAIL=second_user@example.com
WP_USER_PASSWORD=change_me
```

This file must **never** be committed — add it to `.gitignore`. It's the only place secrets live; nothing is hardcoded into any Dockerfile or config file (see `README.md` §"Secrets vs Environment Variables" for the reasoning).

If your domain isn't publicly resolvable, map it locally:
```bash
echo "127.0.0.1 yourlogin.42.fr" | sudo tee -a /etc/hosts
```

## 2. Building and launching via Makefile / Docker Compose

The `Makefile` wraps `docker compose -f srcs/docker-compose.yml <command>` so you rarely need to invoke Compose directly.

```makefile
COMPOSE_FILE = srcs/docker-compose.yml
DATA_DIR     = /home/sel-ghai/data
```

| `make` target | Underlying action |
|---|---|
| `up` (default) | `mkdir -p $(DATA_DIR)/db $(DATA_DIR)/wordpress`, then `docker compose -f $(COMPOSE_FILE) up --build -d`. The `mkdir` step is required *before* Compose runs, since the bind-mount volumes fail to mount if the host path doesn't exist yet. `--build` re-checks/rebuilds images (fast on a cache hit — see §3), `-d` runs detached. |
| `down` | `docker compose ... down` — stops and removes containers, keeps volumes/network definitions and all host data. |
| `stop` / `start` | `docker compose ... stop` / `start` — pause/resume without removing containers. |
| `restart` | `down` then `up`. |
| `ps` | `docker compose ... ps` — container status. |
| `logs` / `logs-nginx` / `logs-php` / `logs-db` | `docker compose ... logs -f [service]` — follow logs, all or per service. |
| `clean` | `down -v` — additionally removes the named volumes and network from Docker's bookkeeping. Since the volumes are bind mounts (see §4), host data is untouched. |
| `fclean` | `clean` + `sudo rm -rf $(DATA_DIR)/db $(DATA_DIR)/wordpress` + `docker system prune -af`. Destroys all persisted data and prunes unused images/build cache system-wide (not scoped to this project). |
| `re` | `fclean` then `up` — full wipe and rebuild. |

You can still call Compose directly if you need finer control than the Makefile exposes, e.g.:
```bash
docker compose -f srcs/docker-compose.yml build wordpress   # rebuild a single service
docker compose -f srcs/docker-compose.yml up -d --no-deps wordpress  # restart one service only
```

## 3. Image build mechanics (relevant when modifying Dockerfiles)

Each `RUN`/`COPY`/`ADD` instruction produces one image layer; `ENV`/`CMD`/`WORKDIR`/etc. only touch metadata. Layer cache keys depend on the instruction text **and** the parent layer's hash — so:

- Put rarely-changing steps (`apt update && apt install ...`) **before** frequently-changing steps (`COPY` of your own config/scripts) in each Dockerfile, so editing a config file doesn't force a full package reinstall on every `make up`.
- If a build seems to be using stale files, force a clean rebuild with:
  ```bash
  docker compose -f srcs/docker-compose.yml build --no-cache
  ```

At container start, Docker mounts an OverlayFS stack (image layers read-only + one writable layer per container). Anything written outside a mounted volume disappears when the container is removed — which is exactly why WordPress files and the database live on the bind-mounted volumes described next, not inside the container itself.

## 4. Managing containers and volumes

### Containers
```bash
make ps                          
make logs-nginx                  
docker exec -it wordpress bash   
docker exec wordpress wp user list --allow-root   
```

### Volumes / networks
```bash
docker volume ls                 
docker network ls                
docker compose -f srcs/docker-compose.yml down -v   

`docker-compose.yml` declares `wordpress` and `db_data` as named volumes, but pins them to specific host paths via `driver_opts`:

```yaml
volumes:
  wordpress:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/sel-ghai/data/wordpress
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/sel-ghai/data/db
```

This makes them **bind mounts under a named-volume interface** — you get Compose's convenient `volumes: wordpress:` syntax in each service, while the data is guaranteed to live at a specific, host-inspectable path rather than inside Docker's internal storage. See `README.md` for the full Docker Volumes vs Bind Mounts comparison and why this hybrid approach was chosen.

## 5. Where project data lives and how it persists

| Data | Host path | Mounted into | Survives `down`/`stop`/`restart`? | Survives `clean`? | Survives `fclean`/`re`? |
|---|---|---|---|---|---|
| WordPress files (core, themes, plugins, uploads) | `/home/sel-ghai/data/wordpress` | `nginx` and `wordpress`, both at `/var/www/html` | Yes | Yes | **No — deleted** |
| MariaDB data directory | `/home/sel-ghai/data/db` | `mariadb`, at `/var/lib/mysql` | Yes | Yes | **No — deleted** |

`nginx` and `wordpress` share the **same** volume at the same mount path, which is required: Nginx's `try_files` needs to see the WordPress files on disk to distinguish static assets from PHP requests, while PHP-FPM (in the `wordpress` container) needs those same files to execute them. Two containers, one shared filesystem view — only possible because both mount the identical named volume.

### Idempotent provisioning

Both the `wordpress` and `mariadb` entrypoint scripts are written to be safe to re-run on every container start (since `restart: always` means they may run many times over the stack's lifetime, not just once):

```bash
if ! wp core is-installed --allow-root; then
    wp core install --url=https://${DOMAIN_NAME} ... --allow-root
fi
if ! wp user get ${WP_USER} --field=ID --allow-root >/dev/null 2>&1; then
    wp user create ${WP_USER} ${WP_EMAIL} --user_pass=${WP_USER_PASSWORD} --allow-root
fi
```

On a fresh volume, these blocks run and provision the site. On a container restart with the same (persisted) volume, the checks succeed and the blocks are skipped — no duplicate install attempts, no errors.

### Full data wipe

```bash
make fclean   
```

This is the only path that deletes `/home/sel-ghai/data/{db,wordpress}` on the host. Everything else (`down`, `stop`, `clean`) leaves this data untouched, since it never lived inside a container's writable layer to begin with — it's always been on the host, just bind-mounted in.
