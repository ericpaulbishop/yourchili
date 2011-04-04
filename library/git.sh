#!/bin/bash



##################
# Git / Gitosis  #
##################


function git_install
{
	aptitude install -y tk8.4 libcurl3 libcurl-dev git
}

function gitosis_install
{
	aptitude install -y ssh
	git_install

	if [ ! -d "/srv/projects/git" ] ; then
		local curdir=$(pwd)
		
		cd /tmp
		git clone git://eagain.net/gitosis.git
		cd gitosis
		aptitude install -y python-setuptools
		python setup.py install
		adduser \
			--system \
			--shell /bin/sh \
			--gecos 'git version control' \
			--ingroup www-data \
			--disabled-password \
			--home /srv/projects/git \
			git

		mkdir -p /srv/projects/git
		chmod -R 755 /srv/projects/git
		chown -R git:www-data /srv/projects/git
		if [ ! -e /root/.ssh/id_rsa ] ; then
			rm -rf /root/.ssh/id_rsa*
			printf "/root/.ssh/id_rsa\n\n\n\n\n" | ssh-keygen -t rsa -P "" 
		fi
		sudo -H -u git gitosis-init < /root/.ssh/id_rsa.pub
		chmod -R 775 /srv/projects/git/repositories
		
		cd "$curdir"
		rm -rf /tmp/gitosis

		#git daemon init 
		#(only exports public projects, with git-daemon-export-ok file, so by default it is secure)
		cat << 'EOF' > /etc/init.d/git-daemon
#!/bin/sh

test -f /usr/local/libexec/git-core/git-daemon || exit 0

. /lib/lsb/init-functions

GITDAEMON_OPTIONS="--reuseaddr --verbose --base-path=/srv/projects/git/repositories/ --detach"

case "$1" in
start)  log_daemon_msg "Starting git-daemon"

        start-stop-daemon --start -c git:www-data --quiet --background \
                     --exec /usr/local/libexec/git-core/git-daemon -- ${GITDAEMON_OPTIONS}

        log_end_msg $?
        ;;
stop)   log_daemon_msg "Stopping git-daemon"

        start-stop-daemon --stop --quiet --name git-daemon

        log_end_msg $?
        ;;
*)      log_action_msg "Usage: /etc/init.d/git-daemon {start|stop}"
        exit 2
        ;;
esac
exit 0
EOF
		chmod 755 /etc/init.d/git-daemon
		update-rc.d git-daemon defaults
		/etc/init.d/git-daemon start

	fi


}

