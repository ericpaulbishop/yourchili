#!/bin/bash



#####################################
# Git / Gitosis / Grack / Redmine   #
#####################################


function git_install
{

	if [ ! -e /usr/local/libexec/git-core/git ] ; then
		local curdir=$(pwd)
		
		aptitude install -y tk8.4 libcurl
		rm -rf /tmp/git
		mkdir -p /tmp/git
		cd /tmp/git
		wget http://www.kernel.org/pub/software/scm/git/git-1.7.1.tar.bz2 
		tar xjf *.tar.bz2
		cd git-1.7.1
		./configure
		make install
		
		cd "$curdir"
		rm -rf /tmp/git
	fi

}

function gitosis_install
{

	git_install

	if [ ! -d "/srv/projects/git" ] ; then
		local curdir=$(pwd)
		
		cd /tmp
		git clone git://eagain.net/gitosis.git
		cd gitosis
		aptitude -y install python-setuptools
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
			printf "/root/.ssh/id_rsa\n\n\n\n\n" | ssh-keygen -t rsa 
		fi
		sudo -H -u git gitosis-init < /root/.ssh/id_rsa.pub
		chmod -R 775 /srv/projects/git/repositories
		
		cd "$curdir"
		rm -rf /tmp/gitosis
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
	sed -i -e  "s/use_redmine_auth.*\$/use_redmine_auth      => true,/"                  "$PROJ_ID/config.ru"
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
	cd "/srv/projects/redmine/$REDMINE_ID"
	ruby script/runner "Repository.fetch_changesets" -e production
EOF

	chmod    775 "$pr_file"
	chown git:www-data "$pr_file"

	cd "$curdir"

}

function create_svn
{
	local PROJ_ID=$1
	local REDMINE_ID=$2
	local REDMINE_ADMIN_PW=$3

	local curdir=$(pwd)


	#does nothing if svn is already installed
	install_svn

	#create svn repository
	svnadmin create "/srv/projects/svn/$PROJ_ID"


	#initialize SVN structure
	cd /tmp
	svn checkout  "file:///srv/projects/svn/$PROJ_ID/"
	cd "$PROJ_ID"
	mkdir branches tags trunk
	svn add branches tags trunk
	svn commit -m "Create Initial Repository Structure"
	cd ..
	rm -rf "$PROJ_ID"

	chown -R www-data:www-data /srv/projects/svn

	db="$REDMINE_ID"_rm
	better_redmine_auth_pm
	cat << EOF >"/etc/apache2/sites-available/auth_$PROJ_ID"
PerlLoadModule Apache::Authn::Redmine
<Location /svn/$PROJ_ID>
	DAV               svn
	SVNPath           /srv/projects/svn/$PROJ_ID
	Order             deny,allow
	Deny from         all
	Satisfy           any
	PerlAccessHandler Apache::Authn::Redmine::access_handler	
	PerlAuthenHandler Apache::Authn::Redmine::authen_handler
	AuthType          Basic
	AuthName	  "$PROJ_ID SVN Repository"


	Require           valid-user
	RedmineDSN        "DBI:mysql:database=$db;host=localhost"
	RedmineDbUser     "$db"
	RedmineDbPass     "$REDMINE_ADMIN_PW"

</Location>
EOF
	a2ensite "auth_$PROJ_ID"
	/etc/init.d/apache2 restart




	cd "$curdir"
}


