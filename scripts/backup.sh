#!/usr/bin/env bash
# WordPress stack backup: DB dump + files archive + retention cleanup.
# Cron: 0 3 * * * /opt/wp-hosting-lab/scripts/backup.sh >> /var/log/wp-backup.log 2>&1

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups"
RETENTION_DAYS=7
COMPOSE="docker compose"

cd "$PROJECT_DIR"
set -a; . ./.env; set +a

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
DEST="$BACKUP_DIR/$TIMESTAMP"
mkdir -p "$DEST"

# --single-transaction: consistent InnoDB dump without locking tables
$COMPOSE exec -T db mariadb-dump \
  -u"root" -p"$($COMPOSE exec -T db printenv MARIADB_ROOT_PASSWORD)" \
  --single-transaction \
  "$DB_NAME" | gzip > "$DEST/db.sql.gz"

# Resolve the docroot volume from the running container — folder renames must not break backups
WP_VOLUME="$(docker inspect "$($COMPOSE ps -q wordpress)" --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Name}}{{end}}{{end}}')"
[ -n "$WP_VOLUME" ] || { echo "[FAIL] wp_data volume not found — is the stack up?" >&2; exit 1; }

docker run --rm \
  -v "$WP_VOLUME":/var/www/html:ro \
  -v "$DEST":/backup \
  alpine tar czf /backup/files.tar.gz -C /var/www/html .

# An empty archive is a failed backup — fail loudly, not silently
SIZE=$(stat -c%s "$DEST/files.tar.gz")
[ "$SIZE" -lt 10000 ] && { echo "[FAIL] files.tar.gz is suspiciously small ($SIZE bytes) — check the volume" >&2; exit 1; }

find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} +

echo "[OK] $(date '+%F %T') backup ready: $DEST ($(du -sh "$DEST" | cut -f1))"
