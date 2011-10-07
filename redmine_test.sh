#!/bin/bash

./install.sh
source /usr/local/lib/yourchili/yourchili.sh

HOSTNAME="mysite.com"
DB_PASSWORD="password"
NGINX_USER="www-data"
NGINX_GROUP="www-data"


USER="librarian"
USER_PW="ookook"
USER_FIRST_NAME="The"
USER_LAST_NAME="Librarian"
USER_EMAIL="librarian@uu.edu.am"

BACKUP_DIR="/backups" #directory where we store backups

git pull >/dev/null 2>&1

nginx_create_site "mysite.com"        "mysite.com www.mysite.com"               0 "" 1
nginx_ensite "mysite.com"
nginx_delete_site default

install_redmine   "mysite.com" ""      1 0 ""     postgresql ""      1 "$USER" "$USER_PW" "$USER_FIRST_NAME" "$USER_LAST_NAME" "$USER_EMAIL"     "my-git-proj1" 1 "My Git One"

cd /root
ln -s /srv/www/my*/redmine
ln -s /srv/www/my*/redmine/v*/plug*/*git*



