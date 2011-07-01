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


	if [ ! -n "$VPATH" ]; then
		echo "Could not determine DocumentRoot for $1"
		return 1;
	fi

	if [ ! -e /usr/bin/wget ]; then
		aptitude -y install wget unzip
	fi


	#set necessary rewrite rule
	echo 'rewrite ^.*/files/(.*)$ /wp-includes/ms-files.php?file=$1 last;'  >/etc/nginx/wordpress.conf
	echo 'if (!-e $request_filename)'                                      >>/etc/nginx/wordpress.conf
	echo '{'                                                               >>/etc/nginx/wordpress.conf
	echo '    rewrite  ^(.+)$ /index.php?q=$1 last;'                       >>/etc/nginx/wordpress.conf
	echo '}'                                                               >>/etc/nginx/wordpress.conf
	chmod 644 /etc/nginx/wordpress.conf
	nginx_add_include_for_vhost "/etc/nginx/sites_available/$SITE_ID" "/etc/nginx/wordpress.conf"




	# download, extract, chown, and get our config file started
	local curdir=$(pwd)
	local wp_ver_file="wordpress-3.1.4.tar.gz"
	cd /tmp
	wget "http://wordpress.org/$wp_ver_file"
	tar xfz $wp_ver_file
	rm -rf $wp_ver_file
	mv "wordpress"/* "$VPATH"
	rm -rf "wordpress"
	chown -R www-data "$VPATH"
	

	cd "$VPATH"
	rm -rf index.html
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

	# set database/username/password	
	sed -i "s/database_name_here/$db/" wp-config.php
	sed -i "s/username_here/$db/" wp-config.php
	sed -i "s/password_here/$WP_PASS/" wp-config.php

	# set WP_CACHE variable to true
	echo "<?php" > wp-config.php.tmp
	echo "define('WP_CACHE', true);" >>wp-config.php.tmp
	cat wp-config.php | egrep -v "^[\t ]*<\?php" | egrep -v "^[\t ]*\?>[\t ]*$" >> wp-config.php.tmp
	echo "?>" >>wp-config.php.tmp
	mv wp-config.php.tmp wp-config.php




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





	# install wp-super-cache plugin
	cd ./wp-content/plugins/
	wget http://downloads.wordpress.org/plugin/wp-super-cache.0.9.9.9.zip
	unzip wp-super-cache.0.9.9.9.zip
	rm -rf wp-super-cache.0.9.9.9.zip


	# specify wp-super-cache configuration
	cat << 'EOF' >../wp-cache-config.php
<?php
/*
WP-Cache Config Sample File

See wp-cache.php for author details.
*/

$wp_cache_mobile_groups = ''; //Added by WP-Cache Manager
$wp_cache_mobile_prefixes = 'w3c , w3c-, acs-, alav, alca, amoi, audi, avan, benq, bird, blac, blaz, brew, cell, cldc, cmd-, dang, doco, eric, hipt, htc_, inno, ipaq, ipod, jigs, kddi, keji, leno, lg-c, lg-d, lg-g, lge-, lg/u, maui, maxo, midp, mits, mmef, mobi, mot-, moto, mwbp, nec-, newt, noki, palm, pana, pant, phil, play, port, prox, qwap, sage, sams, sany, sch-, sec-, send, seri, sgh-, shar, sie-, siem, smal, smar, sony, sph-, symb, t-mo, teli, tim-, tosh, tsm-, upg1, upsi, vk-v, voda, wap-, wapa, wapi, wapp, wapr, webc, winw, winw, xda , xda-'; //Added by WP-Cache Manager
$wp_cache_refresh_single_only = '0'; //Added by WP-Cache Manager
$wp_cache_mod_rewrite = 0; //Added by WP-Cache Manager
$wp_cache_front_page_checks = 0; //Added by WP-Cache Manager
$wp_supercache_304 = 0; //Added by WP-Cache Manager
$wp_cache_slash_check = 0; //Added by WP-Cache Manager
if ( ! defined('WPCACHEHOME') )
	define( 'WPCACHEHOME', WP_CONTENT_DIR . "/plugins/wp-super-cache/" ); //Added by WP-Cache Manager

$cache_compression = 0; // Super cache compression
$cache_enabled = true; //Added by WP-Cache Manager
$super_cache_enabled = true; //Added by WP-Cache Manager
$cache_max_time = 3600; //in seconds
//$use_flock = true; // Set it true or false if you know what to use
$cache_path = WP_CONTENT_DIR . '/cache/';
$file_prefix = 'wp-cache-';
$ossdlcdn = 0;

// We want to be able to identify each blog in a WordPress MU install
$blogcacheid = '';
if( defined( 'VHOST' ) ) {
	$blogcacheid = 'blog'; // main blog
	if( constant( 'VHOST' ) == 'yes' ) {
		$blogcacheid = $_SERVER['HTTP_HOST'];
	} else {
		$request_uri = preg_replace('/[ <>\'\"\r\n\t\(\)]/', '', str_replace( '..', '', $_SERVER['REQUEST_URI'] ) );
		if( strpos( $request_uri, '/', 1 ) ) {
			if( $base == '/' ) {
				$blogcacheid = substr( $request_uri, 1, strpos( $request_uri, '/', 1 ) - 1 );
			} else {
				$blogcacheid = str_replace( $base, '', $request_uri );
				$blogcacheid = substr( $blogcacheid, 0, strpos( $blogcacheid, '/', 1 ) );
			}
			if ( '/' == substr($blogcacheid, -1))
				$blogcacheid = substr($blogcacheid, 0, -1);
		}
		$blogcacheid = str_replace( '/', '', $blogcacheid );
	}
}

