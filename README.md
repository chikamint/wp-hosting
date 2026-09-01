# wp-hosting-lab

Production-style WordPress hosting stack: Nginx/Apache front-end variants, MariaDB, backup and migration automation.

## Layout

- `docker-compose.yml` — Nginx + PHP-FPM + MariaDB
- `docker-compose.apache.yml` — Apache (mod_php) variant with .htaccess support, like shared hosting panels
- `nginx/default.conf` — rate limiting, security headers, static caching, xmlrpc blocked
- `scripts/backup.sh` — DB dump (`--single-transaction`) + files archive + retention
- `scripts/migrate.sh` — move the site to another server: dump, rsync, deploy, URL rewrite in `wp_options`
- `apache/htaccess-sample` — ready-to-use .htaccess

## Usage

```bash
cp .env.example .env   # set real passwords
docker compose up -d
# WordPress installer at http://server-ip:8080
```

Apache variant:

```bash
docker compose -f docker-compose.apache.yml up -d
# http://server-ip:8081
```

## Scripts

```bash
./scripts/backup.sh                                   # backup with 7-day retention
./scripts/migrate.sh user@host /opt/wp-hosting-lab new-domain.com
```

Backups land in `backups/<timestamp>/` as `db.sql.gz` + `files.tar.gz`.

Cron example:

```
0 3 * * * /opt/wp-hosting-lab/scripts/backup.sh >> /var/log/wp-backup.log 2>&1
```
