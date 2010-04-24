#!/bin/bash

. ./erics-cloud-lib.sh


HOSTNAME="cori-celesti.org"
DB_PASSWORD="password"
NGINX_USER="www-data"
NGINX_GROUP="www-data"
PROJ_NAME="miner"
PROJ_PW="password"


upgrade_system
better_bash_prompt 1
set_hostname "$HOSTNAME"


mysql_install "$DB_PASSWORD"
mysql_tune

nginx_php-fpm
nginx_ruby
nginx_install

setup_svn_with_redmine "$PROJ_NAME" "1" "admin" "$PROJ_PW" "$DB_PASSWORD"

nginx_delete_site localhost
nginx_create_site "www.salamander-linux.com" "www.salamander-linux.com salamander-linux.com www.salamanderlinux.com salamanderlinux.com" 0 "" "1"
nginx_create_site "www.thisisnotmyfacebook.com" "www.thisisnotmyfacebook.com thisisnotmyfacebook.com" 0 "" "1"
nginx_ensite "www.salamander-linux.com"
nginx_ensite "www.thisisnotmyfacebook.com"

set_open_ports 22 80 443 25 110 587

add_user "eric" "password" "1"

#setup_trac_and_svn_with_apache "myproj" "1" "admin" "password" "1" "0" "0" "8080"

