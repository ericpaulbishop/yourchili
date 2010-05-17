#!/bin/bash


function setup_backup_cronjob
{
	DB_PASSWORD="$1"
	BACKUP_DIR="$2"

	local curr_dir=$(pwd)
	cat /etc/crontab | grep -v "&&.*do_backup.sh" > /etc/crontab.tmp
	mkdir -p "$BACKUP_DIR"
	echo "3  23	* * *   root	source \"$REDCLOUD_INSTALL_DIR/redcloud.sh\" ; backup_mysql root \"$DB_PASSWORD\" \"$BACKUP_DIR\" ; backup_sites \"$BACKUP_DIR\" ; backup_projects \"$BACKUP_DIR\" ; backup_mail_config \"$BACKUP_DIR\" ; backup_hostname \"$BACKUP_DIR\"" >>/etc/crontab.tmp
	mv /etc/crontab.tmp /etc/crontab
	restart cron
}