function create_redmine_project
{
	#arguments
	local DB_PASSWORD=$1                 #root database password, necessary to create database
	local REDMINE_ID=$2                  #id for redmine installation, will be installed to /srv/projects/redmine/$REDMINE_ID
	local PROJ_ID=$3                     #id for project being created, this will appear in SCM URLs
	local IS_PUBLIC=$4                   #is this project publicly visible?  Can anyone grab the code?
	local SCM=$5                         #SCM to use, currently only "git" and "svn" are supported
	local PROJ_NAME=$6                   #project name, as it will appear in redmine
	local REDMINE_ADMIN_USER=$7          #redmine admin user name
	local REDMINE_ADMIN_PW=$8            #doubles as redmine admin user pw & redmine database pw
	local REDMINE_ADMIN_FIRST=$9         #first name of redmine admin user
	local REDMINE_ADMIN_LAST=${10}       #last name of redmine admin user
	local REDMINE_ADMIN_EMAIL=${11}      #email of redmine admin user
	local FORCE_SSL_AUTH=${12}           #return unauthorized if someone tries to perform password-protected operation over http and not https, only works when SCM=git

	local curdir=$(pwd)

	#create redmine database
	db="$REDMINE_ID"_rm
	mysql_create_database "$DB_PASSWORD" "$db"
	mysql_create_user     "$DB_PASSWORD" "$db" "$REDMINE_ADMIN_PW"
	mysql_grant_user      "$DB_PASSWORD" "$db" "$db"


	#In order to clone redmine repo we need git,
	#and gitosis plugin gets installed even if we're using SVN
	#so just go ahead and install git & gitosis no matter what
	#does nothing if git/gitosis is already installed
	git_install
	gitosis_install

	#redmine
	mkdir -p /srv/projects/redmine
	cd /srv/projects/redmine
	git clone https://github.com/edavis10/redmine.git
	mv redmine "$REDMINE_ID"
	cd "$REDMINE_ID"
	git checkout "0.9-stable"
	rm -rf .git

	cat << EOF >config/database.yml
production:
  adapter: mysql
  database: $db
  host: localhost
  username: $db
  password: $REDMINE_ADMIN_PW
EOF

	if [ -e config/initializers/session_store.rb ] ; then
		RAILS_ENV=production rake config/initializers/session_store.rb
	else
		rake generate_session_store
	fi
	RAILS_ENV=production rake db:migrate
	echo "en" | RAILS_ENV=production rake redmine:load_default_data
	mkdir tmp public/plugin_assets
	sudo chmod -R 755 files log tmp public/plugin_assets

	is_public="false"
	if [ "$IS_PUBLIC" == 1 ] || [ "$IS_PUBLIC" == "true" ] ; then
		is_public="true"
		echo "$is_public" > "is_public"
	fi
	chmod -R 775 log  #for git, when hook is called both git and www-data users (which are in the same www-data group) need write access to log directory





	#SCM stuff
	if [ "$SCM" = "git" ] ; then
		 create_git "$PROJ_ID" "$REDMINE_ID" "$REDMINE_ADMIN_PW" "$FORCE_SSL_AUTH"
	
	elif [ "$SCM" = "svn" ] || [ "SCM" = "subversion" ] ; then
		create_svn "$PROJ_ID" "$REDMINE_ID" "$REDMINE_ADMIN_PW" 
	else
		echo "not implemented yet"
		return 1
	fi



	#initialize redmine project data with create.rb script
	cat << EOF >create.rb
# Adapted From: http://github.com/edavis10/redmine_data_generator/blob/37b8acb63a4302281641090949fb0cb87e8b1039/app/models/data_generator.rb#L36
project = Project.create(
					:name => "$PROJ_NAME",
					:description => "",
					:identifier => "$PROJ_ID",
					:is_public =>$is_public
					)
EOF

	if [ "$SCM" = "git" ] ; then
		cat << EOF >>create.rb
repo = Repository::Git.create(
					:project_id=>project.id,
					:url=>"/srv/projects/git/repositories/$PROJ_ID.git"
					)
EOF
	elif [ "$SCM" = "svn" ] || [ "$SCM" = "subversion" ] ; then
			cat << EOF >>create.rb
repo = Repository::Subversion.create(
					:project_id=>project.id,
					:url=>"file:///srv/projects/svn/$PROJ_ID"
					)
EOF
	fi

	cat << EOF >>create.rb

project.enabled_module_names=(["repository", "issue_tracking"])
project.trackers = Tracker.all
project.save


@user = User.new( 
					:language => Setting.default_language,
					:firstname=>"$REDMINE_ADMIN_FIRST",
					:lastname=>"$REDMINE_ADMIN_LAST",
					:mail=>"$REDMINE_ADMIN_EMAIL"
					)
@user.admin = true
@user.login = "$REDMINE_ADMIN_USER"
@user.password = "$REDMINE_ADMIN_PW"
@user.password_confirmation = "$REDMINE_ADMIN_PW"
@user.save

@membership = Member.new(
			:principal=>@user,
			:project_id=>project.id,
			:role_ids=>[3]
			)
@membership.save


anon = Role.anonymous
nonm = Role.non_member
anon.add_permission!( "add_issues" )
nonm.add_permission!( "add_issues" )


closedIssueStatus = IssueStatus.find(:first, :conditions=>"name = \"Closed\"")
if(defined?(closedIssueStatus['id']))
	Setting.commit_fix_status_id = closedIssueStatus['id']
end

EOF



	#delete original admin user & update info by running create script
	echo "DELETE FROM users WHERE login=\"admin\" ; " | mysql -u root -p"$DB_PASSWORD" "$db"
	ruby script/console production < create.rb
	rm -rf create.rb


	
	#gitosis plugin
	cd vendor/plugins
	git clone https://github.com/ericpaulbishop/redmine_gitosis.git
	cd redmine_gitosis
	rm -rf .git
	sed -i -e  "s/'gitosisUrl.*\$/'gitosisUrl' => 'git@localhost:gitosis-admin.git',/"                                         "init.rb"
	sed -i -e  "s/'gitosisIdentityFile.*\$/'gitosisIdentityFile' => '\/srv\/projects\/redmine\/$REDMINE_ID\/.ssh\/id_rsa',/"   "init.rb"
	sed -i -e  "s/'developerBaseUrl.*\$/'developerBaseUrl' => 'git@localhost:',/"                                              "init.rb"
	sed -i -e  "s/'basePath.*\$/'basePath' => '\/srv\/projects\/git\/repositories\/',/"                                        "init.rb"
	cp -r ~/.ssh "/srv/projects/redmine/$REDMINE_ID/"
	chown -R www-data:www-data "/srv/projects/redmine/$REDMINE_ID/"
	chmod 600 "/srv/projects/redmine/$REDMINE_ID/.ssh/id_rsa"
	cd "/srv/projects/redmine/$REDMINE_ID/"
	rake db:migrate_plugins RAILS_ENV=production


	#single project plugin
	cd vendor/plugins
	git clone https://github.com/ericpaulbishop/redmine_single_project.git
	cd redmine_single_project
	rm -rf .git
	cd "/srv/projects/redmine/$REDMINE_ID/"


	chown    www-data:www-data /srv/projects
	chown -R www-data:www-data /srv/projects/redmine

	/etc/init.d/nginx restart
	
	cd "$curdir"

}

