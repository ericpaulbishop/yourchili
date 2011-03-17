#!/bin/bash


function better_wordpress_install
{
	# installs the latest wordpress tarball from wordpress.org

	# $1 - required - The existing virtualhost to install into
	# $2 - required - The wordpress username, which will also be database name
	# $3 - required - The database password

	if [ ! -n "$3" ]; then
		echo "better_wordpress_install() requires the root database password as its first argument"
		return 1;
	fi

	if [ ! -n "$1" ]; then
		echo "better_wordpress_install() requires the vitualhost as its second argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "better_wordpress_install() requires the Wordpress username as its second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "better_wordpress_install() requires the Wordpress password as its third argument"
		return 1;
	fi




	DB_PASSWORD="$1"
	VPATH=$(cat "/etc/nginx/sites-available/$2" | grep -P "^[\t ]*root"  | awk ' { print $2 } ' | sed 's/;.*$//g')
	WP_USER="$3"
	WP_PW="$4"

	if [ ! -n "$VPATH" ]; then
		echo "Could not determine DocumentRoot for $1"
		return 1;
	fi

	if [ ! -e /usr/bin/wget ]; then
		aptitude -y install wget unzip
	fi

	# download, extract, chown, and get our config file started
	curdir=$(pwd)
	cd /tmp
	wget "http://wordpress.org/latest.tar.gz"
	tar xfz latest.tar.gz
	rm -rf latest.tar.gz
	rm -rf "$VPATH"
	mv "wordpress" "$VPATH"
	chown -R www-data "$VPATH"
	

	cd "$VPATH"	
	cp wp-config-sample.php wp-config.php
	chown www-data wp-config.php
	chmod 640 wp-config.php

	# database configuration
	db="${WP_USER}_wp"
	mysql_create_database "$DB_PASSWORD" "$db"
	mysql_create_user "$DB_PASSWORD" "$db" "$WP_PASS"
	mysql_grant_user "$DB_PASSWORD" "$db" "$db"

	# configuration file updates
	for i in {1..4}
		do sed -i "0,/put your unique phrase here/s/put your unique phrase here/$(randomString 50)/" wp-config.php
	done

	sed -i "s/putyourdbnamehere/$db/" wp-config.php
	sed -i "s/usernamehere/$db/" wp-config.php
	sed -i "s/yourpasswordhere/$db/" wp-config.php



	chown -R www-data *
	chgrp -R www-data *

	
	cd "$curdir"

}


