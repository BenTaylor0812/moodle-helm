FROM php:8.2-apache

# Install dependencies.
#
# Moodle 5.1 declares these extensions as REQUIRED in public/admin/environment.xml:
#   ctype curl dom exif fileinfo filter gd hash iconv intl json mbstring
#   openssl pcre simplexml soap sodium spl tokenizer xml xmlreader zip zlib
#
# All but gd, intl, zip, exif and soap are compiled into php:*-apache already.
# mysqli is for MariaDB; opcache is a performance recommendation.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip rsync libpng-dev libjpeg-dev libfreetype6-dev libxml2-dev libzip-dev libicu-dev libonig-dev mariadb-client \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd intl zip exif soap mysqli opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN a2enmod rewrite

# Create directories
RUN mkdir -p /var/www/moodle /var/www/moodledata


# Copy in Moodle

ARG MOODLE_VERSION=5.1.3
COPY moodle-versions/moodle-${MOODLE_VERSION}.tgz /tmp/moodle.tgz
RUN mkdir -p /usr/src/moodle
RUN tar -xz -f /tmp/moodle.tgz -C /usr/src/moodle --strip-components=1 \
    && rm /tmp/moodle.tgz

# # Apache should serve the public directory
# RUN rm -rf /var/www/html && \
#     ln -s /var/www/moodle/public /var/www/html

# Permissions
RUN chown -R www-data:www-data /var/www/moodle /var/www/moodledata && \
    chmod -R u+rwX,go+rX /var/www/moodle /var/www/moodledata

COPY moodle.ini /usr/local/etc/php/conf.d/moodle.ini

# Copy entrypoint
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]