function create_git_project
{
	#arguments
	local DB_PASSWORD="$1"
	local PROJ_NAME="$2"
	local ANONYMOUS_CHECKOUT="$3"
	local PROJ_USER_ID="$4"
	local PROJ_PW="$5"
	local PROJ_USER_FIRST="$6"
	local PROJ_USER_LAST="$7"
	local PROJ_USER_EMAIL="$8"
	local FORCE_SSL_AUTH="$9"	


	local curdir=$(pwd)


	db="$PROJ_NAME"_rm
	mysql_create_database "$DB_PASSWORD" "$db"
	mysql_create_user     "$DB_PASSWORD" "$db" "$PROJ_PW"
	mysql_grant_user      "$DB_PASSWORD" "$db" "$db"



	#does nothing if git/gitosis is already installed
	git_install
	gitosis_install

	#create git repository
	mkdir -p "/srv/projects/git/repositories/$PROJ_NAME.git"
	cd "/srv/projects/git/repositories/$PROJ_NAME.git"
	git init --bare
	chmod -R 775 /srv/projects/git/repositories/
	chown -R git:www-data /srv/projects/git/repositories/

	

	#install and configure grack
	mkdir -p "/srv/projects/git/grack/"
	cd "/srv/projects/git/grack/"
	git clone "https://github.com/ericpaulbishop/grack.git" 
	rm -rf "grack/.git"
	mv grack "$PROJ_NAME"
	mkdir "$PROJ_NAME/public"
	mkdir "$PROJ_NAME/tmp"
	escaped_proj_root=$(echo "/srv/projects/git/repositories/$PROJ_NAME.git" | sed 's/\//\\\//g')
	sed -i -e  "s/project_root.*\$/project_root => \"$escaped_proj_root\",/"          "$PROJ_NAME/config.ru"
	sed -i -e  "s/use_redmine_auth.*\$/use_redmine_auth      => true,/"               "$PROJ_NAME/config.ru"
	sed -i -e  "s/redmine_db_type.*\$/redmine_db_type       => \"Mysql\",/"           "$PROJ_NAME/config.ru"
	sed -i -e  "s/redmine_db_host.*\$/redmine_db_host       => \"localhost\",/"       "$PROJ_NAME/config.ru"
	sed -i -e  "s/redmine_db_name.*\$/redmine_db_name       => \"$db\",/"             "$PROJ_NAME/config.ru"
	sed -i -e  "s/redmine_db_user.*\$/redmine_db_user       => \"$db\",/"             "$PROJ_NAME/config.ru"
	sed -i -e  "s/redmine_db_pass.*\$/redmine_db_pass       => \"$PROJ_PW\",/"        "$PROJ_NAME/config.ru"
	if [ "$FORCE_SSL_AUTH" = "1" ] ; then
		sed -i -e  "s/require_ssl_for_auth.*\$/require_ssl_for_auth  => true,/"   "$PROJ_NAME/config.ru"
	else
		sed -i -e  "s/require_ssl_for_auth.*\$/require_ssl_for_auth  => false,/"  "$PROJ_NAME/config.ru"
	fi
	chown -R www-data:www-data /srv/projects/git/grack 

	

	#redmine
	mkdir -p /srv/projects/redmine
	cd /srv/projects/redmine
	git clone https://github.com/edavis10/redmine.git
	mv redmine "$PROJ_NAME"
	cd "$PROJ_NAME"
	git checkout "0.9-stable"
	rm -rf .git

	cat << EOF >config/database.yml
production:
  adapter: mysql
  database: $db
  host: localhost
  username: $db
  password: $PROJ_PW
EOF

	if [ -e config/initializers/session_store.rb ] ; then
		RAILS_ENV=production rake config/initializers/session_store.rb
	else
		rake generate_session_store
	fi
	RAILS_ENV=production rake db:migrate
	echo "en" | RAILS_ENV=production rake redmine:load_default_data
	mkdir tmp public/plugin_assets
	sudo chmod -R 755 files log tmp public/plugin_assets

	is_public="false"
	if [ "$ANONYMOUS_CHECKOUT" == 1 ] || [ "$ANONYMOUS_CHECKOUT" == "true" ] ; then
		is_public="true"
		echo "$is_public" > "is_public"
	fi


	#initialize redmine project data with create.rb script
	cat << EOF >create.rb
# Adapted From: http://github.com/edavis10/redmine_data_generator/blob/37b8acb63a4302281641090949fb0cb87e8b1039/app/models/data_generator.rb#L36
project = Project.create(
					:name => "$PROJ_NAME",
					:description => "",
					:identifier => "$PROJ_NAME",
					:is_public =>$is_public
					)

repo = Repository::Git.create(
					:project_id=>project.id,
					:url=>"/srv/projects/git/repositories/$PROJ_NAME.git"
					)

project.enabled_module_names=(["repository", "issue_tracking"])
project.trackers = Tracker.all
project.save


@user = User.new( 
					:language => Setting.default_language,
					:firstname=>"$PROJ_USER_FIRST",
					:lastname=>"$PROJ_USER_LAST",
					:mail=>"$PROJ_USER_EMAIL"
					)
@user.admin = true
@user.login = "$PROJ_USER_ID"
@user.password = "$PROJ_PW"
@user.password_confirmation = "$PROJ_PW"
@user.save

@membership = Member.new(
			:principal=>@user,
			:project_id=>project.id,
			:role_ids=>[3]
			)
@membership.save


anon = Role.anonymous
nonm = Role.non_member
anon.add_permission!( "add_issues" )
nonm.add_permission!( "add_issues" )


closedIssueStatus = IssueStatus.find(:first, :conditions=>"name = \"Closed\"")
if(defined?(closedIssueStatus['id']))
	Setting.commit_fix_status_id = closedIssueStatus['id']
end

EOF



	#delete original admin user & update info by running create script
	echo "DELETE FROM users WHERE login=\"admin\" ; " | mysql -u root -p"$DB_PASSWORD" "$db"
	ruby script/console production < create.rb
	rm -rf create.rb


	#post-receive hook
	pr_file="/srv/projects/git/repositories/$PROJ_NAME.git/hooks/post-receive"
	cat << EOF > "$pr_file"
	cd "/srv/projects/redmine/$PROJ_NAME"
	ruby script/runner "Repository.fetch_changesets" -e production
EOF

	chmod -R 775 log #when hook is called, both git and www-data need write access to log directory
	chmod    775 "$pr_file"
	chown git:www-data "$pr_file"



	#gitosis plugin
	cd vendor/plugins
	git clone https://github.com/ericpaulbishop/redmine_gitosis.git
	cd redmine_gitosis
	rm -rf .git
	sed -i -e  "s/'gitosisUrl.*\$/'gitosisUrl' => 'git@localhost:gitosis-admin.git',/"                                         "init.rb"
	sed -i -e  "s/'gitosisIdentityFile.*\$/'gitosisIdentityFile' => '\/srv\/projects\/redmine\/$PROJ_NAME\/.ssh\/id_rsa',/"    "init.rb"
	sed -i -e  "s/'developerBaseUrl.*\$/'developerBaseUrl' => 'git@localhost:',/"                                              "init.rb"
	sed -i -e  "s/'basePath.*\$/'basePath' => '\/srv\/projects\/git\/repositories\/',/"                                        "init.rb"
	cp -r ~/.ssh "/srv/projects/redmine/$PROJ_NAME/"
	chown -R www-data:www-data "/srv/projects/redmine/$PROJ_NAME/"
	chmod 600 "/srv/projects/redmine/$PROJ_NAME/.ssh/id_rsa"
	cd "/srv/projects/redmine/$PROJ_NAME/"
	rake db:migrate_plugins RAILS_ENV=production


	#single project plugin
	cd vendor/plugins
	git clone https://github.com/ericpaulbishop/redmine_single_project.git
	cd redmine_single_project
	rm -rf .git
	cd "/srv/projects/redmine/$PROJ_NAME/"


	chown    www-data:www-data /srv/projects
	chown -R www-data:www-data /srv/projects/redmine

	/etc/init.d/nginx restart
	
	cd "$curdir"

}



