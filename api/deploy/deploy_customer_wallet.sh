#!/bin/bash
set -e
SRC=/tmp/cw_deploy
DST=/var/www/gstaxi/api
cd "$SRC"
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  mkdir -p "$(dirname "$DST/$rel")"
  cp "$SRC/$rel" "$DST/$rel"
  php -l "$DST/$rel" >/dev/null
  echo "deployed $rel"
done < "$SRC/files.txt"
chown -R --reference="$DST/app/Models/User.php" "$DST/app" "$DST/routes" "$DST/database/migrations" 2>/dev/null || true
cd "$DST"
php artisan migrate --path=database/migrations/2026_09_29_120000_create_customer_wallets_tables.php --force
php artisan cache:clear
php artisan route:list 2>/dev/null | grep -Ei "wallet|/pay" || true
