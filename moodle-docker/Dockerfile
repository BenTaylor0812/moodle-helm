FROM php:8.2-apache

RUN apt-get update && apt-get install -y \
    git unzip libpng-dev libjpeg-dev libfreetype6-dev libxml2-dev libzip-dev libicu-dev libonig-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd intl zip mysqli opcache

RUN a2enmod rewrite

# Directories
RUN mkdir -p /bitnami/moodle /bitnami/moodledata

# Download Moodle
ARG MOODLE_VERSION=4.3
RUN curl -L https://download.moodle.org/download.php/direct/stable501/moodle-latest-501.tgz \
    | tar -xz -C /bitnami/moodle --strip-components=1

# Point Apache to public/, not the whole codebase
RUN rm -rf /var/www/html && \
    ln -s /bitnami/moodle/public /var/www/html

# Permissions for Apache user (php:8.2-apache uses www-data)
RUN chown -R www-data:www-data /bitnami/moodle /bitnami/moodledata && \
    chmod -R u+rwX,go+rX /bitnami/moodle

    chown -R www-data:www-data /bitnami/moodle
chown -R www-data:www-data /bitnami/moodledata
chmod -R u+rwX,go+rX /bitnami/moodle
chmod -R u+rwX,go+rX /bitnami/moodledata


COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

RUN echo "max_input_vars = 5000" > /usr/local/etc/php/conf.d/moodle.ini

EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]