function create_git
{
	local PROJ_ID=$1
	local REDMINE_ID=$2
	local REDMINE_ADMIN_PW=$3
	local FORCE_SSL_AUTH="$4"

	local db="$REDMINE_ID"_rm
	
	local curdir=$(pwd)


	#does nothing if git/gitosis is already installed
	git_install
	gitosis_install

	#create git repository
	mkdir -p "/srv/projects/git/repositories/$PROJ_ID.git"
	cd "/srv/projects/git/repositories/$PROJ_ID.git"
	git init --bare
	chmod -R 775 /srv/projects/git/repositories/
	chown -R git:www-data /srv/projects/git/repositories/

	

	#install and configure grack
	mkdir -p "/srv/projects/git/grack/"
	cd "/srv/projects/git/grack/"
	git clone "https://github.com/ericpaulbishop/grack.git" 
	rm -rf "grack/.git"
	mv grack "$PROJ_ID"
	mkdir "$PROJ_ID/public"
	mkdir "$PROJ_ID/tmp"
	escaped_proj_root=$(echo "/srv/projects/git/repositories/$PROJ_ID.git" | sed 's/\//\\\//g')
	sed -i -e  "s/project_root.*\$/project_root => \"$escaped_proj_root\",/"             "$PROJ_ID/config.ru"
	sed -i -e  "s/use_redmine_auth.*=>.*\$/use_redmine_auth      => true,/"                  "$PROJ_ID/config.ru"
	sed -i -e  "s/redmine_db_type.*\$/redmine_db_type       => \"Mysql\",/"              "$PROJ_ID/config.ru"
	sed -i -e  "s/redmine_db_host.*\$/redmine_db_host       => \"localhost\",/"          "$PROJ_ID/config.ru"
	sed -i -e  "s/redmine_db_name.*\$/redmine_db_name       => \"$db\",/"                "$PROJ_ID/config.ru"
	sed -i -e  "s/redmine_db_user.*\$/redmine_db_user       => \"$db\",/"                "$PROJ_ID/config.ru"
	sed -i -e  "s/redmine_db_pass.*\$/redmine_db_pass       => \"$REDMINE_ADMIN_PW\",/"  "$PROJ_ID/config.ru"
	if [ "$FORCE_SSL_AUTH" = "1" ] ; then
		sed -i -e  "s/require_ssl_for_auth.*\$/require_ssl_for_auth  => true,/"      "$PROJ_ID/config.ru"
	else
		sed -i -e  "s/require_ssl_for_auth.*\$/require_ssl_for_auth  => false,/"     "$PROJ_ID/config.ru"
	fi
	chown -R www-data:www-data /srv/projects/git/grack


	#post-receive hook
	pr_file="/srv/projects/git/repositories/$PROJ_ID.git/hooks/post-receive"
	cat << EOF > "$pr_file"
	cd "/srv/projects/chili/$REDMINE_ID"
	ruby script/runner "Repository.fetch_changesets" -e production
EOF

	chmod    775 "$pr_file"
	chown git:www-data "$pr_file"

	cd "$curdir"

}

function enable_git_for_vhost
{
	local VHOST_ID=$1
	local PROJ_ID=$2
	local FORCE_GIT_SSL=$3

	#enable git in non-ssl vhost, if not forcing use of ssl vhost
	local vhost_root=$(cat "/etc/nginx/sites-available/$VHOST_ID" | grep -P "^[\t ]*root"  | awk ' { print $2 } ' | sed 's/;.*$//g')
	vhost_config="/etc/nginx/sites-available/$VHOST_ID"
	
	if [ "$FORCE_GIT_SSL" != "1" ] && [ "$FORCE_GIT_SSL" != "true" ] ; then
		mkdir -p "$vhost_root/git"
		ln -s "/srv/projects/git/grack/$PROJ_ID/public"  "$vhost_root/git/$PROJ_ID.git"
		nginx_add_passenger_uri_for_vhost "$vhost_config" "/git/$PROJ_ID.git"
	fi


	#enable git and git project in ssl vhost
	ssl_config="/etc/nginx/sites-available/$NGINX_SSL_ID"
	if [ ! -e "$ssl_config" ] ; then
		nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "/git/$PROJ_ID.git" "1"
	fi
	local ssl_root=$(cat "/etc/nginx/sites-available/$NGINX_SSL_ID" | grep -P "^[\t ]*root" | awk ' { print $2 } ' | sed 's/;.*$//g')
	mkdir -p "$ssl_root/git"
	ln -s "/srv/projects/git/grack/$PROJ_ID/public"   "$ssl_root/git/$PROJ_ID.git"
	nginx_add_passenger_uri_for_vhost "$ssl_config" "/git/$PROJ_ID.git"


	#if forcing ssl, create conf file that configures this to include
	nossl_include="$NGINX_CONF_PATH/${PROJ_ID}_${VHOST_ID}_git.conf"
	rm -rf "$nossl_conf"
	if [ "$FORCE_GIT_SSL" = "1" ] || [ "$FORCE_GIT_SSL" = "true" ] ; then
		cat << EOF >>"$nossl_include"
location ~ ^/$PROJ_ID/.*\$
{
	rewrite ^(.*)\$ https://\$host\$1 permanent;
}
EOF
	fi

	if [ -e "$nossl_include" ] ; then
		nginx_add_include_for_vhost "$vhost_config" "$nossl_include"
	fi

	/etc/init.d/nginx restart


}

