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

# Archive the docroot volume via a throwaway read-only container
docker run --rm \
  -v wp-hosting-lab_wp_data:/var/www/html:ro \
  -v "$DEST":/backup \
  alpine tar czf /backup/files.tar.gz -C /var/www/html .

find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} +

echo "[OK] $(date '+%F %T') backup ready: $DEST ($(du -sh "$DEST" | cut -f1))"
