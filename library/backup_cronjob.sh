#!/bin/bash


function setup_backup_cronjob
{
	local curr_dir=$(pwd)
	cat /etc/crontab | grep -v "&&.*do_backup.sh" > /etc/crontab.tmp
	mkdir -p /backups
	echo "3  23	* * *   root	source \"$REDCLOUD_INSTALL_DIR/redcloud.sh\" ; backup_mysql /backups ; backup_sites /backups ; backup_projects /backups ; backup_mail_config /backups ; backup_hostname /backups" >>/etc/crontab.tmp
	mv /etc/crontab.tmp /etc/crontab
	restart cron
}