function enable_git_project_for_vhost
{
	local VHOST_ID=$1
	local PROJ_ID=$2
	local REDMINE_ID=$3
	local FORCE_GIT_SSL=$4
	local FORCE_REDMINE_SSL=$5
	local REDMINE_IS_ROOT=$6

	gitosis_init="/srv/projects/redmine/$REDMINE_ID/vendor/plugins/redmine_gitosis/init.rb"
	public=""
	if [ -e "/srv/projects/redmine/$REDMINE_ID/is_public" ] ; then
		public=$(grep "true" "/srv/projects/redmine/$REDMINE_ID/is_public")
	fi
	if [ -n "$public" ] ; then
		sed -i -e  "s/'readOnlyBaseUrl.*\$/'readOnlyBaseUrls' => ['http:\/\/$VHOST_ID\/git\/'],/"                     "$gitosis_init"
	else
		sed -i -e  "s/'readOnlyBaseUrl.*\$/'readOnlyBaseUrls' => [],/"                                                "$gitosis_init"
	fi
	sed -i -e  "s/'developerBaseUrl.*\$/'developerBaseUrls' => ['git@$VHOST_ID:','https:\/\/[user]@$VHOST_ID\/git\/'],/"  "$gitosis_init"

	
	
	#enable redmine and git in non-ssl vhost, if not forcing use of ssl vhost
	local vhost_root=$(cat "/etc/nginx/sites-available/$VHOST_ID" | grep -P "^[\t ]*root"  | awk ' { print $2 } ' | sed 's/;.*$//g')
	cat "/etc/nginx/sites-available/$VHOST_ID" | grep -v "passenger_base_uri.*$REDMINE_ID;" | grep -v "passenger_base_uri.*$PROJ_ID.git;"  > "/etc/nginx/sites-available/$VHOST_ID.tmp" 
	if [ "$FORCE_REDMINE_SSL" != "1" ] || [ "$FORCE_GIT_SSL" != "1" ] ; then
		
		
		if [ "$FORCE_REDMINE_SSL" != "1" ] &&  [ "$FORCE_GIT_SSL" != "1" ]  ; then
			mkdir -p "$vhost_root/git"
			ln -s "/srv/projects/git/grack/$PROJ_ID/public" "$vhost_root/git/$PROJ_ID.git"
			ln -s "/srv/projects/redmine/$REDMINE_ID/public"   "$vhost_root/$REDMINE_ID"
			cat   "/etc/nginx/sites-available/$VHOST_ID.tmp" | sed -e "s/^.*passenger_enabled.*\$/\tpassenger_enabled   on;\n\tpassenger_base_uri  \/$REDMINE_ID;\n\tpassenger_base_uri  \/git\/$PROJ_ID.git;/g"  > "/etc/nginx/sites-available/$VHOST_ID"
		elif [ "$FORCE_REDMINE_SSL" != "1" ] ; then
			ln -s "/srv/projects/redmine/$REDMINE_ID/public"  "$vhost_root/$REDMINE_ID"
			cat   "/etc/nginx/sites-available/$VHOST_ID.tmp" | sed -e "s/^.*passenger_enabled.*\$/\tpassenger_enabled   on;\n\tpassenger_base_uri  \/$REDMINE_ID;/g"  > "/etc/nginx/sites-available/$VHOST_ID"
		elif [ "$FORCE_REDMINE_SSL" != "1" ] ; then
			mkdir -p "$vhost_root/git"
			ln -s "/srv/projects/git/grack/$PROJ_ID/public" "$vhost_root/git/$PROJ_ID.git"
			cat   "/etc/nginx/sites-available/$VHOST_ID.tmp" | sed -e "s/^.*passenger_enabled.*\$/\tpassenger_enabled   on;\n\tpassenger_base_uri  \/git\/$PROJ_ID.git;/g"  > "/etc/nginx/sites-available/$VHOST_ID"
		fi
	fi
	rm -rf "/etc/nginx/sites-available/$VHOST_ID.tmp" 


	#enable redmine and git project in ssl vhost
	if [ -z "/etc/nginx/sites-available/$NGINX_SSL_ID" ] ; then
		nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "/$REDMINE_ID" "1"
	fi
	local ssl_root=$(cat "/etc/nginx/sites-available/$NGINX_SSL_ID" | grep -P "^[\t ]*root" | awk ' { print $2 } ' | sed 's/;.*$//g')
	mkdir -p "$ssl_root/git"
	ln -s "/srv/projects/git/grack/$PROJ_ID/public" "$ssl_root/git/$PROJ_ID.git"
	ln -s "/srv/projects/redmine/$REDMINE_ID/public"   "$ssl_root/$REDMINE_ID"

	cat "/etc/nginx/sites-available/$NGINX_SSL_ID" | grep -v "passenger_base_uri.*$REDMINE_ID;" | grep -v "passenger_base_uri.*$PROJ_ID.git;" > "/etc/nginx/sites-available/$NGINX_SSL_ID.tmp" 
	cat "/etc/nginx/sites-available/$NGINX_SSL_ID.tmp" | sed -e "s/^.*passenger_enabled.*\$/\tpassenger_enabled   on;\n\tpassenger_base_uri  \/$REDMINE_ID;\n\tpassenger_base_uri  \/git\/$PROJ_ID.git;/g"  > "/etc/nginx/sites-available/$NGINX_SSL_ID"
	rm -rf "/etc/nginx/sites-available/$NGINX_SSL_ID.tmp" 

	# setup nossl_include
	rm -rf "/$NGINX_CONF_PATH/${PROJ_ID}_project_nossl.conf"
	if [ "$FORCE_GIT_SSL" = "1" ] ; then
		cat << EOF >>"$NGINX_CONF_PATH/${PROJ_ID}_project_nossl.conf"
	location ~ ^/git/.*\$
	{
 		rewrite ^(.*)\$ https://\$host\$1 permanent;
	}
EOF
	fi

	if [ "$FORCE_REDMINE_SSL" = "1" ] ; then
		cat << EOF >>"$NGINX_CONF_PATH/${PROJ_ID}_project_nossl.conf"
	location ~ ^/$REDMINE_ID/.*\$
	{
 		rewrite ^(.*)\$ https://\$host\$1 permanent;
	}
EOF
	fi


	if [ "REDMINE_IS_ROOT" = "1" ] ; then
		cat << EOF >>"$NGINX_CONF_PATH/${PROJ_ID}_project_nossl.conf"
	location /
	{
 		rewrite ^(.*)\$ /${REDMINE_ID} permanent;
	}
EOF

	fi


	#if nossl_include exists, add to vhost
	if [ -e "$NGINX_CONF_PATH/${PROJ_ID}_project_nossl.conf" ] ; then
		cat "/etc/nginx/sites-available/$VHOST_ID" | grep -v "^}" | grep -v "include.*${PROJ_ID}_project_nossl.conf;" >"/etc/nginx/sites-available/$VHOST_ID.tmp" 
		cat << EOF >>/etc/nginx/sites-available/$VHOST_ID.tmp
		include $NGINX_CONF_PATH/${PROJ_ID}_project_nossl.conf;
}
EOF
		mv "/etc/nginx/sites-available/$VHOST_ID.tmp" "/etc/nginx/sites-available/$VHOST_ID"
	fi

	
	chown -R www-data:www-data /srv/www

	/etc/init.d/nginx restart
	
	
}


