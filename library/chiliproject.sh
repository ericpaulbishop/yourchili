#!/bin/bash

#################
# ChiliProject  #
#################


function install_chili_project
{
	#arguments
	local CHILI_VHOST=$1 ; shift ;
	local CHILI_VHOST_SUBDIR=$1 ; shift ;
	
	local USE_SSL=$1 ; shift ;
	local FORCE_SSL=$1 ; shift ;
	local SSL_VHOST_SUBDIR=$1 ; shift ;
	
	local DB_TYPE=$1 ; shift ;		  # "mysql" or "postresql"	
	local DB_PASSWORD=$1 ; shift ;            # mysql root database password, necessary to create database if DB_TYPE=mysql

	local CHILI_IS_PUBLIC=$1 ; shift ;
	local CHILI_ADMIN_USER=$1 ; shift ;       #chili admin user name
	local CHILI_ADMIN_PW=$1 ; shift ;         #doubles as chili admin user pw & chili database pw
	local CHILI_ADMIN_FIRST=$1 ; shift ;      #first name of chili admin user
	local CHILI_ADMIN_LAST=$1 ; shift ;       #last name of chili admin user
	local CHILI_ADMIN_EMAIL=$1 ; shift ;      #email of chili admin user


	local SCM=$1 ; shift ;                    #SCM to use, currently only "git" and "svn" are supported
	local PROJ_ID=$1 ; shift ;                #id for project being created, this will appear in SCM URLs
	local PROJ_IS_PUBLIC=$1 ; shift ;         #is this project publicly visible?  Can anyone grab the code?
	local PROJ_NAME=$1 ; shift ;              #project name, as it will appear in chili



	CHILI_VHOST_SUBDIR=$(echo "$CHILI_VHOST_SUBDIR" | sed 's/^\///g')
	SSL_VHOST_SUBDIR=$(echo "$SSL_VHOST_SUBDIR" | sed 's/^\///g')

	gem install -v=0.4.2 i18n
	gem install -v=2.3.5 rails


	local curdir=$(pwd)
	local chili_install_path=""
	local chili_id=""
	if [ -z "$CHILI_VHOST" ] && [ "$USE_SSL" == "0" ] ; then
		echo "ERROR: You must specify a virtualhost and/or install to SSL Virtual Host\n";
		return
	elif [ -z "$CHILI_VHOST" ] ; then
		#install to SSL VHOST
		chili_id="chili"
		chili_install_path="/srv/www/$NGINX_SSL_ID/$chili_id"
		
		chili_num=1
		while [ -e "$chili_install_path" ] ; do
			chili_id="chili_$chili_num"
			chili_install_path="/srv/www/$NGINX_SSL_ID/$chili_id"
			chili_num=$(( $chili_num + 1 ))
		done
	else
		#install to VHOST
		chili_id="chili"
		chili_install_path="/srv/www/$CHILI_VHOST/$chili_id"

		chili_num=1
		while [ -e "$chili_install_path" ] ; do
			chili_id="chili_$chili_num"
			chili_install_path="/srv/www/$CHILI_VHOST/$chili_id"
			chili_num=$(( $chili_num + 1 ))
		done
	fi


	#create chili database
	local db="chili_"$(randomString 10 | tr "[:upper:]" "[:lower:]")
	if [ "$DB_TYPE" = "mysql" ] && [ -n "$DB_PASSWORD"] ; then
		mysql_create_database "$DB_PASSWORD" "$db"
		mysql_create_user     "$DB_PASSWORD" "$db" "$CHILI_ADMIN_PW"
		mysql_grant_user      "$DB_PASSWORD" "$db" "$db"
		gem install mysql
	else
		postgresql_install         #be sure it's installed
		postgresql_create_database "$db"
		postgresql_create_user     "$db" "$CHILI_ADMIN_PW"
		postgresql_grant_user      "$db" "$db"
		gem install pg
	fi


	#In order to clone chili repo we need git,
	#and git hosting plugin gets installed even if we're using SVN
	#so just go ahead and install git & gitolite no matter what
	#does nothing if git/gitolite is already installed
	git_install
	gitolite_install


	#get chiliproject code
	cd /tmp
	git clone git://github.com/chiliproject/chiliproject.git
	mv chiliproject "$chili_install_path"
	cd "$chili_install_path"
	git checkout "v1.2.0"
	rm -rf .git

	cat << EOF >config/database.yml
production:
  adapter: $DB_TYPE
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

	echo "en" | RAILS_ENV=production rake redmine:load_default_data
	mkdir tmp public/plugin_assets
	chmod -R 755 files log tmp public/plugin_assets


	#SCM stuff
	if [ "$SCM" = "git" ] ; then
		create_git "$PROJ_ID" "$PROJ_IS_PUBLIC" "$chili_install_path"
	elif [ "$SCM" = "svn" ] || [ "SCM" = "subversion" ] ; then
		create_svn "$PROJ_ID" "$chili_id" "$CHILI_ADMIN_PW" 
	else
		echo "ERROR: SCM \"$SCM\" not implemented"
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
					:is_public =>$PROJ_IS_PUBLIC
					)
EOF

	if [ "$SCM" = "git" ] ; then
		cat << EOF >>create.rb
