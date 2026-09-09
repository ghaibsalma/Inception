# User Documentation

This guide is for anyone running or administering the stack day to day — no Docker internals required here (see `DEV_DOC.md` for that).

## 1. What services does the stack provide?

| Service | What it does, in plain terms |
|---|---|
| **nginx** | The front door. Handles all incoming HTTPS traffic and forwards page requests to WordPress. This is the only thing reachable from outside the stack. |
| **wordpress** | The actual website — runs WordPress and generates every page you see. |
| **mariadb** | The database — stores every post, page, user, comment, and setting behind the scenes. Not directly reachable from outside the stack. |

Together, they provide one thing to the end user: a WordPress website reachable over HTTPS, plus its administration panel.

## 2. Starting and stopping the project

All operations go through `make`, run from the project root.

| Command | Effect |
|---|---|
| `make` (same as `make up`) | Starts everything. First run also builds the images and creates the data folders. |
| `make down` | Stops and removes the containers. **Your data is kept.** |
| `make stop` | Pauses the containers without removing them (quicker to resume). |
| `make start` | Resumes containers previously paused with `make stop`. |
| `make restart` | Full stop + start in one step. Use this after changing `.env`. |
| `make clean` | Like `down`, and also removes Docker's internal volume/network records. Your data on disk is still kept. |
| `make fclean` | **Deletes your website and database permanently**, and cleans up unused Docker images. Use only if you want to start from a truly empty slate. |
| `make re` | `fclean` + `up` — wipes everything and rebuilds fresh. |

**Day-to-day routine:**
```bash
make up  
make down
```

## 3. Accessing the website and the administration panel

- **Website**: `https://<DOMAIN_NAME>` — replace `<DOMAIN_NAME>` with the value set in `.env`.
- **Administration panel**: `https://<DOMAIN_NAME>/wp-admin` — log in with the WordPress admin username and password (see §4 for where to find these).

The site is served only over HTTPS (no plain HTTP). The certificate is self-signed, so your browser will show a security warning the first time — this is expected; click "Advanced" → "Proceed" (wording varies by browser) to continue.

## 4. Locating and managing credentials

All credentials are defined in a single **`.env` file**, which lives in the project (not committed to version control, since it holds secrets). It should contain, at minimum:

- `DOMAIN_NAME` — the domain the site is served on.
- `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD` — MariaDB credentials.
- `WP_ADMIN_USER`, `WP_ADMIN_PASSWORD`, `WP_ADMIN_EMAIL` — the WordPress administrator account, created automatically the first time the stack starts.
- `WP_USER`, `WP_EMAIL`, `WP_USER_PASSWORD` — a second, non-admin WordPress account, also created automatically.

**To change a password or username:** edit the `.env` file, then run `make restart`. Note that changing `WP_ADMIN_USER`/`WP_USER` in `.env` after the accounts already exist will **not** rename the existing WordPress account — WordPress usernames are only set at account-creation time. To change an existing account's password without touching usernames, either update it directly from the WordPress admin panel (Users → your profile), or via WP-CLI:

```bash
docker exec wordpress wp user update <username> --user_pass=<new_password> --allow-root
```

**Never commit `.env` to a public repository** — it contains database and admin passwords in plain text.

## 5. Checking that the services are running correctly

**Check container status:**
```bash
make ps
```
All three services (`nginx`, `wordpress`, `mariadb`) should show as `Up`. If one shows `Restarting` or `Exited`, it's crash-looping — check its logs (below).

**Check logs:**
```bash
make logs      
make logs-nginx
make logs-php  
make logs-db   
```

**Confirm the site actually responds:**
```bash
curl -Ik https://<DOMAIN_NAME>
```
A `200 OK` (or a redirect) means the site is responding. `-k` skips certificate validation, needed here because of the self-signed cert.

**Confirm WordPress users exist as expected:**
```bash
docker exec wordpress wp user list --allow-root
```

### Common issues

| Symptom | What to check |
|---|---|
| Browser can't reach the site at all | `make ps` — is `nginx` up? Does `<DOMAIN_NAME>` resolve (check `/etc/hosts` or DNS)? |
| "502 Bad Gateway" | `wordpress` container is down or unhealthy — check `make logs-php`. |
| Database connection error on the page | `mariadb` isn't ready or credentials in `.env` are wrong — check `make logs-db`. |
| Certificate warning in the browser | Expected — the certificate is self-signed. Not an error. |
| Edited `.env` but nothing changed | Run `make restart` — environment variables are only read when a container starts. |
