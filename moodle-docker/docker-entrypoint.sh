#!/bin/bash
set -e

MOODLE_DIR=/var/www/moodle
MOODLEDATA_DIR=/var/www/moodledata

echo "Waiting for MariaDB at $MOODLE_DATABASE_HOST:$MOODLE_DATABASE_PORT_NUMBER..."
until mysqladmin ping -h"$MOODLE_DATABASE_HOST" --protocol=tcp --skip-ssl --silent; do
  sleep 2
done

if [ "$SKIP_INSTALL" = "true" ]; then
    echo "Skipping Moodle installation (debug mode)."
    exec "$@"
fi

echo "Checking if Moodle is already installed..."
if ! mysql -h"$MOODLE_DATABASE_HOST" \
    -u"$MOODLE_DATABASE_USER" \
    -p"$MOODLE_DATABASE_PASSWORD" \
    --skip-ssl \
    -e "SELECT 1 FROM mdl_user LIMIT 1;" "$MOODLE_DATABASE_NAME" >/dev/null 2>&1; then

    echo "No Moodle tables found — running installer..."
    php $MOODLE_DIR/admin/cli/install.php \
      --non-interactive \
      --agree-license \
      --wwwroot="$MOODLE_WWWROOT" \
      --dataroot="$MOODLEDATA_DIR" \
      --dbtype="mariadb" \
      --dbhost="$MOODLE_DATABASE_HOST" \
      --dbname="$MOODLE_DATABASE_NAME" \
      --dbuser="$MOODLE_DATABASE_USER" \
      --dbpass="$MOODLE_DATABASE_PASSWORD" \
      --dbport="$MOODLE_DATABASE_PORT_NUMBER" \
      --dbsocket="" \
      --fullname="Moodle" \
      --shortname="moodle" \
      --adminuser="admin" \
      --adminpass="admin123!" \
      --adminemail="admin@example.com"

    echo "Fixing permissions..."
    chown -R www-data:www-data /var/www/moodle
    chmod -R u+rwX,go+rX /var/www/moodle

else
    echo "Moodle already installed — skipping installer."
fi




exec "$@"