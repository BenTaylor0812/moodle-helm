#!/bin/bash
set -e

MOODLE_DIR=/bitnami/moodle
MOODLEDATA_DIR=/bitnami/moodledata

: "${MOODLE_WWWROOT:=http://localhost:30080}"

if ! mysql -h"$MOODLE_DATABASE_HOST" -u"$MOODLE_DATABASE_USER" -p"$MOODLE_DATABASE_PASSWORD" \
    -e "SELECT 1 FROM mdl_user LIMIT 1;" "$MOODLE_DATABASE_NAME" >/dev/null 2>&1; then
    echo "Running Moodle installer..."
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
    --fullname="Moodle" \
    --shortname="moodle" \
    --adminuser="admin" \
    --adminpass="admin123!" \
    --adminemail="admin@example.com"
else
    echo "Moodle already installed, skipping installer."
fi


# if [ ! -f "$MOODLE_DIR/config.php" ]; then
#   php $MOODLE_DIR/admin/cli/install.php \
#     --non-interactive \
#     --agree-license \
#     --wwwroot="$MOODLE_WWWROOT" \
#     --dataroot="$MOODLEDATA_DIR" \
#     --dbtype="mariadb" \
#     --dbhost="$MOODLE_DATABASE_HOST" \
#     --dbname="$MOODLE_DATABASE_NAME" \
#     --dbuser="$MOODLE_DATABASE_USER" \
#     --dbpass="$MOODLE_DATABASE_PASSWORD" \
#     --fullname="Moodle" \
#     --shortname="moodle" \
#     --adminuser="admin" \
#     --adminpass="admin123!" \
#     --adminemail="admin@example.com"
# fi

exec "$@"