#!/bin/bash
# Usage: stage files under /tmp/cw_deploy (same relative paths) + files.txt, optional migrations.txt and admin_dist/.
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
if [ -f "$SRC/migrations.txt" ]; then
  while IFS= read -r mig; do
    [ -z "$mig" ] && continue
    php artisan migrate --path="$mig" --force
  done < "$SRC/migrations.txt"
fi
if [ -d "$SRC/admin_dist" ]; then
  ADMIN="$DST/public/admin"
  mkdir -p "$ADMIN/assets"
  cp -r "$SRC/admin_dist/assets/." "$ADMIN/assets/"
  cp "$SRC/admin_dist/index.html" "$ADMIN/index.html"
  chown -R gstaxi_1z:www-data "$ADMIN"
  find "$ADMIN" -type f -exec chmod 644 {} +
  echo "admin deployed: $(grep -o 'assets/index-[^"]*\.js' "$ADMIN/index.html")"
fi
php artisan cache:clear
# opcache قد يتلف عند استبدال ملفات PHP أثناء التشغيل (SIGSEGV جماعي → 502)
systemctl reload php8.3-fpm && echo "php-fpm reloaded"
