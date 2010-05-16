#!/bin/bash


#################################
#	PHP-FPM			#
#################################


function php_fpm_install
{
	if [ ! -n "$1" ]; then
		echo "install_php_fpm requires server user as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "install_php_fpm requires server group as its second argument"
		return 1;
	fi

	local PHP_FPM_USER="$1"
	local PHP_FPM_GROUP="$2"

	#check for versions of: libevent; php-fpm; php; suhosin; suhosin patch.
	#the naming conventions php-fpm have changed at random in the past. be careful.
	#
	# http://monkey.org/~provos/libevent/
	# http://launchpad.net/php-fpm/
	# http://php.net/
	# http://www.hardened-php.net/suhosin/download.html
	#
	#and alter variables as necessary

	local curdir=$(pwd)
	
	#dependencies for all the crap to be included with php
	aptitude install -y libcurl4-openssl-dev libjpeg62-dev libpng12-dev libxpm-dev libfreetype6-dev libt1-dev libmcrypt-dev libxslt1-dev libbz2-dev libxml2-dev

	#not php specific deps
	aptitude install -y wget build-essential autoconf

	#create directory to play in
	mkdir /tmp/phpcrap
	cd /tmp/phpcrap

	#need stable libevent.
	wget "http://www.monkey.org/~provos/libevent-$LIBEVENT_VER.tar.gz"
	tar -xzvf "libevent-$LIBEVENT_VER.tar.gz"
	cd "libevent-$LIBEVENT_VER"
	./configure
	make
	DESTDIR=$PWD make install
	export LIBEVENT_SEARCH_PATH="$PWD/usr/local"

	#don't want to build in libevent directory
	cd ../

	#grab php.
	wget "http://us.php.net/get/php-$PHP_VER.tar.bz2/from/us.php.net/mirror"
	tar -xjvf "php-$PHP_VER.tar.bz2"

	#grab suhosin.
	wget "http://download.suhosin.org/suhosin-patch-$PHP_VER-$SUHOSIN_PATCH_VER.patch.gz"
	gunzip "suhosin-patch-$PHP_VER-$SUHOSIN_PATCH_VER.patch.gz"

	#patch php with suhosin.
	cd "php-$PHP_VER"
	patch -p 1 -i "../suhosin-patch-$PHP_VER-$SUHOSIN_PATCH_VER.patch"

	#build php
	mkdir php-build
	cd php-build
	../configure --with-config-file-path=/usr/local/lib/php --with-curl --enable-exif --with-gd --with-jpeg-dir --with-png-dir --with-zlib --with-xpm-dir --with-freetype-dir --with-t1lib --with-mcrypt --with-mhash --with-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-mysql-sock=/var/run/mysqld/mysqld.sock --with-openssl --enable-sysvmsg --enable-wddx --with-xsl --enable-zip --with-bz2 --enable-bcmath --enable-calendar --enable-ftp --enable-mbstring --enable-soap --enable-sockets --enable-sqlite-utf8 --with-gettext --enable-shmop --with-xmlrpc
	make

	#grab php-fpm and build
	wget "http://launchpad.net/php-fpm/master/$PHP_FPM_VER/+download/php-fpm-$PHP_FPM_VER~$PHP_VER_IND.tar.gz"
	tar -xzvf "php-fpm-$PHP_FPM_VER~$PHP_VER_IND.tar.gz"
	cd "php-fpm-$PHP_FPM_VER-$PHP_VER_IND"
	mkdir fpm-build
	cd fpm-build
	../configure --srcdir=../ --with-php-src="../../../" --with-php-build="../../" --with-libevent="$LIBEVENT_SEARCH_PATH" --with-fpm-bin=/usr/local/sbin/php-fpm  --with-fpm-init=/etc/init.d/php-fpm --with-fpm-user="$PHP_FPM_USER" --with-fpm-group="$PHP_FPM_GROUP"
	make

	#install php
	cd ../../
	make install

	#move php.ini to where php-fpm looks for it
	cp "/tmp/phpcrap/php-$PHP_VER/php.ini-production" /usr/local/lib/php/php.ini

	#set default timezone to UTC to avoid errors from php date functions
	sed -i -e 's/^;date\.timezone.*$/date\.timezone = "UTC"/g' /usr/local/lib/php/php.ini


	#set permissions
	chmod 644 /usr/local/lib/php/php.ini

	#install php-fpm
	cd "php-fpm-$PHP_FPM_VER-$PHP_VER_IND"
	cd fpm-build
	make install

	#grab and install suhosin extension.
	cd ../../../../
	wget "http://download.suhosin.org/suhosin-$SUHOSIN_VER.tgz"
	tar -xzvf "suhosin-$SUHOSIN_VER.tgz"
	cd "suhosin-$SUHOSIN_VER"
	/usr/local/bin/phpize
	./configure
	make
	make install

	#make php use it.
	echo "extension = suhosin.so" >> /usr/local/lib/php/php.ini

	#have /etc/init.d/php-fpm run on boot
	update-rc.d php-fpm defaults

	#/etc/php-fpm.conf stuff
	#sockets > ports. Using the 127.0.0.1:9000 stuff needlessly introduces TCP/IP overhead.
	sed -i 's/<value\ name="listen_address">127.0.0.1:9000<\/value>/<value\ name="listen_address">\/var\/run\/php-fpm.sock<\/value>/' /etc/php-fpm.conf
	
	#nice strict permissions
	sed -i 's/<value\ name="mode">0666<\/value>/<value\ name="mode">0600<\/value>/' /etc/php-fpm.conf
	
	#matches available processors. Will not make a 360 melt.
	sed -i 's/<value\ name="max_children">5<\/value>/<value\ name="max_children">4<\/value>/' /etc/php-fpm.conf
	
	#i like to know when scripts are slow.
	sed -i 's/<value\ name="request_slowlog_timeout">0s<\/value>/<value name="request_slowlog_timeout">2s<\/value>/' /etc/php-fpm.conf

	#edited to include PHP path
	sed -i 's/<value\ name="PATH">\/usr\/local\/bin:\/usr\/bin:\/bin<\/value>/<value\ name="PATH">\/usr\/local\/bin:\/usr\/bin:\/bin:\/usr\/local\/sbin<\/value>/' /etc/php-fpm.conf

	#Engage.
        /etc/init.d/php-fpm start

	cd "$curdir"

	#remove build crap
	rm -rf /tmp/phpcrap

}

