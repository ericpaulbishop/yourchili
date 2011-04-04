#!/bin/bash

#################
# ChiliProject  #
#################


function create_chili_project
{
	#arguments
	local DB_PASSWORD=$1               #root database password, necessary to create database
	local CHILI_ID=$2                  #id for chili installation, will be installed to /srv/projects/chili/$CHILI_ID
	local PROJ_ID=$3                   #id for project being created, this will appear in SCM URLs
	local IS_PUBLIC=$4                 #is this project publicly visible?  Can anyone grab the code?
	local SCM=$5                       #SCM to use, currently only "git" and "svn" are supported
	local PROJ_NAME=$6                 #project name, as it will appear in chili
	local CHILI_ADMIN_USER=$7          #chili admin user name
	local CHILI_ADMIN_PW=$8            #doubles as chili admin user pw & chili database pw
	local CHILI_ADMIN_FIRST=$9         #first name of chili admin user
	local CHILI_ADMIN_LAST=${10}       #last name of chili admin user
	local CHILI_ADMIN_EMAIL=${11}      #email of chili admin user
	local FORCE_SSL_AUTH=${12}         #return unauthorized if someone tries to perform password-protected operation over http and not https, only works when SCM=git

	local curdir=$(pwd)

	gem install -v=0.4.2 i18n
	gem install -v=2.3.5 rails


	#create chili database
	db="$CHILI_ID"_rm
	mysql_create_database "$DB_PASSWORD" "$db"
	mysql_create_user     "$DB_PASSWORD" "$db" "$CHILI_ADMIN_PW"
	mysql_grant_user      "$DB_PASSWORD" "$db" "$db"


	#In order to clone chili repo we need git,
	#and gitosis plugin gets installed even if we're using SVN
	#so just go ahead and install git & gitosis no matter what
	#does nothing if git/gitosis is already installed
	git_install
	gitosis_install

	#get chiliproject code
	mkdir -p /srv/projects/chili
	cd /srv/projects/chili
	git clone https://github.com/edavis10/chiliproject.git
	mv chiliproject "$CHILI_ID"
	cd "$CHILI_ID"
	git checkout "v1.2.0"
	rm -rf .git

	cat << EOF >config/database.yml
production:
  adapter: mysql
  database: $db
  host: localhost
  username: $db
  password: $CHILI_ADMIN_PW
EOF

	if [ -e config/initializers/session_store.rb ] ; then
		RAILS_ENV=production rake config/initializers/session_store.rb
	else
		rake generate_session_store
	fi
	RAILS_ENV=production rake db:migrate

	echo "en" | RAILS_ENV=production rake chiliproject:load_default_data
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
		create_git "$PROJ_ID" "$CHILI_ID" "$CHILI_ADMIN_PW" "$FORCE_SSL_AUTH"
		if [ "$is_public" = "true" ] ; then
			touch "/srv/projects/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
			chmod -R 775 "/srv/projects/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
			chown -R git:www-data "/srv/projects/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
		fi

	elif [ "$SCM" = "svn" ] || [ "SCM" = "subversion" ] ; then
		create_svn "$PROJ_ID" "$CHILI_ID" "$CHILI_ADMIN_PW" 
	else
		echo "not implemented yet"
		return 1
	fi



	#initialize chili project data with create.rb script
	cat << EOF >create.rb
# Adapted From: http://github.com/edavis10/redmine_data_generator/blob/37b8acb63a4302281641090949fb0cb87e8b1039/app/models/data_generator.rb#L36

require 'tmpdir'

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
					:firstname=>"$CHILI_ADMIN_FIRST",
					:lastname=>"$CHILI_ADMIN_LAST",
					:mail=>"$CHILI_ADMIN_EMAIL"
					)
