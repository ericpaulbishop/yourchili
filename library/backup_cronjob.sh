#!/bin/bash


function setup_backup_cronjob
{
	local curr_dir=$(pwd)
	cat /etc/crontab | grep -v "&&.*do_backup.sh" > /etc/crontab.tmp
	echo '3  23	* * *   root	cd '$curr_dir' && ./do_backup.sh' >>/etc/crontab.tmp
	mv /etc/crontab.tmp /etc/crontab
	restart cron
}


