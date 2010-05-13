#!/bin/bash

############
# Redmine  #
############


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


	# save whether we have a public project here 
	# yes, this should be on a per-project basis, but
	# this only matters for display of urls in gitosis plugin, so
	# it's not that big a deal and can easily be changed later
	is_public="false"
	if [ "$IS_PUBLIC" == 1 ] || [ "$IS_PUBLIC" == "true" ] ; then
		is_public="true"
		echo "$is_public" > "is_public"
	fi


	# for git, when hook is called both git and www-data users 
	# (which are in the same www-data group) need write access to log directory
	chmod -R 775 log  





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


function add_redmine_project
{
	#arguments
	local REDMINE_ID=$1                  #id for redmine installation, will be installed to /srv/projects/redmine/$REDMINE_ID
	local PROJ_ID=$2                     #id for project being created, this will appear in SCM URLs
	local IS_PUBLIC=$3                   #is this project publicly visible?  Can anyone grab the code?
	local SCM=$4                         #SCM to use, currently only "git" and "svn" are supported
	local PROJ_NAME=$5                   #project name, as it will appear in redmine
	local REDMINE_ADMIN_USER=$6          #redmine admin user name, must already exist
	local REDMINE_ADMIN_PW=$7            #doubles as redmine admin user pw & redmine database pw
	local FORCE_SSL_AUTH=$8              #return unauthorized if someone tries to perform password-protected operation over http and not https, only works when SCM=git
	
	
	local curdir=$(pwd)


	#cd to redmine directory, crap out if it doesn't exist
	if [ ! -d "/srv/projects/redmine/$REDMINE_ID" ] ; then
		return 1 
	fi
	cd "/srv/projects/redmine/$REDMINE_ID"


	# save whether we have a public project here 
	# yes, this should be on a per-project basis, but
	# this only matters for display of urls in gitosis plugin, so
	# it's not that big a deal and can easily be changed later
	is_public="false"
	if [ "$IS_PUBLIC" == 1 ] || [ "$IS_PUBLIC" == "true" ] ; then
		is_public="true"
		echo "$is_public" > "is_public"
	fi


	# for git, when hook is called both git and www-data users 
	# (which are in the same www-data group) need write access to log directory
	chmod -R 775 log  



	#SCM stuff
	if [ "$SCM" = "git" ] ; then
		 create_git "$PROJ_ID" "$REDMINE_ID" "$REDMINE_ADMIN_PW" "$FORCE_SSL_AUTH"
	
	elif [ "$SCM" = "svn" ] || [ "SCM" = "subversion" ] ; then
		create_svn "$PROJ_ID" "$REDMINE_ID" "$REDMINE_ADMIN_PW" 
	else
		echo "not implemented yet"
		return 1
	fi

	#add redmine project data with add.rb script
	cat << EOF >add.rb
# Adapted From: http://github.com/edavis10/redmine_data_generator/blob/37b8acb63a4302281641090949fb0cb87e8b1039/app/models/data_generator.rb#L36
project = Project.create(
					:name => "$PROJ_NAME",
					:description => "",
					:identifier => "$PROJ_ID",
					:is_public =>$is_public
					)
EOF

	if [ "$SCM" = "git" ] ; then
		cat << EOF >>add.rb
repo = Repository::Git.create(
					:project_id=>project.id,
					:url=>"/srv/projects/git/repositories/$PROJ_ID.git"
					)
EOF
	elif [ "$SCM" = "svn" ] || [ "$SCM" = "subversion" ] ; then
			cat << EOF >>add.rb
repo = Repository::Subversion.create(
					:project_id=>project.id,
					:url=>"file:///srv/projects/svn/$PROJ_ID"
					)
EOF
	fi

	cat << EOF >>add.rb

project.enabled_module_names=(["repository", "issue_tracking"])
project.trackers = Tracker.all
project.save

@user = User.find(:first, :conditions=>"login = \"$REDMINE_ADMIN_USER\"")


@membership = Member.new(
			:principal=>@user,
			:project_id=>project.id,
			:role_ids=>[3]
			)
@membership.save

EOF
	ruby script/console production < add.rb
	rm -rf add.rb


	/etc/init.d/nginx restart

	cd "$curdir"

}






