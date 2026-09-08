*This project has been created as part of the 42 curriculum by sel-ghai.*

# Inception

## Description

Inception is a system administration project that consists of building a small, production-style web infrastructure entirely with Docker, without relying on prebuilt images from Docker Hub (each service is built from a base OS image, using a hand-written Dockerfile).

The goal is to deploy a WordPress site, served over HTTPS, backed by a MariaDB database, with each component isolated in its own container, each container built from its own Dockerfile, all orchestrated through a single `docker-compose.yml`. In short: a minimal, self-contained WordPress hosting stack that starts with one command and can be torn down and rebuilt from scratch just as easily.

The stack is made up of three services:

| Service | Role |
|---|---|
| `nginx` | Reverse proxy and TLS termination — the only container exposed to the host, listening on port 443 (HTTPS only, no plain HTTP). |
| `wordpress` | PHP-FPM running WordPress core. Has no web server of its own — it only executes PHP and hands rendered output back to Nginx. |
| `mariadb` | The database backend used by WordPress to store all site content, users, and settings. |

```
Browser ──HTTPS(443)──▶ nginx ──FastCGI(9000)──▶ wordpress (php-fpm) ──TCP(3306)──▶ mariadb
```

## Instructions

### Prerequisites

- Docker Engine with the Compose plugin (`docker compose`).
- `make`.
- `sudo` privileges (required by `make fclean`, which removes host data directories).

### Configuration

Before the first run, create an `.env` file (not committed to the repository) at the path expected by `docker-compose.yml` — see `USER_DOC.md` for the exact variables required (domain name, database credentials, WordPress admin/user credentials).

### Build & run

```bash
make 
```

Once running, the site is reachable at `https://sel-ghai.42.fr:443`. Full command reference (`stop`, `down`, `clean`, `fclean`, `logs`, etc.) is documented in `USER_DOC.md` and `DEV_DOC.md`.

### Further documentation

- **[USER_DOC.md](./USER_DOC.md)** — how to use the stack day to day: starting/stopping it, accessing the site and admin panel, managing credentials, checking service health.
- **[DEV_DOC.md](./DEV_DOC.md)** — how to set up the project from scratch as a developer, build/launch mechanics, container/volume management commands, and data persistence details.

## Project description: Docker usage and sources

### Why Docker here

Each service (`nginx`, `wordpress`, `mariadb`) is built from its **own Dockerfile**, starting from a minimal base image (no ready-made `nginx`/`wordpress`/`mariadb` images from Docker Hub, per project constraints), with only the packages each service strictly needs installed on top. This keeps each container small, single-purpose, and easy to reason about: if the database needs upgrading or the PHP version needs bumping, only that one image is rebuilt, and the failure of one container's process (e.g. Nginx crashing) doesn't take down the others.

### Sources / structure

```
srcs/
├── docker-compose.yml
├── .env                     # not committed
└── requirements/
    ├── nginx/
    │   ├── Dockerfile
    │   ├── conf/
    ├── wordpress/
    │   ├── Dockerfile
    │   ├── conf/
    │   └── tools/
    └── mariadb/
        ├── Dockerfile
        ├── conf/
        └── tools/
```

Each `tools/entrypoint.sh` script is written to be **idempotent** — safe to re-run on every container start (e.g. checking `wp core is-installed` before running `wp core install`) — since `restart: always` means these scripts may execute many times over a container's lifetime, not just once.

### Main design choices

- **One process per container**, communicating only over the network (FastCGI on 9000, MySQL protocol on 3306) or through a shared volume for WordPress files — never by sharing a container's process namespace or filesystem directly.
- **Only `nginx` is exposed to the host** (`443:443`); `wordpress` and `mariadb` are reachable only from inside the Docker network, addressed by service name via Compose's embedded DNS.
- **TLS termination happens at Nginx**, with a self-signed certificate generated at image build time (see `DEV_DOC.md` for detail and its limitations).
- **Persistent data lives on bind-mounted host directories**, not inside any container's writable layer, so `down`/`stop`/`restart` never lose data, and only an explicit `fclean` does.
- **Secrets are injected via `.env` and Compose `env_file:`**, never hardcoded into a Dockerfile or committed to the repository.

### Virtual Machines vs Docker

