# Operations runbook

Backup, restore, migration and first-response incident procedures for the WordPress stack.

## Backup

- Manual: `./scripts/backup.sh` from the repo root
- Scheduled: cron daily at 03:00 — `0 3 * * * /opt/wp-hosting-lab/scripts/backup.sh >> /var/log/wp-backup.log 2>&1`
- Output: `backups/YYYY-MM-DD_hh-mm-ss/` containing `db.sql.gz` and `files.tar.gz`
- Retention: 7 days (see `RETENTION_DAYS` in the script)

**Verify backups weekly** — a backup you never opened is a rumor:

```bash
zcat backups/*/db.sql.gz | head -20     # expect CREATE TABLE statements
tar tzf backups/*/files.tar.gz | head    # expect wp-content/, wp-config.php, ...
```

## Restore on a fresh server

1. Deploy the repo: `git clone <repo> && cd wp-hosting-lab && cp .env.example .env` (set passwords), `docker compose up -d --wait`
2. Copy the backup directory to the server
3. Restore files into the docroot volume:
   ```bash
   docker run --rm -v wp-hosting-lab_wp_data:/var/www/html -v "$PWD/<backup-dir>":/backup:ro \
     alpine tar xzf /backup/files.tar.gz -C /var/www/html
   ```
4. Import the DB:
   ```bash
   gunzip -c <backup-dir>/db.sql.gz | docker compose exec -T db mariadb -uroot -p"$(docker compose exec -T db printenv MARIADB_ROOT_PASSWORD)" wordpress
   ```
5. If the domain changed, update `siteurl`/`home` in `wp_options`
6. Verify: homepage returns 200, `/wp-admin` login works, permalinks OK

## Migration to a new server

```bash
./scripts/migrate.sh user@new-server /opt/wp-hosting-lab new-domain.example
```

Checklist:

- [ ] Target server reachable over SSH (key auth), docker + compose plugin installed
- [ ] `.env` created on the target (its own passwords)
- [ ] DNS TTL on the record lowered in advance (300s) so the cutover is fast
- [ ] Site verified on the new IP *before* switching DNS: add `NEW_IP new-domain.example` to local `/etc/hosts`, open the site
- [ ] After DNS switch: watch `docker compose logs -f nginx` for a few minutes
- [ ] Old server kept intact for 24h as a rollback option

## Incident first-response matrix

| Symptom | First check | Typical cause | Fix |
|---|---|---|---|
| White screen / HTTP 500 | `wp-content/debug.log` (enable `WP_DEBUG_LOG` first) | Plugin fatal error | Rename the plugin dir in `wp-content/plugins/`, restore after triage |
| Styles/images broken, admin errors | `nginx` `error.log` — `Permission denied` on `wp-content` | Broken ownership/perms | `chown -R www-data:www-data`, `chmod 755 wp-content` |
| Homepage OK, inner pages 404 | `access.log` shows 404, PHP never called | Missing rewrite fallback | Restore `try_files ... /index.php?$args` (nginx) or `.htaccess` (Apache) |
| "Error establishing a database connection" | `docker compose ps`, `logs db` | DB container down / bad credentials in `wp-config.php` | Start db, reconcile `WORDPRESS_DB_*` vs actual |
| Site suddenly slow | `docker stats`, `top` on host | OOM, slow queries, no caching | Check `dmesg` for OOM kills, add Redis object cache, review plugins |
| Disk full alerts | `df -h`, `du -sh /var/lib/docker` | Old images, logs, backups | `docker system prune`, logrotate, check `backups/` retention |

## After every incident

Add a short note: what broke, root cause, what fixed it, how to detect earlier. That log is interview material.