repo = Repository::Git.create(
					:project_id=>project.id,
					:url=>"/srv/git/repositories/$PROJ_ID.git"
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
	if [ "$DB_TYPE" = "mysql" ] ; then
		echo "DELETE FROM users WHERE login=\"admin\" ; " | mysql -u root -p"$DB_PASSWORD" "$db"
	else
		echo "DELETE FROM users WHERE login=\"admin\" ; " | sudo -u postgres psql "$db"

	fi
	ruby script/console production < create.rb
	rm -rf create.rb


	
	
	#git hosting plugin
	if [ "$SCM" = "git" ] ; then
		cd vendor/plugins
		git clone https://github.com/ericpaulbishop/redmine_git_hosting.git
		cd redmine_git_hosting
		rm -rf .git
		escaped_chili_install_path=$(echo "$chili_install_path" | sed 's/\//\\\//g')
		sed -i -e  "s/'gitoliteUrl.*\$/'gitoliteUrl' => 'git@localhost:gitolite-admin.git',/"                                             "init.rb"
		sed -i -e  "s/'gitoliteIdentityFile.*\$/'gitoliteIdentityFile' => '$escaped_chili_install_path\/.ssh\/gitolite_admin_id_rsa',/"   "init.rb"
		sed -i -e  "s/'gitUserIdentityFile.*\$/'gitUserIdentityFile'   => '$escaped_chili_install_path\/.ssh\/git_user_id_rsa',/"         "init.rb"
		sed -i -e  "s/'basePath.*\$/'basePath' => '\/srv\/projects\/git\/repositories\/',/"                                               "init.rb"
		cp -r /root/.ssh "$chili_install_path"
		chown -R www-data:www-data "$chili_install_path"
		chmod 600 "$chili_install_path/.ssh/"*rsa*
		cd "$chili_install_path"
		rake db:migrate_plugins RAILS_ENV=production
	fi


	#single project plugin
	cd vendor/plugins
	git clone https://github.com/ericpaulbishop/redmine_single_project.git
	cd redmine_single_project
	rm -rf .git
	cd "$chili_install_path"

	#action_mailer_optional_tls plugin
	script/plugin install git://github.com/collectiveidea/action_mailer_optional_tls.git


	#themes
	git clone https://github.com/ericpaulbishop/redmine_theme_pack.git
	mkdir -p public/themes
	mv redmine_theme_pack/* public/themes/
	rm -rf redmine_theme_pack


	#update permissions on chili install dir
	chown -R www-data:www-data "$chili_install_path"


	#configure symlinks/vhosts
	ssl_config="/etc/nginx/sites-available/$NGINX_SSL_ID"
	ssl_root=$(get_root_for_site_id "$NGINX_SSL_ID")

	if [ "$USE_SSL" != "0" ] ; then
		#install to SSL VHOST
		if [ "$SSL_VHOST_SUBDIR" = "" ] || [ "$SSL_VHOST_SUBDIR" = "." ] ; then
			#set to root
			nginx_set_rails_as_vhost_root "$NGINX_SSL_ID" "$chili_install_path/public"
		else
			#make intermediate subdirectories
			mkdir -p "$ssl_root/$SSL_VHOST_SUBDIR"
			rm -rf "$ssl_root/$SSL_VHOST_SUBDIR"

			#create symlink
			ln -s "$chili_install_path/public" "$ssl_root/$SSL_VHOST_SUBDIR"
			nginx_add_passenger_uri_for_vhost "$ssl_config" "/$SSL_VHOST_SUBDIR"
		fi
	fi
	if [ -n "$CHILI_VHOST" ] ; then
		#install to VHOST
		vhost_config="/etc/nginx/sites-available/$CHILI_VHOST"
		vhost_root=$(get_root_for_site_id "$CHILI_VHOST")
		if [ "$CHILI_FORCE_SSL" != "1" ] ; then
			if [ "$CHILI_VHOST_SUBDIR" = "" ] || [ "$CHILI_VHOST_SUBDIR" = "." ] ; then
				#set to root
				nginx_set_rails_as_vhost_root "$CHILI_VHOST" "$chili_install_path/public"
			else
				#make intermediate subdirectories
				mkdir -p "$vhost_root/$CHILI_VHOST_SUBDIR"
				rm -rf "$vhost_root/$CHILI_VHOST_SUBDIR"

				#create symlink
				ln -s "$chili_install_path/public" "$vhost_root/$CHILI_VHOST_SUBDIR"
				nginx_add_passenger_uri_for_vhost "$vhost_config" "/$CHILI_VHOST_SUBDIR"
			fi
		else
			# setup nossl_include
			nossl_include="$NGINX_CONF_PATH/${CHILI_VHOST}_${chili_id}.conf"
			rm -rf "$nossl_include"
			cat << EOF >>"$nossl_include"
location ~ ^/$CHILI_ID/.*\$
{
	rewrite ^(.*)\$ https://\$host\$1 permanent;
}
EOF
			nginx_add_include_for_vhost "$vhost_config" "$nossl_include"
		fi
	fi

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
	# this only matters for display of urls in gitolite plugin, so
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
			touch "/srv/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
			chmod -R 775 "/srv/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
			chown -R git:www-data "/srv/git/repositories/$PROJ_ID.git/git-daemon-export-ok"
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
					:url=>"/srv/git/repositories/$PROJ_ID.git"
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




