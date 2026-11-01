FROM php:8.2-apache

# Install dependencies.
#
# Moodle 5.1 declares these extensions as REQUIRED in public/admin/environment.xml:
#   ctype curl dom exif fileinfo filter gd hash iconv intl json mbstring
#   openssl pcre simplexml soap sodium spl tokenizer xml xmlreader zip zlib
#
# All but gd, intl, zip, exif and soap are compiled into php:*-apache already.
# mysqli is for MariaDB; opcache is a performance recommendation.
# unzip is kept for baking plugins into the image.
RUN apt-get update && apt-get install -y --no-install-recommends \
    unzip libpng-dev libjpeg-dev libfreetype6-dev libxml2-dev libzip-dev libicu-dev libonig-dev mariadb-client \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd intl zip exif soap mysqli opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN a2enmod rewrite

# moodledata is a mount point for the PVC; Moodle's code lives in the image.
RUN mkdir -p /var/www/moodle /var/www/moodledata

# Moodle core, unpacked into its final location.
#
# This is an immutable image: the code ships here rather than being copied onto
# a volume at startup. Upgrading Moodle means building a new image, which also
# means the running code is always exactly what the image contains, with no
# volume accumulating state that drifts between environments.
ARG MOODLE_VERSION=5.1.3
COPY moodle-versions/moodle-${MOODLE_VERSION}.tgz /tmp/moodle.tgz
RUN tar -xz -f /tmp/moodle.tgz -C /var/www/moodle --strip-components=1 \
    && rm /tmp/moodle.tgz

# Moodle 5 serves from public/, so point Apache's DocumentRoot at it. Done at
# build time now that the code is fixed in the image.
RUN rm -rf /var/www/html \
    && ln -s /var/www/moodle/public /var/www/html

# Plugins are baked in here, before the chown below. One block per plugin, e.g.
#
#   COPY plugins/oauth/auth_oidc.zip /tmp/
#   RUN unzip -q /tmp/auth_oidc.zip -d /var/www/moodle/public/auth/ \
#    && rm /tmp/auth_oidc.zip \
#    && test -f /var/www/moodle/public/auth/oidc/version.php
#
# That final `test` fails the build if the archive unpacked to the wrong folder
# name, which is the commonest plugin mistake and otherwise only shows up as a
# confusing Moodle error later.

RUN chown -R www-data:www-data /var/www/moodle /var/www/moodledata && \
    chmod -R u+rwX,go+rX /var/www/moodle /var/www/moodledata

COPY moodle.ini /usr/local/etc/php/conf.d/moodle.ini

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
