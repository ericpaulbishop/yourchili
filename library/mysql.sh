#!/bin/bash

###########################################################
# mysql-server
###########################################################

function mysql_install {
	# $1 - the mysql root password

	if [ ! -n "$1" ]; then
		echo "mysql_install() requires the root pass as its first argument"
		return 1;
	fi

	echo "mysql-server-5.1 mysql-server/root_password password $1" | debconf-set-selections
	echo "mysql-server-5.1 mysql-server/root_password_again password $1" | debconf-set-selections
	aptitude install -y mysql-server mysql-client libmysqld-dev libmysqlclient-dev

	echo "Sleeping while MySQL starts up for the first time..."
	sleep 5
}

function mysql_tune {
	# Tunes MySQL's memory usage to utilize the percentage of memory you specify, defaulting to 40%

	# $1 - the percent of system memory to allocate towards MySQL

	if [ ! -n "$1" ];
		then PERCENT=30
		else PERCENT="$1"
	fi

	sed -i -e 's/^#skip-innodb/skip-innodb/' /etc/mysql/my.cnf # disable innodb - saves about 100M

	MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo) # how much memory in MB this system has
	MYMEM=$((MEM*PERCENT/100)) # how much memory we'd like to tune mysql with
	MYMEMCHUNKS=$((MYMEM/4)) # how many 4MB chunks we have to play with

	# mysql config options we want to set to the percentages in the second list, respectively
	OPTLIST=(key_buffer sort_buffer_size read_buffer_size read_rnd_buffer_size myisam_sort_buffer_size query_cache_size)
	DISTLIST=(75 1 1 1 5 15)

	for opt in ${OPTLIST[@]}; do
		sed -i -e "/\[mysqld\]/,/\[.*\]/s/^$opt/#$opt/" /etc/mysql/my.cnf
	done

	for i in ${!OPTLIST[*]}; do
		val=$(echo | awk "{print int((${DISTLIST[$i]} * $MYMEMCHUNKS/100))*4}")
		if [ $val -lt 4 ]
			then val=4
		fi
		config="${config}\n${OPTLIST[$i]} = ${val}M"
	done

	sed -i -e "s/\(\[mysqld\]\)/\1\n$config\n/" /etc/mysql/my.cnf

	/etc/init.d/mysql restart
}

function mysql_create_database {
	# $1 - the mysql root password
	# $2 - the db name to create

	if [ ! -n "$1" ]; then
		echo "mysql_create_database() requires the root pass as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "mysql_create_database() requires the name of the database as the second argument"
		return 1;
	fi

	echo "CREATE DATABASE $2;" | mysql -u root -p$1
}

function mysql_create_user {
	# $1 - the mysql root password
	# $2 - the user to create
	# $3 - their password
	

	if [ ! -n "$1" ]; then
		echo "mysql_create_user() requires the root pass as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "mysql_create_user() requires username as the second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "mysql_create_user() requires a password as the third argument"
		return 1;
	fi

	echo "CREATE USER '$2'@'localhost' IDENTIFIED BY '$3';" | mysql -u root -p$1
}

function mysql_grant_user {
	# $1 - the mysql root password
	# $2 - the user to bestow privileges 
	# $3 - the database

	if [ ! -n "$1" ]; then
		echo "mysql_grant_user() requires the root pass as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "mysql_grant_user() requires username as the second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "mysql_grant_user() requires a database as the third argument"
		return 1;
	fi

	echo "GRANT ALL PRIVILEGES ON $3.* TO '$2'@'localhost';" | mysql -u root -p$1
	echo "FLUSH PRIVILEGES;" | mysql -u root -p$1

}

function backup_mysql
{
	if [ ! -n "$1" ]; then
		echo "backup_mysql() requires the database user as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "backup_mysql) requires the database password as its second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "backup_mysql() requires the output file path as its third argument"
		return 1;
	fi
	local USER="$1"
	local PASS="$2"
	local BACKUP_DIR="$3"
	local DBNAMES="$4"


	fname=""
	if [ -n "$DBNAMES" ] ; then
		fname=$(echo "$DBNAMES" | sed 's/ /_/g')
		mysqldump --single-transaction --add-drop-table --add-drop-database -h localhost --user="$USER" --password="$PASS" --databases $DBNAMES > "/tmp/$fname-db.sql"
		

	else
		fname="all"
		mysqldump --single-transaction --add-drop-table --add-drop-database -h localhost --user="$USER" --password="$PASS" --all-databases  > "/tmp/$fname-db.sql"
	fi

	mkdir -p "$BACKUP_DIR"

	local curdir=$(pwd)
	cd /tmp
	rm -rf "$BACKUP_DIR/$fname-db.tar.bz2"
	tar cjf	"$BACKUP_DIR/$fname-db.tar.bz2" "$fname-db.sql"
	rm -rf "$fname-db.sql"
	cd "$curdir"

}


function restore_mysql
{
	if [ ! -n "$1" ]; then
		echo "restore_mysql() requires the database user as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "restore_mysql) requires the database password as its second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "restore_mysql() requires the backup directory as its third argument"
		return 1;
	fi
	
	local USER="$1"
	local DB_PASSWORD="$2"
	local BACKUP_DIR="$3"



	rm -rf "/tmp/tmp.db" "/tmp/tmp.db.all.sql"
	mkdir "/tmp/tmp.db"
	
	db_zips=$(ls "$BACKUP_DIR/"*-db.tar.bz2)
	for dbz in $db_zips ; do
		tar -C "/tmp/tmp.db" -xjf "$dbz"
		cat /tmp/tmp.db/* >> "/tmp/tmp.db.all.sql"
		rm -rf /tmp/tmp.db/*
	done

	#ensure that current user (usually root) and debian-sys-maint have same password as before, and that they still have all permissions
	old_debian_pw=$(echo $(cat /etc/mysql/debian.cnf | grep password | sed 's/^.*=[\t ]*//g') | awk ' { print $1 } ')
	echo "USE mysql ;"                                                                            >> "/tmp/tmp.db.all.sql"
	echo "GRANT ALL ON *.* TO 'debian-sys-maint'@'localhost' ;"                                   >> "/tmp/tmp.db.all.sql"
	echo "GRANT ALL ON *.* TO '$USER'@'localhost' ;"                                              >> "/tmp/tmp.db.all.sql"
	echo "UPDATE user SET password=PASSWORD(\"$old_debian_pw\") WHERE User='debian-sys-maint' ;"  >> "/tmp/tmp.db.all.sql"
	echo "UPDATE user SET password=PASSWORD(\"$DB_PASSWORD\") WHERE User='$USER' ;"               >> "/tmp/tmp.db.all.sql"
	echo "FLUSH PRIVILEGES ;"                                                                     >> "/tmp/tmp.db.all.sql"


	mysql --user="$USER" --password="$DB_PASSWORD" < "/tmp/tmp.db.all.sql"
	rm -rf "/tmp/tmp.db" "/tmp/tmp.db.all.sql"


	touch /tmp/restart-mysql
	
}


