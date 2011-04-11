#!/bin/bash

./install.sh
source /usr/local/lib/redcloud/redcloud.sh

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


nginx_create_site "mysite.com"        "mysite.com www.mysite.com"               0 "" 1
nginx_ensite "mysite.com"
nginx_delete_site default

install_chili_project   "mysite.com" ""      1 0 ""     postgresql ""      1 "$USER" "$USER_PW" "$USER_FIRST_NAME" "$USER_LAST_NAME" "$USER_EMAIL"     "git" "my-git-proj1" 1 "My Git One"



