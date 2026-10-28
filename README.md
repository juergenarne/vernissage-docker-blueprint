# Vernissage with Docker Compose

A complete, self-hosted [Vernissage](https://joinvernissage.org) instance (the Fediverse photo-sharing platform) on an Ubuntu server – set up with a **single** command.

The stack closely follows the official installer [`vernissagectl`](https://github.com/VernissageApp/VernissageInstaller), but is built for an **existing host Nginx**: the instance only listens on `127.0.0.1:<port>`, and HTTPS is handled by the host Nginx with certbot.

```
Internet ─▶ host Nginx (TLS, certbot) ─▶ 127.0.0.1:8180 ─▶ proxy ─┬─▶ web    (Angular)
                                                                  ├─▶ api    (Swift/Vapor, ActivityPub)
                                                                  └─▶ minio  (/static-resource/ → images)
                       jobs (queues/scheduler) · push (Web Push) · postgres · redis
```

## Installation

Requirements: an Ubuntu server and a DNS record for the domain pointing at it. Docker and the Compose plugin are installed by `init.sh` if necessary.

```bash
git clone <this-repo>.git my-vernissage
cd my-vernissage
./init.sh
```

`init.sh`

1. checks for (and if need be installs) Docker and the Compose plugin,
2. asks for the domain, local port, maximum upload size and image tag,
3. generates all passwords and keys (PostgreSQL, Redis, MinIO, Web Push key, VAPID key pair) into `.env.local` (`chmod 600`; `.env` is a symlink to it),
4. builds MinIO from source (as the official installer does – there are no maintained MinIO images any more), creates the bucket and makes its objects publicly readable,
5. starts everything with `docker compose up -d --build` and waits for the health checks,
6. then runs `install.sh`.

`install.sh`

1. asks for the administrator's username, email address, display name and password,
2. asks for the instance name, description, contact address, registration mode and, optionally, SMTP,
3. creates the administrator through the Vernissage API, confirms the account, grants the administrator role and **blocks the built-in `admin`/`admin` account**,
4. stores the image URL, Web Push (enabled), instance details and SMTP in the database,
5. writes
   - `nginx/<domain>.conf` – a ready-made host Nginx configuration for the domain,
   - `INSTALLATION.md` – an overview of the instance (without passwords).

All that remains afterwards:

```bash
sudo cp nginx/photos.example.org.conf /etc/nginx/sites-available/photos.example.org
sudo ln -s /etc/nginx/sites-available/photos.example.org /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d photos.example.org
```

## Several instances per server

Supported: simply clone into another directory and choose a different port when running `init.sh`. The Compose project name is derived from the directory name.

## Where the data lives

Vernissage ships as ready-built Docker images (Swift back end, Angular front end) – there are no application files to install into a web root. All persistent data lives in `data/`: real directories on the host, bind-mounted into the containers (no Docker volumes). They survive restarts, `docker compose down` and upgrades, and can be copied like any other directory (stop the stack before copying `data/postgres/`, or use the dump from `backup.sh`).

| Data | Location | Container |
|---|---|---|
| Uploaded photos (originals and resized variants) | `data/minio/` (MinIO bucket `vernissage`) | `minio` |
| Users, posts, EXIF data, alt texts, comments, followers, settings | `data/postgres/` | `postgres` |
| Queues and cache (e.g. ActivityPub delivery) | `data/redis/` | `redis` |

## Operation

```bash
./upgrade.sh                                   # update repository + images (takes a backup first)
./backup.sh                                    # backup to backups/<timestamp>/
docker compose ps                              # status
docker compose logs -f api jobs                # logs
docker compose down                            # stop (data stays in data/)
```

`upgrade.sh` pulls repository changes (`git pull --ff-only`, only if there are no local changes), runs `backup.sh`, pulls new images, rebuilds MinIO, recreates only the containers that changed, waits for all health checks and shows the old and new Vernissage version. Options: `--yes` (no questions, e.g. for cron), `--skip-backup`, `--no-git`.

PostgreSQL (`postgres:18`) and Redis are deliberately pinned to a major version. A PostgreSQL major upgrade requires a dump and restore and is not carried out by `upgrade.sh`.

Backup via cron (daily at 03:30):

```cron
30 3 * * * cd /path/to/instance && ./backup.sh >> backups/backup.log 2>&1
```

Backups (`backups/`) also contain `.env.local` – be sure to keep an additional copy **off** the server.

## Directory layout

| Path | Contents | In Git? |
|---|---|---|
| `docker-compose.yml` | stack definition | yes |
| `docker/minio/` | Dockerfile for MinIO | yes |
| `docker/proxy/templates/` | configuration of the internal proxy | yes |
| `init.sh`, `install.sh`, `upgrade.sh`, `backup.sh` | scripts | yes |
| `lib/common.sh` | shared shell functions | yes |
| `.env.local` | **secrets** | no |
| `data/` | PostgreSQL, Redis, MinIO | no |
| `backups/` | backups | no |
| `nginx/` | generated host Nginx configuration | no |
| `INSTALLATION.md` | generated instance overview | no |

## Starting afresh

```bash
docker compose down
sudo rm -rf data/ nginx/*.conf INSTALLATION.md .env.local .env
./init.sh
```

**Warning:** this deletes all data of the instance. The domain should stay the same in the long term – changing it breaks federated identities.

## Sources

- [Vernissage – Hosting in Docker containers](https://docs.joinvernissage.org/documentation/vernissageserver/dockercontainers)
- [VernissageInstaller (`vernissagectl`)](https://github.com/VernissageApp/VernissageInstaller)
- [VernissageProxy](https://github.com/VernissageApp/VernissageProxy)
