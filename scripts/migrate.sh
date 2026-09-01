#!/usr/bin/env bash
# Migrate the WordPress site to another server.
# Usage: ./scripts/migrate.sh user@host /opt/wp-hosting-lab new-domain.example

set -euo pipefail

TARGET="${1:?target user@host required}"
TARGET_DIR="${2:?target directory required}"
NEW_DOMAIN="${3:?new domain required}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a; . ./.env; set +a

echo ">>> Taking fresh backup..."
./scripts/backup.sh
LATEST="$(ls -1dt backups/*/ | head -n1)"

echo ">>> Syncing to $TARGET:$TARGET_DIR ..."
ssh "$TARGET" "mkdir -p '$TARGET_DIR'"
rsync -az --delete \
  --exclude '.git' --exclude 'backups' \
  ./ "$TARGET:$TARGET_DIR/"
rsync -az "$LATEST" "$TARGET:$TARGET_DIR/backups/"

echo ">>> Deploying on $TARGET ..."
ssh "$TARGET" "bash -s" -- "$TARGET_DIR" "$LATEST" "$NEW_DOMAIN" <<'REMOTE'
set -euo pipefail
TARGET_DIR="$1"; BACKUP="$2"; NEW_DOMAIN="$3"
cd "$TARGET_DIR"

[ -f .env ] || { echo "Missing .env on target (copy from .env.example)"; exit 1; }
set -a; . ./.env; set +a

docker compose up -d --wait

# Resolve the docroot volume from the running container
WP_VOLUME="$(docker inspect "$(docker compose ps -q wordpress)" --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Name}}{{end}}{{end}}')"
[ -n "$WP_VOLUME" ] || { echo "[FAIL] wp_data volume not found"; exit 1; }

docker run --rm \
  -v "$WP_VOLUME":/var/www/html \
  -v "$TARGET_DIR/$BACKUP":/backup:ro \
  alpine sh -c 'rm -rf /var/www/html/* && tar xzf /backup/files.tar.gz -C /var/www/html'

gunzip -c "$BACKUP/db.sql.gz" | docker compose exec -T db mariadb -uroot -p"$(docker compose exec -T db printenv MARIADB_ROOT_PASSWORD)" "$DB_NAME"

# Without this WP keeps redirecting to the old domain
docker compose exec -T db mariadb -uroot -p"$(docker compose exec -T db printenv MARIADB_ROOT_PASSWORD)" "$DB_NAME" \
  -e "UPDATE wp_options SET option_value='http://$NEW_DOMAIN' WHERE option_name IN ('siteurl','home');"

echo "[OK] Deployed: http://$NEW_DOMAIN"
REMOTE

echo "[OK] Migration done. Verify the site and update DNS."
