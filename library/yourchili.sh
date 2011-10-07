#!/bin/bash

##Uncomment below when installed, to indicate where 
##library is installed, so we can source sub-modules properly 
#YOURCHILI_INSTALL_DIR=/usr/local/lib/yourchili


if [ -z "$YOURCHILI_INSTALL_DIR" ] ; then
	YOURCHILI_INSTALL_DIR="./library" 
fi

export YOURCHILI_INSTALL_DIR

source "$YOURCHILI_INSTALL_DIR/constants.sh"
source "$YOURCHILI_INSTALL_DIR/random.sh"
source "$YOURCHILI_INSTALL_DIR/hostname.sh"
source "$YOURCHILI_INSTALL_DIR/user.sh"
source "$YOURCHILI_INSTALL_DIR/upgrade.sh"
source "$YOURCHILI_INSTALL_DIR/security.sh"
source "$YOURCHILI_INSTALL_DIR/mysql.sh"
source "$YOURCHILI_INSTALL_DIR/postgresql.sh"
source "$YOURCHILI_INSTALL_DIR/nginx_stack.sh"
source "$YOURCHILI_INSTALL_DIR/git.sh"
source "$YOURCHILI_INSTALL_DIR/redmine_chiliproject.sh"
source "$YOURCHILI_INSTALL_DIR/site_backup_and_restore.sh"
source "$YOURCHILI_INSTALL_DIR/mail.sh"
source "$YOURCHILI_INSTALL_DIR/backup_cronjob.sh"
source "$YOURCHILI_INSTALL_DIR/wordpress.sh"
source "$YOURCHILI_INSTALL_DIR/escape_path.sh"