// Array of files that have 'wp-' but should still be cached 
$cache_acceptable_files = array( 'wp-comments-popup.php', 'wp-links-opml.php', 'wp-locations.php' );

$cache_rejected_uri = array('wp-.*\\.php', 'index\\.php');
$cache_rejected_user_agent = array ( 0 => 'bot', 1 => 'ia_archive', 2 => 'slurp', 3 => 'crawl', 4 => 'spider', 5 => 'Yandex' );

$cache_rebuild_files = 1; //Added by WP-Cache Manager

// Disable the file locking system.
// If you are experiencing problems with clearing or creating cache files
// uncommenting this may help.
$wp_cache_mutex_disabled = 1; //Added by WP-Cache Manager

// Just modify it if you have conflicts with semaphores
$sem_id = 1816471371; //Added by WP-Cache Manager

if ( '/' != substr($cache_path, -1)) {
	$cache_path .= '/';
}

$wp_cache_mobile = 0;
$wp_cache_mobile_whitelist = 'Stand Alone/QNws';
$wp_cache_mobile_browsers = '2.0 MMP, 240x320, 400X240, AvantGo, BlackBerry, Blazer, Cellphone, Danger, DoCoMo, Elaine/3.0, EudoraWeb, Googlebot-Mobile, hiptop, IEMobile, KYOCERA/WX310K, LG/U990, MIDP-2., MMEF20, MOT-V, NetFront, Newt, Nintendo Wii, Nitro, Nokia, Opera Mini, Palm, PlayStation Portable, portalmmm, Proxinet, ProxiNet, SHARP-TQ-GX10, SHG-i900, Small, SonyEricsson, Symbian OS, SymbianOS, TS21i-10, UP.Browser, UP.Link, webOS, Windows CE, WinWAP, YahooSeeker/M1A1-R2D2, iPhone, iPod, Android, BlackBerry9530, LG-TU915 Obigo, LGE VX, webOS, Nokia5800'; //Added by WP-Cache Manager

// change to relocate the supercache plugins directory
$wp_cache_plugins_dir = WPCACHEHOME . 'plugins';
// set to 1 to do garbage collection during normal process shutdown instead of wp-cron
$wp_cache_shutdown_gc = 0; 
$wp_super_cache_late_init = 0; //Added by WP-Cache Manager

// uncomment the next line to enable advanced debugging features
$wp_super_cache_advanced_debug = 0;
$wp_super_cache_front_page_text = '';
$wp_super_cache_front_page_clear = 0;
$wp_super_cache_front_page_check = 0;
$wp_super_cache_front_page_notification = '0';

$wp_cache_object_cache = 0; //Added by WP-Cache Manager
$wp_cache_anon_only = 0;
$wp_supercache_cache_list = 0; //Added by WP-Cache Manager
$wp_cache_debug_to_file = 0;
$wp_super_cache_debug = 0;
$wp_cache_debug_level = 5;
$wp_cache_debug_ip = '';
$wp_cache_debug_log = '';
$wp_cache_debug_email = '';
$wp_cache_pages[ "search" ] = 0;
$wp_cache_pages[ "feed" ] = 0;
$wp_cache_pages[ "category" ] = 0;
$wp_cache_pages[ "home" ] = 0;
$wp_cache_pages[ "frontpage" ] = 0;
$wp_cache_pages[ "tag" ] = 0;
$wp_cache_pages[ "archives" ] = 0;
$wp_cache_pages[ "pages" ] = 0;
$wp_cache_pages[ "single" ] = 0;
$wp_cache_hide_donation = 0;
$wp_cache_not_logged_in = 0; //Added by WP-Cache Manager
$wp_cache_clear_on_post_edit = 0; //Added by WP-Cache Manager
$wp_cache_hello_world = 0; //Added by WP-Cache Manager
$wp_cache_mobile_enabled = 1; //Added by WP-Cache Manager
$wp_cache_cron_check = 0;
?>	
EOF
	

	#activate wp-super-cache plugin
	echo "UPDATE wp_options SET option_value='/index.php/archives/%post_id%' WHERE option_name='permalink_structure' ;"              | mysql --user="$db" --password="$WP_PASS" $db
	echo "UPDATE wp_options SET option_value='a:1:{i:0;s:27:\"wp-super-cache/wp-cache.php\";}' WHERE option_name='active_plugins' ;" | mysql --user="$db" --password="$WP_PASS" $db
	echo "UPDATE wp_options SET autoload='yes' WHERE option_name='active_plugins' ;"                                                 | mysql --user="$db" --password="$WP_PASS" $db
	
	cd "$VPATH"
	chmod 640 wp-config.php
	chown -R www-data *
	chgrp -R www-data *

	/etc/init.d/nginx restart
	/etc/init.d/php5-fpm restart

	cd "$curdir"

}


