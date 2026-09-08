#!/bin/sh

mkdir -p /run/php

until mysqladmin ping -h "$MYSQL_HOSTNAME" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent 2>/dev/null; do
    echo "Waiting for $MYSQL_HOSTNAME database connection..."
    sleep 2
done

if [  -f "./wp-config.php" ];
then
    echo "Wp already configured"
else
    wp core download --allow-root
    sed -i "s/username_here/$MYSQL_USER/g" wp-config-sample.php
    sed -i "s/password_here/$MYSQL_PASSWORD/g" wp-config-sample.php
    sed -i "s/localhost/$MYSQL_HOSTNAME/g" wp-config-sample.php
    sed -i "s/database_name_here/$MYSQL_DATABASE/g" wp-config-sample.php
    cp wp-config-sample.php wp-config.php
fi

if ! wp core is-installed --allow-root; then
    wp core install --url=https://${DOMAIN_NAME} --title="Salma's Inception" --admin_user=${WP_ADMIN_USER} --admin_password=${WP_ADMIN_PASSWORD} --admin_email=${WP_ADMIN_EMAIL} --allow-root
fi

if ! wp user get ${WP_USER} --field=ID --allow-root >/dev/null 2>&1; then
    wp user create ${WP_USER} ${WP_USER_EMAIL} --user_pass=${WP_USER_PASSWORD} --allow-root
fi

exec php-fpm8.2 -F

