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



#updates packages to latest versions
upgrade_system

#sets detailed (2-line) bash prompt that includes date/time
#otherwise we just use short 1-line bash prompt (but still colored)
better_bash_prompt 1

#set hostname and allowed ports
#port 22=ssh; 80,443=http,https; 25,110,587=email; 9418=git
set_hostname "$HOSTNAME"
set_open_ports 22 80 443 25 110 587 9418 


# Add an admin user
# Last arg indicates that this is an admin
add_user "$USER" "$USER_PW" "1"

#install mysql, let it use up to 30% of memory
mysql_install "$DB_PASSWORD"
postgresql_install 

#install nginx, along with both passenger(ruby), php and perl
nginx_install "$NGINX_USER" "$NGINX_GROUP" "1" "1" "1"




