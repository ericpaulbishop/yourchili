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


	#installing only the basics.
	mkdir -p /var/www  #required to install php5-fpm -- it's a bug in Ubuntu
	aptitude install -y php5-fpm php5-mysql php5-pgsql php5
 
	#php5-fpm conf
	php_fpm_conf_file=`grep -R "^listen.*=.*127" /etc/php5/fpm/* | sed 's/:.*$//g' | uniq | head -n 1`
 
	#sockets > ports. Using the 127.0.0.1:9000 stuff needlessly introduces TCP/IP overhead.
	sed -i 's/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/' $php_fpm_conf_file
	
	#nice strict permissions
	sed -i 's/;listen.owner = www-data/listen.owner = '"$PHP_FPM_USER"'/'  $php_fpm_conf_file
	sed -i 's/;listen.group = www-data/listen.group = '"$PHP_FPM_GROUP"'/' $php_fpm_conf_file
	sed -i 's/;listen.mode = 0666/listen.mode = 0600/'                     $php_fpm_conf_file

	
	#these settings are fairly conservative and can probably be increased without things melting
	sed -i 's/pm.max_children = 50/pm.max_children = 12/'           $php_fpm_conf_file
	sed -i 's/pm.start_servers = 20/pm.start_servers = 4/'          $php_fpm_conf_file
	sed -i 's/pm.min_spare_servers = 5/pm.min_spare_servers = 2/'   $php_fpm_conf_file
	sed -i 's/pm.max_spare_servers = 35/pm.max_spare_servers = 4/'  $php_fpm_conf_file
	sed -i 's/pm.max_requests = 0/pm.max_requests = 500/'           $php_fpm_conf_file

 
	#Engage.
	/etc/init.d/php5-fpm restart
}

function perl_fcgi_install
{
	aptitude install -y build-essential psmisc libfcgi-perl
	
	cat << 'EOF' >/usr/bin/perl-fastcgi
#!/usr/bin/perl

use FCGI;
use Socket;
use POSIX qw(setsid);

require 'syscall.ph';

&daemonize;

#this keeps the program alive or something after exec'ing perl scripts
END() { } BEGIN() { }
*CORE::GLOBAL::exit = sub { die "fakeexit\nrc=".shift()."\n"; }; 
eval q{exit}; 
if ($@) { 
	exit unless $@ =~ /^fakeexit/; 
};

&main;

sub daemonize() {
    chdir '/'                 or die "Can't chdir to /: $!";
    defined(my $pid = fork)   or die "Can't fork: $!";
    exit if $pid;
    setsid                    or die "Can't start a new session: $!";
    umask 0;
}

sub main {
        $socket = FCGI::OpenSocket( "/var/run/perl-fastcgi/perl-fastcgi.sock", 25 );
        $request = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%req_params, $socket );
        if ($request) { request_loop()};
            FCGI::CloseSocket( $socket );
}

sub request_loop {
        while( $request->Accept() >= 0 ) {
            
           #processing any STDIN input from WebServer (for CGI-POST actions)
           $stdin_passthrough ='';
           $req_len = 0 + $req_params{'CONTENT_LENGTH'};
           if (($req_params{'REQUEST_METHOD'} eq 'POST') && ($req_len != 0) ){ 
                my $bytes_read = 0;
                while ($bytes_read < $req_len) {
                        my $data = '';
                        my $bytes = read(STDIN, $data, ($req_len - $bytes_read));
                        last if ($bytes == 0 || !defined($bytes));
                        $stdin_passthrough .= $data;
                        $bytes_read += $bytes;
                }
            }

            #running the cgi app
            if ( (-x $req_params{SCRIPT_FILENAME}) &&  #can I execute this?
                 (-s $req_params{SCRIPT_FILENAME}) &&  #Is this file empty?
                 (-r $req_params{SCRIPT_FILENAME})     #can I read this file?
            ){
		pipe(CHILD_RD, PARENT_WR);
		my $pid = open(KID_TO_READ, "-|");
		unless(defined($pid)) {
			print("Content-type: text/plain\r\n\r\n");
                        print "Error: CGI app returned no output - ";
                        print "Executing $req_params{SCRIPT_FILENAME} failed !\n";
			next;
		}
		if ($pid > 0) {
			close(CHILD_RD);
			print PARENT_WR $stdin_passthrough;
			close(PARENT_WR);

			while(my $s = <KID_TO_READ>) { print $s; }
			close KID_TO_READ;
			waitpid($pid, 0);
		} else {
	                foreach $key ( keys %req_params){
        	           $ENV{$key} = $req_params{$key};
                	}
        	        # cd to the script's local directory
	                if ($req_params{SCRIPT_FILENAME} =~ /^(.*)\/[^\/]+$/) {
                        	chdir $1;
                	}

			close(PARENT_WR);
			close(STDIN);
			#fcntl(CHILD_RD, F_DUPFD, 0);
			syscall(&SYS_dup2, fileno(CHILD_RD), 0);
			#open(STDIN, "<&CHILD_RD");
			exec($req_params{SCRIPT_FILENAME});
			die("exec failed");
		}
            } 
            else {
                print("Content-type: text/plain\r\n\r\n");
                print "Error: No such CGI app - $req_params{SCRIPT_FILENAME} may not ";
                print "exist or is not executable by this process.\n";
            }

        }
}
EOF

	cat << 'EOF' >/etc/init.d/perl-fastcgi