######################
# Ruby / Rails       #
######################

function ruby_install
{
	local curdir=$(pwd)
	
	ruby_ee_source_url=$(echo $(wget -O-  http://www.rubyenterpriseedition.com/download.html 2>/dev/null ) | egrep -o 'href="[^\"]*\.tar\.gz' | sed 's/^href="//g')
	mkdir /tmp/ruby
	cd /tmp/ruby

	aptitude install -y build-essential zlib1g-dev libssl-dev libreadline5-dev
	wget "$ruby_ee_source_url"
	tar xvzf *.tar.gz
	rm -rf *.tar.gz
	cd ruby*
	./installer --auto "$RUBY_PREFIX"

	for ex in erb gem irb rackup rails rake rdoc ri ruby ; do
		ln -s "$RUBY_PREFIX/bin/$ex" "/usr/bin/$ex"
	done

	gem install mysql
	gem install rails

	#necessary for redmine grack auth
	gem install dbi
	gem install dbd-mysql

	#necessary for redmine gitosis plugin
	gem install inifile
	gem install net-ssh
	gem install lockfile

	cd "$curdir"
	rm -rf /tmp/ruby
}

#################################
#	nginx			#
#################################

function nginx_create_site
{
	local server_id="$1"
	local server_name_list="$2"
	local is_ssl="$3"
	local rails_paths="$4"
	local enable_php="$5"

	port="80"
	ssl_cert=""
	ssl_ckey=""
	ssl=""
	if [ "$is_ssl" = "1" ] ; then
		port="443"
		ssl="ssl                  on;"
		ssl_cert="ssl_certificate      $NGINX_CONF_PATH/ssl/nginx.pem;"
		ssl_ckey="ssl_certificate_key  $NGINX_CONF_PATH/ssl/nginx.key;"
		if [ ! -e "$NGINX_CONF_PATH/ssl/nginx.pem" ] || [ ! -e "$NGINX_CONF_PATH/ssl/nginx.key"  ] ; then
			aptitude -y install ssl-cert
			mkdir -p "$NGINX_CONF_PATH/ssl"
			make-ssl-cert generate-default-snakeoil --force-overwrite
			cp /etc/ssl/certs/ssl-cert-snakeoil.pem    "$NGINX_CONF_PATH/ssl/nginx.pem"
			cp /etc/ssl/private/ssl-cert-snakeoil.key  "$NGINX_CONF_PATH/ssl/nginx.key"
		fi
	fi

	config_path="$NGINX_CONF_PATH/sites-available/$server_id"
	cat << EOF >"$config_path"
server
{
	listen               $port;
	server_name          $server_name_list;
	access_log           $NGINX_PREFIX/$server_id/logs/access.log;
	root                 $NGINX_PREFIX/$server_id/public_html;
	index                index.html index.htm index.php index.cgi;
	$ssl
	$ssl_cert
	$ssl_ckey

	#rails
EOF


	if [ -z "$rails_paths" ] ; then
		cat << EOF >>"$config_path"
	#passenger_enabled   on;
	#passenger_base_uri  rails_app; ##should be symlink to public dir of actual rails_app 
EOF
	else
		echo '	passenger_enabled   on;' >>"$config_path"
		if [ "$rails_paths" != '.' ] ; then
			for rp in $rails_paths ; do
				echo "	passenger_base_uri  $rp; " >> "$config_path"
			done
		fi	
	fi

	local php_comment=""
	if [ "$php_enabled" == '0' ] ; then
		php_comment="#"
	fi
	cat << EOF >>"$config_path"

	${php_comment}#php
	${php_comment}location ~ \.php\$
	${php_comment}{
	${php_comment}	fastcgi_pass   unix:/var/run/php-fpm.sock ;
	${php_comment}	include        $NGINX_CONF_PATH/fastcgi_params;
	${php_comment}}
EOF

	echo "}" >> "$config_path"
	

	mkdir -p "$NGINX_PREFIX/$server_id/public_html"
	mkdir -p "$NGINX_PREFIX/$server_id/logs"
	cat << EOF >"$NGINX_PREFIX/$server_id/public_html/index.html"
<html>
	<head>
		<title>Nothing To See Here</title>
	</head>
	<body style="background:#FFBBBB;">
		<center>
			<p>Nginx is running on $server_id</p>
			<p>Please disregard the pink <a href="http://xkcd.com/636/">brontosaurus</a>.</p>
			<p>Move along, nothing to see here...</p>
		</center>
	</body>
</html>
EOF
	chown -R www-data:www-data "$NGINX_PREFIX/$server_id"

}
function nginx_ensite
{
	local server_id="$1"
	ln -s "$NGINX_CONF_PATH/sites-available/$server_id" "$NGINX_CONF_PATH/sites-enabled/$server_id" 
	/etc/init.d/nginx restart
}
function nginx_dissite
{
	rm -rf "$NGINX_CONF_PATH/sites-enabled/$server_id"
	/etc/init.d/nginx restart
}
function nginx_delete_site
{
	local server_id="$1"
	rm -rf "$NGINX_CONF_PATH/sites-enabled/$server_id"
	rm -rf "$NGINX_CONF_PATH/sites-available/$server_id"
	rm -rf "$NGINX_PREFIX/$server_id"
	/etc/init.d/nginx restart
}


function nginx_add_passenger_uri_for_vhost
{
	local VHOST_CONFIG_FILE=$1
	local URI=$2

	escaped_uri=$(echo "$URI" | sed 's/\//\\\//g')
	escaped_search_uri=$(echo "$escaped_uri" | sed 's/\./\\./g')
	escaped_search_uri=$(echo "$escaped_search_uri" | sed 's/\-/\\-/g')
	escaped_search_uri=$(echo "$escaped_search_uri" | sed 's/\$/\\$/g')
	escaped_search_uri=$(echo "$escaped_search_uri" | sed 's/\^/\\^/g')
	#I don't think any other special characters are going to be showing up in the uri...
	

	NL=$'\\\n'
	TAB=$'\\\t'
	cat "$VHOST_CONFIG_FILE" | grep -v -P "^[\t ]*passenger_base_uri[\t ]+$escaped_search_uri;"  > "$VHOST_CONFIG_FILE.tmp" 
	enabled_line=$(grep -P "^[\t ]*passenger_enabled[\t ]+" "$VHOST_CONFIG_FILE")
	if [ -n "$enabled_line" ] ; then
		
		cat   "$VHOST_CONFIG_FILE.tmp" | sed -e "s/passenger_enabled.*$/passenger_enabled   on;${NL}${TAB}passenger_base_uri  $escaped_uri;/g"  > "$VHOST_CONFIG_FILE"
	else
		cat   "$VHOST_CONFIG_FILE.tmp" | sed -e "s/^{$/{${NL}${TAB}passenger_enabled   on;${NL}${TAB}passenger_base_uri  $escaped_uri;/g"  > "$VHOST_CONFIG_FILE"
	fi
	rm -rf "$VHOST_CONFIG_FILE.tmp" 

}

function nginx_add_include_for_vhost
{
	local VHOST_CONFIG_FILE=$1
	local INCLUDE_FILE=$2

	escaped_search_include=$(echo "$INCLUDE_FILE" | sed 's/\//\\\//g')
	escaped_search_include=$(echo "$escaped_search_include" | sed 's/\./\\./g')
	escaped_search_include=$(echo "$escaped_search_include" | sed 's/\-/\\-/g')
	escaped_search_include=$(echo "$escaped_search_include" | sed 's/\$/\\$/g')
	escaped_search_include=$(echo "$escaped_search_include" | sed 's/\^/\\^/g')
	
	
	cat "$VHOST_CONFIG_FILE" | grep -v -P "^[\t ]*include[\t ]+$escaped_search_include;" | grep -v "^}[\t ]*$"  > "$VHOST_CONFIG_FILE.tmp" 
	printf "\tinclude $INCLUDE_FILE;\n" >>"$VHOST_CONFIG_FILE.tmp"
	echo "}" >>"$VHOST_CONFIG_FILE.tmp"
	mv "$VHOST_CONFIG_FILE.tmp" "$VHOST_CONFIG_FILE"
}



function nginx_install 
{
	if [ ! -n "$1" ]; then
		echo "install_nginx requires server user as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "install_nginx requires server group as its second argument"
		return 1;
	fi

	local NGINX_USER="$1"
	local NGINX_GROUP="$2"
	local NGINX_USE_PHP="$3"
	local NGINX_USE_PASSENGER="$4"

	if [ -z "$NGINX_USE_PHP" ] ; then
		NGINX_USE_PHP=1
	fi
	if [ -z "$NGINX_USE_PASSENGER" ] ; then
		NGINX_USE_PASSENGER=1
	fi

	if [ "$NGINX_USE_PHP" = 1 ] ; then
		php_fpm_install "$NGINX_USER" "$NGINX_GROUP"
	fi
	if [ "$NGINX_USE_PASSENGER" = 1 ] ; then
		ruby_install
	fi



	local curdir=$(pwd)

	#theres a couple dependencies.
	aptitude install -y libpcre3-dev libcurl4-openssl-dev libssl-dev

	#not nginx specific deps
	aptitude install -y wget build-essential

	#need dpkg-dev for no headaches when apt-get source nginx
	aptitude install -y dpkg-dev

	#directory to play in
	mkdir /tmp/nginx
	cd /tmp/nginx

	#grab and extract
	wget "http://nginx.org/download/nginx-$NGINX_VER.tar.gz"
	tar -xzvf "nginx-$NGINX_VER.tar.gz"

	#I think Reddit has the right idea here....
	#Lil' Bobby Tables, aint he so cute?
	cat "nginx-$NGINX_VER/src/http/ngx_http_header_filter_module.c" | sed "s/\"Server: nginx\"/\"Server: '; DROP TABLE server_types; --\"/g" > /tmp/ngx_h1.tmp
	cat /tmp/ngx_h1.tmp | sed "s/\"Server: \".*NGINX_VER/\"Server: '; DROP TABLE servertypes; --\"/g" > "nginx-$NGINX_VER/src/http/ngx_http_header_filter_module.c"


	#maek eet
	cd "nginx-$NGINX_VER"

	nginx_conf_file="$NGINX_CONF_PATH/nginx.conf"
	nginx_http_log_file="$NGINX_HTTP_LOG_PATH/access.log"

	passenger_root=""
	passenger_path=""
	if  [ "$NGINX_USE_PASSENGER" = 1 ] ; then
		passenger_root=`$RUBY_PREFIX/bin/passenger-config --root`
		passenger_path="$passenger_root/ext/nginx"


		./configure --prefix="$NGINX_PREFIX" --sbin-path="$NGINX_SBIN_PATH" --conf-path="$nginx_conf_file" --pid-path="$NGINX_PID_PATH" --error-log-path="$NGINX_ERROR_LOG_PATH" --http-log-path="$nginx_http_log_file" --user="$NGINX_USER" --group="$NGINX_GROUP" --with-http_ssl_module --with-debug --add-module="$passenger_path"
	else
		./configure --prefix="$NGINX_PREFIX" --sbin-path="$NGINX_SBIN_PATH" --conf-path="$nginx_conf_file" --pid-path="$NGINX_PID_PATH" --error-log-path="$NGINX_ERROR_LOG_PATH" --http-log-path="$nginx_http_log_file" --user="$NGINX_USER" --group="$NGINX_GROUP" --with-http_ssl_module --with-debug

	fi

	make
	make install

	#grab source for ready-made scripts
	apt-get source nginx
	
	#alter init to match sbin path specified in configure. add to init.d
	sed -i "s@DAEMON=/usr/sbin/nginx@DAEMON=$NGINX_SBIN_PATH@" nginx-*/debian/init.d
	cp nginx-*/debian/init.d /etc/init.d/nginx
	chmod 744 /etc/init.d/nginx
	update-rc.d nginx defaults

	#use provided logrotate file. adjust as you please
	sed -i "s/daily/$LOGRO_FREQ/" nginx-*/debian/nginx.logrotate
	sed -i "s/52/$LOGRO_ROTA/" nginx-*/debian/nginx.logrotate
	cp nginx*/debian/nginx.logrotate /etc/logrotate.d/nginx


	pass_comment=""
	if [  "$NGINX_USE_PASSENGER" != 1 ] ; then
		pass_comment="#"
	fi


	#setup default nginx config files
	echo "fastcgi_param  SCRIPT_FILENAME   \$document_root\$fastcgi_script_name;" >> "$NGINX_CONF_PATH/fastcgi_params";
	cat <<EOF >$NGINX_CONF_PATH/nginx.conf

worker_processes 4;

events
{
	worker_connections 1024;
}
http
{
	include             mime.types;
	default_type        application/octet-stream;

	server_names_hash_max_size       4096;
	server_names_hash_bucket_size    4096;

	${pass_comment}passenger_root                   $passenger_root;
	${pass_comment}passenger_ruby                   $RUBY_PREFIX/bin/ruby;
	${pass_comment}passenger_max_pool_size          1;
	${pass_comment}passenger_pool_idle_time         1;
	${pass_comment}passenger_max_instances_per_app  1;
		

	#proxy settings (only relevant when nginx used as a proxy)
	proxy_set_header Host \$host;
	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_set_header X-Real-IP \$remote_addr;


	keepalive_timeout   65;
	sendfile            on;

	#gzip               on;
	#tcp_nopush         on;
	
	include $NGINX_CONF_PATH/sites-enabled/*;
}
EOF


	mkdir -p "$NGINX_CONF_PATH/sites-enabled"
	mkdir -p "$NGINX_CONF_PATH/sites-available"

	#create default site & start nginx
	nginx_create_site "default" "localhost" "0" "" "$NGINX_USE_PHP"
	nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "" "$NGINX_USE_PHP"

	nginx_ensite      "default"
	nginx_ensite      "$NGINX_SSL_ID"
	

	#delete build directory
	rm -rf /tmp/nginx

	chown -R www-data:www-data /srv/www


	#return to original directory
	cd "$curdir"
}