function enable_redmine_for_vhost
{
	local VHOST_ID=$1
	local REDMINE_ID=$2
	local FORCE_REDMINE_SSL=$3
	local REDMINE_IS_ROOT=$4
	
	gitosis_init="/srv/projects/redmine/$REDMINE_ID/vendor/plugins/redmine_gitosis/init.rb"
	public=""
	if [ -e "/srv/projects/redmine/$REDMINE_ID/is_public" ] ; then
		public=$(grep "true" "/srv/projects/redmine/$REDMINE_ID/is_public")
	fi
	if [ -n "$public" ] ; then
		sed -i -e  "s/'readOnlyBaseUrl.*\$/'readOnlyBaseUrls' => 'http:\/\/$VHOST_ID\/git\/',/"                    "$gitosis_init"
	else
		sed -i -e  "s/'readOnlyBaseUrl.*\$/'readOnlyBaseUrls' => '',/"                                             "$gitosis_init"
	fi
	sed -i -e  "s/'developerBaseUrl.*\$/'developerBaseUrls' => 'git@$VHOST_ID:,https:\/\/[user]@$VHOST_ID\/git\/',/"  "$gitosis_init"



	#enable redmine in non-ssl vhost, if not forcing use of ssl vhost
	local vhost_root=$(cat "/etc/nginx/sites-available/$VHOST_ID" | grep -P "^[\t ]*root"  | awk ' { print $2 } ' | sed 's/;.*$//g')
	vhost_config="/etc/nginx/sites-available/$VHOST_ID"
	
	if [ "$FORCE_REDMINE_SSL" != "1" ] && [ "$FORCE_REDMINE_SSL" != "true" ] ; then
		ln -s "/srv/projects/redmine/$REDMINE_ID/public"  "$vhost_root/$REDMINE_ID"
		nginx_add_passenger_uri_for_vhost "$vhost_config" "/$REDMINE_ID"
	fi


	#enable redmine and git project in ssl vhost
	ssl_config="/etc/nginx/sites-available/$NGINX_SSL_ID"
	if [ ! -e "$ssl_config" ] ; then
		nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "/$REDMINE_ID" "1"
	fi
	local ssl_root=$(cat "/etc/nginx/sites-available/$NGINX_SSL_ID" | grep -P "^[\t ]*root" | awk ' { print $2 } ' | sed 's/;.*$//g')
	ln -s "/srv/projects/redmine/$REDMINE_ID/public"   "$ssl_root/$REDMINE_ID"
	nginx_add_passenger_uri_for_vhost "$ssl_config" "/$REDMINE_ID"

	

	# setup nossl_include
	nossl_include="$NGINX_CONF_PATH/${REDMINE_ID}_${VHOST_ID}_redmine.conf"
	rm -rf "$nossl_include"
	if [ "$FORCE_REDMINE_SSL" = "1" ] || [ "$FORCE_REDMINE_SSL" = "true" ] ; then
		cat << EOF >>"$nossl_include"
location ~ ^/$REDMINE_ID/.*\$
{
	rewrite ^(.*)\$ https://\$host\$1 permanent;
}
EOF
	fi
	if [ "$REDMINE_IS_ROOT" = "1" ] || [ "$REDMINE_IS_ROOT" = "true" ]; then
		cat << EOF >>"$nossl_include"
location ~ ^/(index\..*)?$
{
	rewrite ^(.*)\$ /${REDMINE_ID} permanent;
}
EOF
	fi

	if [ -e "$nossl_include" ] ; then
		nginx_add_include_for_vhost "$vhost_config" "$nossl_include"
	fi

	/etc/init.d/nginx restart

}
