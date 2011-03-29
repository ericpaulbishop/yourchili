#!/bin/bash


function better_wordpress_install
{
	# installs the latest wordpress tarball from wordpress.org
	# root db pass = $1
	# VPATH = $2
	# Wordpress User = $3
	# Wordpress Pass = $4


	DB_PASSWORD="$1"
	VPATH=$(cat "/etc/nginx/sites-available/$2" | grep -P "^[\t ]*root"  | awk ' { print $2 } ' | sed 's/;.*$//g')
	WP_USER="$3"
	WP_PASS="$4"

	echo "WP_PASS = $4";
	


	if [ ! -n "$VPATH" ]; then
		echo "Could not determine DocumentRoot for $1"
		return 1;
	fi

	if [ ! -e /usr/bin/wget ]; then
		aptitude -y install wget unzip
	fi

	# download, extract, chown, and get our config file started
	local curdir=$(pwd)
	local wp_ver_file="wordpress-3.1.tar.gz"
	cd /tmp
	wget "http://wordpress.org/$wp_ver_file"
	tar xfz $wp_ver_file
	rm -rf $wp_ver_file
	rm -rf "$VPATH"
	mv "wordpress" "$VPATH"
	chown -R www-data "$VPATH"
	

	cd "$VPATH"	
	cp wp-config-sample.php wp-config.php
	chown www-data wp-config.php

	# database configuration
	db="${WP_USER}_wp"
	mysql_create_database "$DB_PASSWORD" "$db"
	mysql_create_user "$DB_PASSWORD" "$db" "$WP_PASS"
	mysql_grant_user "$DB_PASSWORD" "$db" "$db"

	# configuration file updates
	for i in {1..8}
		do sed -i "0,/put your unique phrase here/s/put your unique phrase here/$(randomString 50)/" wp-config.php
	done

	
	sed -i "s/database_name_here/$db/" wp-config.php
	sed -i "s/username_here/$db/" wp-config.php
	sed -i "s/password_here/$WP_PASS/" wp-config.php




	chmod 640 wp-config.php
	chown -R www-data *
	chgrp -R www-data *

	/etc/init.d/nginx restart
	/etc/init.d/php5-fpm restart
	
	cd "$curdir"

}


