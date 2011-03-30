#!/bin/bash


function better_wordpress_install
{
	# installs the latest wordpress tarball from wordpress.org
	#
	# root db pass = $1
	# nginx site id = $2
	# Wordpress User = $3
	# Wordpress Pass = $4
	# Wordpress Blog Title = $5
	# Wordpress Admin Email = $6


	DB_PASSWORD="$1"
	SITE_ID="$2"
	WP_USER="$3"
	WP_PASS="$4"
	WP_TITLE="$5"
	WP_EMAIL="$6"

	VPATH=$(cat "/etc/nginx/sites-available/$2" | grep -P "^[\t ]*root"  | awk ' { print $2 } ' | sed 's/;.*$//g')

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


	local site_url=$(get_domain_for_site_id $SITE_ID)
	if [ -z "$site_url" ] ; then
		site_url=$(get_rdns)
	fi
	if [ -z "$site_url" ] ; then
		site_url=$(system_ip)	
	fi
	if [ -z "$site_url" ] ; then
		site_url="127.0.0.1"
	fi
	site_url="http://$site_url"



	cd wp-admin
	echo '<?php' >wpinst.php
	echo "define( 'WP_SITEURL', '$site_url' );" >>wpinst.php

	cat << 'EOF' >>wpinst.php
define( 'WP_INSTALLING', true );

/** Load WordPress Bootstrap */
require_once( dirname( dirname( __FILE__ ) ) . '/../wp-load.php' );

/** Load WordPress Administration Upgrade API */
require_once( dirname( __FILE__ ) . '/includes/upgrade.php' );

/** Load wpdb */
require_once(dirname(dirname(__FILE__)) . '/../wp-includes/wp-db.php');




// Let's check to make sure WP isn't already installed.
if ( is_blog_installed() ) {
	die( '<h1>' . __( 'Already Installed' ) . '</h1><p>' . __( 'You appear to have already installed WordPress. To reinstall please clear your old database tables first.' ) . '</p><p class="step"><a href="../wp-login.php" class="button">' . __('Log In') . '</a></p></body></html>' );
}
// Let's check to make sure WP isn't already installed.
if ( is_blog_installed() ) {
	die( '<h1>' . __( 'Already Installed' ) . '</h1><p>' . __( 'You appear to have already installed WordPress. To reinstall please clear your old database tables first.' ) . '</p><p class="step"><a href="../wp-login.php" class="button">' . __('Log In') . '</a></p></body></html>' );
}

$php_version    = phpversion();
$mysql_version  = $wpdb->db_version();
$php_compat     = version_compare( $php_version, $required_php_version, '>=' );
$mysql_compat   = version_compare( $mysql_version, $required_mysql_version, '>=' ) || file_exists( WP_CONTENT_DIR . '/db.php' );

if ( !$mysql_compat && !$php_compat )
	$compat = sprintf( __('You cannot install because <a href="http://codex.wordpress.org/Version_%1$s">WordPress %1$s</a> requires PHP version %2$s or higher and MySQL version %3$s or higher. You are running PHP version %4$s and MySQL version %5$s.'), $wp_version, $required_php_version, $required_mysql_version, $php_version, $mysql_version );
elseif ( !$php_compat )
	$compat = sprintf( __('You cannot install because <a href="http://codex.wordpress.org/Version_%1$s">WordPress %1$s</a> requires PHP version %2$s or higher. You are running version %3$s.'), $wp_version, $required_php_version, $php_version );
elseif ( !$mysql_compat )
	$compat = sprintf( __('You cannot install because <a href="http://codex.wordpress.org/Version_%1$s">WordPress %1$s</a> requires MySQL version %2$s or higher. You are running version %3$s.'), $wp_version, $required_mysql_version, $mysql_version );

if ( !$mysql_compat || !$php_compat ) {
	die('<h1>' . __('Insufficient Requirements') . '</h1><p>' . $compat . '</p></body></html>');
}
EOF
	echo "\$weblog_title=\"$WP_TITLE\";"  >> wpinst.php
	echo "\$user_name=\"$WP_USER\";"      >> wpinst.php
	echo "\$admin_password=\"$WP_PASS\";" >> wpinst.php
	echo "\$admin_email=\"$WP_EMAIL\";"   >> wpinst.php
	echo "\$public=1;"                    >> wpinst.php
	cat << 'EOF' >>wpinst.php

$result = wp_install($weblog_title, $user_name, $admin_email, $public, '', $admin_password);
extract( $result, EXTR_SKIP );

?>
EOF

	php < wpinst.php
	rm -rf wpinst.php
	cd ..



	chmod 640 wp-config.php
	chown -R www-data *
	chgrp -R www-data *

	# install w3 total cache plugin
	# not 100% sure of 3.1 support, but let's try
	# this with latest dev version -- svn r366391
	cd /tmp
	rm -rf trunk
	svn co -r 366391 http://svn.wp-plugins.org/w3-total-cache/trunk
	mv trunk w3-total-cache
	cd w3-total-cache
	find . -name ".svn" | xargs rm -rf



	/etc/init.d/nginx restart
	/etc/init.d/php5-fpm restart

	cd "$curdir"

}


