#!/bin/bash

##Uncomment below when installed, to indicate where 
##library is installed, so we can source sub-modules properly 
#REDCLOUD_INSTALL_DIR=/usr/local/lib/redcloud


if [ -z "$REDCLOUD_INSTALL_DIR" ] ; then
	REDCLOUD_INSTALL_DIR="./library" 
fi

export REDCLOUD_INSTALL_DIR

source "$REDCLOUD_INSTALL_DIR/constants.sh"
source "$REDCLOUD_INSTALL_DIR/random.sh"
source "$REDCLOUD_INSTALL_DIR/hostname.sh"
source "$REDCLOUD_INSTALL_DIR/user.sh"
source "$REDCLOUD_INSTALL_DIR/upgrade.sh"
source "$REDCLOUD_INSTALL_DIR/security.sh"
source "$REDCLOUD_INSTALL_DIR/mysql.sh"
source "$REDCLOUD_INSTALL_DIR/postgresql.sh"
source "$REDCLOUD_INSTALL_DIR/nginx_stack.sh"
source "$REDCLOUD_INSTALL_DIR/subversion.sh"
source "$REDCLOUD_INSTALL_DIR/git.sh"
source "$REDCLOUD_INSTALL_DIR/chiliproject.sh"
source "$REDCLOUD_INSTALL_DIR/site_backup_and_restore.sh"
source "$REDCLOUD_INSTALL_DIR/mail.sh"
source "$REDCLOUD_INSTALL_DIR/backup_cronjob.sh"
source "$REDCLOUD_INSTALL_DIR/wordpress.sh"