#!/bin/bash
PERL_SCRIPT=/usr/bin/perl-fastcgi
FASTCGI_USER=www-data
SOCKET_DIR=/var/run/perl-fastcgi
RETVAL=0
case "$1" in
    start)
      mkdir -p $SOCKET_DIR >/dev/null 2>&1
      rm -rf $SOCKET_DIR/*  >/dev/null 2>&1
      chown $FASTCGI_USER $SOCKET_DIR  >/dev/null 2>&1
      su - $FASTCGI_USER -c $PERL_SCRIPT
      RETVAL=$?
  ;;
    stop)
      killall -9 perl-fastcgi
      rm -rf $SOCKET_DIR/*
      RETVAL=$?
  ;;
    restart)
      killall -9 fastcgi-wrapper.pl >/dev/null 2>&1
      mkdir -p $SOCKET_DIR >/dev/null 2>&1
      rm -rf $SOCKET_DIR/*  >/dev/null 2>&1
      chown $FASTCGI_USER $SOCKET_DIR  >/dev/null 2>&1
      su - $FASTCGI_USER -c $PERL_SCRIPT
      RETVAL=$?
  ;;
    *)
      echo "Usage: perl-fastcgi {start|stop|restart}"
      exit 1
  ;;
esac      
exit $RETVAL
EOF


	chmod +x /usr/bin/perl-fastcgi
	chmod +x /etc/init.d/perl-fastcgi
	update-rc.d perl-fastcgi defaults
	/etc/init.d/perl-fastcgi start

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
	gem install rails --version 3.0.5

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
	local enable_perl="$6"

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
			aptitude install -y ssl-cert
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
	local perl_comment=""
	if [ "$enable_php" == '0' ] ; then
		php_comment="#"
	fi
	if [ "$enable_perl" == '0' ] ; then
		perl_comment="#"
	fi

	cat << EOF >>"$config_path"

	${php_comment}#php
	${php_comment}location ~ \.php\$
	${php_comment}{
	${php_comment}	fastcgi_pass   unix:/var/run/php-fpm.sock ;
	${php_comment}	include        $NGINX_CONF_PATH/fastcgi_params;
	${php_comment}}

	${perl_comment}#perl
	${perl_comment}location ~ \.pl\$
	${perl_comment}{
	${perl_comment}	fastcgi_pass   unix:/var/run/perl-fastcgi/perl-fastcgi.sock ;
	${perl_comment}	include        $NGINX_CONF_PATH/fastcgi_params;
	${perl_comment}}

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
	enabled_line=$(grep -P "^[\t #]*passenger_enabled[\t ]+" "$VHOST_CONFIG_FILE")
	if [ -n "$enabled_line" ] ; then
		
		cat   "$VHOST_CONFIG_FILE.tmp" | sed -e "s/^.*passenger_enabled.*$/${TAB}passenger_enabled   on;${NL}${TAB}passenger_base_uri  $escaped_uri;/g"  > "$VHOST_CONFIG_FILE"
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
	local NGINX_USE_PERL="$5"

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
	if [ "$NGINX_USE_PERL" = 1 ] ; then
		perl_fcgi_install
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
	${pass_comment}passenger_max_pool_size          3;
	${pass_comment}passenger_pool_idle_time         0;
	${pass_comment}passenger_max_instances_per_app  3;
		

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
	nginx_create_site "default" "localhost" "0" "" "$NGINX_USE_PHP" "$NGINX_USE_PERL"
	nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "" "$NGINX_USE_PHP" "$NGINX_USE_PERL"

	nginx_ensite      "default"
	nginx_ensite      "$NGINX_SSL_ID"
	

	#delete build directory
	rm -rf /tmp/nginx

	chown -R www-data:www-data /srv/www


	#return to original directory
	cd "$curdir"
}



#################################################################################
# Utility function for generating SSL key & certificate signing request (.csr)  #
# Useful if you need authenticated HTTPS                                        #
# key and csr files are generated in current working directory                  #
# old key and csr files are removed                                             #
#################################################################################

function gen_ssl_key_and_request
{
	local country="$1"       # 2 letter code,                     e.g. "US"
	local state="$2"         # Full name of state/province,       e.g. "Rhode Island"
	local city="$3"          # Full city name,                    e.g. "Providence"
	local organization="$4"  # Your full organization name,       e.g. "Diane's Dildo Emporium LLC"
	local org_unit="$5"      # Organizational unit, can be blank  e.g. "Web Services"
	local site_name="$6"     # Full domain name                   e.g. "www.dianesdildos.com"
	local email="$7"         # Contact email address              e.g. "dirtydiane@dianesdildos.com"
	local valid_time="$8"    # Number of days cert will be valid  e.g. "365" (for one year)

	rm -rf "$site_name.key" "$site_name.csr"
	printf "$country\n$state\n$city\n$organization\n$org_unit\n$site_name\n$email\n\n\n\n\n\n" | openssl req -new -days "$valid_time" -nodes -newkey rsa:2048 -keyout "$site_name.key" -out "$site_name.csr"

}