| | Virtual Machine | Docker |
|---|---|---|
| Isolation | Full hardware virtualization via a hypervisor; each VM runs its own complete OS kernel. | Kernel-level isolation on the host (namespaces + cgroups); containers share the host kernel. |
| Overhead | Heavy — each VM needs its own kernel, drivers, and boots a full OS (minutes, GBs of RAM/disk). | Light — a container is just an isolated process; starts in milliseconds/seconds, MBs of overhead. |
| Startup time | Slow (full OS boot). | Fast (no OS boot, just process start). |
| Use case fit here | Overkill for isolating three cooperating services that don't need separate kernels. | A natural fit — each service is just a process with its own filesystem view, wired together over a lightweight virtual network. |
| Security boundary | Stronger — a compromised VM cannot directly touch the host kernel. | Weaker by default — containers share the host kernel, so a kernel exploit can, in principle, cross container boundaries; mitigated by namespaces/cgroups/capabilities, not eliminated. |

Docker was the right tool here because the goal is fast, reproducible, easily torn-down/rebuilt service isolation, not strict kernel-level security boundaries between mutually distrusting tenants.

### Secrets vs Environment Variables

This project uses **environment variables** (injected via `.env` and Compose `env_file:`) to pass secrets (database credentials, WordPress admin password) into containers. This is a simple, effective approach for a single-user, single-stack setup like this one.

### Docker Network vs Host Network

| | Docker (bridge) Network | Host Network |
|---|---|---|
| Isolation | Containers get their own network namespace and IP, reachable from other containers by service name via Compose's embedded DNS; isolated from the host's network stack. | Container shares the host's network namespace directly — no isolation, no virtual interface, ports bind straight onto the host. |
| Port exposure | Explicit — only ports you `ports:` map are reachable from outside the Docker network. | Everything the process binds to is immediately exposed on the host, with no mapping step. |
| Used in this project | Used — a dedicated `inception` bridge network, with only `nginx`'s port 443 published to the host; `wordpress` and `mariadb` are unreachable from outside the Docker network entirely. | Not used. |
| Why | Matches the principle of least exposure: the database and PHP-FPM have no business being reachable from outside the stack, and bridge networking with named service resolution makes inter-container communication (`wordpress:9000`, `mariadb:3306`) simple without hardcoding IPs. | Would unnecessarily expose internal services and remove the network-level isolation between containers. |

### Docker Volumes vs Bind Mounts

| | Docker (named) Volumes | Bind Mounts |
|---|---|---|
| Managed by | Docker itself, stored under Docker's own data directory (e.g. `/var/lib/docker/volumes/...`), abstracted from the host's directory layout. | Directly maps a specific host path into the container; the host path is chosen and owned by you. |
| Portability | More portable — doesn't depend on a specific host path existing. | Tied to a specific host path; less portable across machines. |
| Used in this project | The volumes are declared as **named volumes in `docker-compose.yml`**, but configured with `driver_opts: { type: none, o: bind, device: ... }` — which makes them **bind mounts under the hood**, pinned to `/home/sel-ghai/data/wordpress` and `/home/sel-ghai/data/db` on the host. | Effectively what's used here, via the named-volume-as-bind-mount pattern above. |
| Why this choice | Gives the convenience of referencing volumes by name in Compose (`volumes: wordpress:`) while guaranteeing the data lands at a specific, predictable, inspectable host path — which is also what lets `make fclean` delete the data with a plain host-side `rm -rf`, and lets you browse the WordPress files or DB data directly from the host without going through a container. | — |

## Resources

### References

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Nginx documentation](https://nginx.org/en/docs/)
- [Nginx `location`/`try_files` directive reference](https://nginx.org/en/docs/http/ngx_http_core_module.html)
- [WordPress WP-CLI documentation](https://developer.wordpress.org/cli/commands/)
- [PHP-FPM configuration documentation](https://www.php.net/manual/en/install.fpm.configuration.php)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [OpenSSL `req` command documentation](https://docs.openssl.org/master/man1/openssl-req/)
- [42's Inception subject PDF (project handout)]

### AI usage

An AI assistant (Claude) was used during this project for:
- Explaining general Docker concepts (image layers, OverlayFS, namespaces/cgroups, how `docker run` assembles and starts a container) for background understanding.
- Drafting the structure and initial content of this `README.md`, `USER_DOC.md`, and `DEV_DOC.md`, based on the project's actual `Makefile` and `docker-compose.yml` and on the explanations given earlier in the conversation — reviewed and adjusted by the author(s) before submission.

AI was not used to generate the Dockerfiles, entrypoint scripts, or Nginx/PHP-FPM configuration themselves.