@user.admin = true
@user.login = "$CHILI_ADMIN_USER"
@user.password = "$CHILI_ADMIN_PW"
@user.password_confirmation = "$CHILI_ADMIN_PW"
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
	git checkout 2011
	rm -rf .git
	sed -i -e  "s/'gitosisUrl.*\$/'gitosisUrl' => 'git@localhost:gitosis-admin.git',/"                                         "init.rb"
	sed -i -e  "s/'gitosisIdentityFile.*\$/'gitosisIdentityFile' => '\/srv\/projects\/chili\/$CHILI_ID\/.ssh\/id_rsa',/"   "init.rb"
	sed -i -e  "s/'basePath.*\$/'basePath' => '\/srv\/projects\/git\/repositories\/',/"                                        "init.rb"
	cp -r /root/.ssh "/srv/projects/chili/$CHILI_ID/"
	chown -R www-data:www-data "/srv/projects/chili/$CHILI_ID/"
	chmod 600 "/srv/projects/chili/$CHILI_ID/.ssh/id_rsa"
	cd "/srv/projects/chili/$CHILI_ID/"
	rake db:migrate_plugins RAILS_ENV=production


	#single project plugin
	#cd vendor/plugins
	#git clone https://github.com/ericpaulbishop/redmine_single_project.git
	#cd redmine_single_project
	#rm -rf .git
	#cd "/srv/projects/chili/$CHILI_ID/"

	#action_mailer_optional_tls plugin
	script/plugin install git://github.com/collectiveidea/action_mailer_optional_tls.git


	#themes
	git clone https://github.com/ericpaulbishop/redmine_theme_pack.git
	mkdir -p public/themes
	mv redmine_theme_pack/* public/themes/
	rm -rf redmine_theme_pack



	chown    www-data:www-data /srv/projects
	chown -R www-data:www-data /srv/projects/chili

	/etc/init.d/nginx restart
	
	cd "$curdir"

}


function add_chili_project
{
	#arguments
	local CHILI_ID=$1                  #id for redmine installation, will be installed to /srv/projects/redmine/$CHILI_ID
	local PROJ_ID=$2                     #id for project being created, this will appear in SCM URLs
	local IS_PUBLIC=$3                   #is this project publicly visible?  Can anyone grab the code?
	local SCM=$4                         #SCM to use, currently only "git" and "svn" are supported
	local PROJ_NAME=$5                   #project name, as it will appear in redmine
	local CHILI_ADMIN_USER=$6          #redmine admin user name, must already exist
	local CHILI_ADMIN_PW=$7            #doubles as redmine admin user pw & redmine database pw
	local FORCE_SSL_AUTH=$8              #return unauthorized if someone tries to perform password-protected operation over http and not https, only works when SCM=git
	
	
	local curdir=$(pwd)


	#cd to chili directory, crap out if it doesn't exist
	if [ ! -d "/srv/projects/chili/$CHILI_ID" ] ; then
		return 1 
	fi
	cd "/srv/projects/chili/$CHILI_ID"


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
		create_git "$PROJ_ID" "$CHILI_ID" "$CHILI_ADMIN_PW" "$FORCE_SSL_AUTH"
		if [ "$is_public" = "true" ] ; then
			touch "/srv/projects/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
			chmod -R 775 "/srv/projects/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
			chown -R git:www-data "/srv/projects/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
		fi

	elif [ "$SCM" = "svn" ] || [ "SCM" = "subversion" ] ; then
		create_svn "$PROJ_ID" "$CHILI_ID" "$CHILI_ADMIN_PW" 
	else
		echo "not implemented yet"
		return 1
	fi

	#add redmine project data with add.rb script
	cat << EOF >add.rb
# Adapted From: http://github.com/edavis10/redmine_data_generator/blob/37b8acb63a4302281641090949fb0cb87e8b1039/app/models/data_generator.rb#L36

require 'tmpdir'

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

@user = User.find(:first, :conditions=>"login = \"$CHILI_ADMIN_USER\"")


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






function enable_chili_for_vhost
{
	local VHOST_ID=$1
	local CHILI_ID=$2
	local FORCE_CHILI_SSL=$3
	local CHILI_IS_ROOT=$4
	

	vhost_domain=$(echo $VHOST_ID | sed 's/^www\.//g')
	gitosis_init="/srv/projects/chili/$CHILI_ID/vendor/plugins/redmine_gitosis/init.rb"
	public=""
	if [ -e "/srv/projects/chili/$CHILI_ID/is_public" ] ; then
		public=$(grep "true" "/srv/projects/chili/$CHILI_ID/is_public")
	fi
	if [ -n "$public" ] ; then
		sed -i -e  "s/'readOnlyBaseUrl.*\$/'readOnlyBaseUrls' => 'git:\/\/$vhost_domain\/,http:\/\/$vhost_domain\/git\/',/"  "$gitosis_init"
	else
		sed -i -e  "s/'readOnlyBaseUrl.*\$/'readOnlyBaseUrls' => '',/"                                                       "$gitosis_init"
	fi
	sed -i -e  "s/'developerBaseUrl.*\$/'developerBaseUrls' => 'git@$vhost_domain:,https:\/\/[user]@$vhost_domain\/git\/',/"     "$gitosis_init"



	#enable chili in non-ssl vhost, if not forcing use of ssl vhost
	local vhost_root=$(cat "/etc/nginx/sites-available/$VHOST_ID" | grep -P "^[\t ]*root"  | awk ' { print $2 } ' | sed 's/;.*$//g')
	vhost_config="/etc/nginx/sites-available/$VHOST_ID"
	
	if [ "$FORCE_CHILI_SSL" != "1" ] && [ "$FORCE_CHILI_SSL" != "true" ] ; then
		ln -s "/srv/projects/chili/$CHILI_ID/public"  "$vhost_root/$CHILI_ID"
		nginx_add_passenger_uri_for_vhost "$vhost_config" "/$CHILI_ID"
	fi


	#enable chili and git project in ssl vhost
	ssl_config="/etc/nginx/sites-available/$NGINX_SSL_ID"
	if [ ! -e "$ssl_config" ] ; then
		nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "/$CHILI_ID" "1"
	fi
	local ssl_root=$(cat "/etc/nginx/sites-available/$NGINX_SSL_ID" | grep -P "^[\t ]*root" | awk ' { print $2 } ' | sed 's/;.*$//g')
	ln -s "/srv/projects/chili/$CHILI_ID/public"   "$ssl_root/$CHILI_ID"
	nginx_add_passenger_uri_for_vhost "$ssl_config" "/$CHILI_ID"

	

	# setup nossl_include
	nossl_include="$NGINX_CONF_PATH/${CHILI_ID}_${VHOST_ID}_chili.conf"
	rm -rf "$nossl_include"
	if [ "$FORCE_CHILI_SSL" = "1" ] || [ "$FORCE_CHILI_SSL" = "true" ] ; then
		cat << EOF >>"$nossl_include"
location ~ ^/$CHILI_ID/.*\$
{
	rewrite ^(.*)\$ https://\$host\$1 permanent;
}
EOF
	fi
	if [ "$CHILI_IS_ROOT" = "1" ] || [ "$CHILI_IS_ROOT" = "true" ]; then
		cat << EOF >>"$nossl_include"
location ~ ^/(index\..*)?$
{
	rewrite ^(.*)\$ /${CHILI_ID} permanent;
}
EOF
	fi

	if [ -e "$nossl_include" ] ; then
		nginx_add_include_for_vhost "$vhost_config" "$nossl_include"
	fi

	/etc/init.d/nginx restart

}
