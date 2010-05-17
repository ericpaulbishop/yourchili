#!/bin/bash


function setup_backup_cronjob
{
	DB_PASSWORD="$1"
	BACKUP_DIR="$2"

	local curr_dir=$(pwd)
	cat /etc/crontab | grep -v "tmp.back\.sh$" > /etc/crontab.tmp
	mkdir -p "$BACKUP_DIR"
	echo "3  23	* * *   root	echo 'source \"$REDCLOUD_INSTALL_DIR/redcloud.sh\" ; backup_mysql root \"$DB_PASSWORD\" \"$BACKUP_DIR\" ; backup_sites \"$BACKUP_DIR\" ; backup_projects \"$BACKUP_DIR\" ; backup_mail_config \"$BACKUP_DIR\" ; backup_hostname \"$BACKUP_DIR\"' > /tmp/back.sh ; chmod 700 /tmp/back.sh ; bash /tmp/back.sh ; rm -rf /tmp/back.sh" >>/etc/crontab.tmp
	mv /etc/crontab.tmp /etc/crontab
	restart cron
}


