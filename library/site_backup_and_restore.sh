#!/bin/bash

#####################################
# Site / Project Backup & Restore   #
#####################################

function backup_sites
{
	if [ ! -n "$1" ]; then
		echo "backup_sites() requires the backup directory as its first argument"
		return 1;
	fi
	BACKUP_DIR="$1";
	LINK_DIRS="$2"
	
	local curdir=$(pwd)


	if [ -d /srv/www/nginx_logs ] ; then
		mkdir -p  "$BACKUP_DIR/sites"
		cd /srv/www
		tar cjfp "$BACKUP_DIR/sites/nginx_logs.tar.bz2" "nginx_logs"
	fi
	
	if [ -d "/etc/nginx/sites-enabled" ] ; then
		mkdir -p "$BACKUP_DIR/sites"
		mkdir -p "$BACKUP_DIR/nginx_site_configs"
		mkdir -p "$BACKUP_DIR/nginx_configs"
		cp /etc/nginx/*.conf "$BACKUP_DIR/nginx_configs"
		cp -r /etc/nginx/ssl "$BACKUP_DIR/nginx_configs"


		cp /etc/nginx/sites-enabled/* "$BACKUP_DIR/nginx_site_configs"
		nginx_site_roots=$(cat /etc/nginx/sites-enabled/* 2>/dev/null | grep root | awk '{ print $2 }' | sed 's/;//g')
		for site_root in $nginx_site_roots ; do
			if [ -e "$site_root" ] ; then
				site_dir=$(echo "$site_root" | sed 's/\/public_html.*$//g')
				site_name=$(echo "$site_dir" | sed 's/^.*\///g')
				cd "$site_dir"/..
				echo $(pwd)
				
				cur_dir=$(pwd)
				exclude_str=""
				for dir in $LINK_DIRS ; do
					esc_cur=$(escape_path "$cur_dir")
					ex=$(echo "$dir" | sed "s/$esc_cur\///g")
					exclude_str="$exclude_str --exclude=\"$ex\" "
				done
				
				tar cjp $exclude_str -f "$BACKUP_DIR/sites/$site_name.tar.bz2" "$site_name"
			fi
		done
	fi
	if [ -d "/etc/apache2/sites-enabled" ] ; then
		mkdir -p "$BACKUP_DIR/sites"
		mkdir -p "$BACKUP_DIR/apache_site_configs"
		mkdir -p "$BACKUP_DIR/apache_configs"
		cp /etc/apache2/*.conf "$BACKUP_DIR/apache_configs"
		cp -r /etc/apache2/ssl "$BACKUP_DIR/apache_configs"


		cp /etc/apache2/sites-enabled/* "$BACKUP_DIR/apache_site_configs"
		apache_site_roots=$(cat /etc/apache2/sites-enabled/* 2>/dev/null | grep DocumentRoot  | awk '{ print $2 }')
		for site_root in $apache_site_roots ; do
			if [ -e "$site_root" ] ; then
				site_dir=$(echo "$site_root" | sed 's/\/public_html.*$//g')
				site_name=$(echo "$site_dir" | sed 's/^.*\///g')
				cd "$site_dir"/..
				echo $(pwd)
				
				cur_dir=$(pwd)
				exclude_str=""
				for dir in $LINK_DIRS ; do
					esc_cur=$(escape_path "$cur_dir")
					ex=$(echo "$dir" | sed "s/$esc_cur\///g")
					exclude_str="$exclude_str --exclude=\"$ex\" "
				done
				
				tar cjp $exclude_str -f "$BACKUP_DIR/sites/$site_name.tar.bz2" "$site_name"
			fi
		done
	fi
	
	if [ -n "$LINK_DIRS" ] ; then
		cd "$BACKUP_DIR"
		mkdir linked_dirs
		cd linked_dirs
		for dir in $LINK_DIRS ; do
			name=$(echo "$dir" | md5sum | awk '{ print $1 }')
			rmdir $name
			mkdir "$name"
			cd "$name"
			ln -s "$dir"
			echo "$dir" > "path.txt"
			cd ..
		done
	fi

	cd "$curdir"
}

function restore_sites
{
	if [ ! -n "$1" ]; then
		echo "restore_sites() requires the backup directory as its first argument"
		return 1;
	fi
	BACKUP_DIR="$1";
	
	local curdir=$(pwd)

	if [ -d "/etc/nginx/" ]  && [ -d "$BACKUP_DIR/nginx_configs" ] ; then
		cp -r "$BACKUP_DIR"/nginx_configs/* /etc/nginx/
	fi
	if [ -d "/etc/apache2/" ]  && [ -d "$BACKUP_DIR/apache_configs" ] ; then
		cp -r "$BACKUP_DIR"/apache_configs/* /etc/apache2/
	fi

	if [ -d "/etc/nginx/sites-available" ]  && [ -d "$BACKUP_DIR/nginx_site_configs" ] ; then
		configs=$(ls $BACKUP_DIR/nginx_site_configs/* | sed 's/^.*\///g')
		for config in $configs ; do
			cp "$BACKUP_DIR/nginx_site_configs/$config" "/etc/nginx/sites-available/$config"
			nginx_ensite "$config"
			site_root=$(cat "$BACKUP_DIR/nginx_site_configs/$config" 2>/dev/null | grep root | awk '{ print $2 }' | sed 's/;//g')
			echo "site_root = $site_root"
			if [ -n "$site_root" ] ; then
				site_dir=$(echo "$site_root" | sed 's/\/public_html.*$//g')
				site_name=$(echo "$site_dir" | sed 's/^.*\///g')
				echo "site_name = $site_name"
				if [ -e "$BACKUP_DIR/sites/$site_name.tar.bz2" ] ; then
					site_parent_dir=$(echo "$site_root" | awk 'BEGIN  { FS="/"  }; { for(i=1;i<NF-1;i++){ printf $i"/"; }     }')
					cd "$site_parent_dir"
					rm -rf "$site_name"
					tar xjfp "$BACKUP_DIR/sites/$site_name.tar.bz2"
				else
					mkdir -p "$site_dir/public_html"
					mkdir -p "$site_dir/logs"
					chown -R www-data:www-data "$site_dir"
				fi
			fi
		done
	fi
	
	if [ -d "/etc/apache2/sites-available" ]  && [ -d "$BACKUP_DIR/apache_site_configs" ] ; then
		configs=$(ls $BACKUP_DIR/apache_site_configs/* | sed 's/^.*\///g')
		for config in $configs ; do
			cp "$BACKUP_DIR/apache_site_configs/$config" "/etc/apache2/sites-available/$config"
			a2ensite "$config"
			site_root=$(cat "$BACKUP_DIR/apache_site_configs/$config" 2>/dev/null | grep DocumentRoot | awk '{ print $2 }' )
			if [ -n "$site_root" ] ; then
				site_dir=$(echo "$site_root" | sed 's/\/public_html.*$//g')
				site_name=$(echo "$site_dir" | sed 's/^.*\///g')
				if [ -e "$BACKUP_DIR/sites/$site_name.tar.bz2" ] ; then
					site_parent_dir=$(echo "$site_root" | awk 'BEGIN  { FS="/"  }; { for(i=1;i<NF-1;i++){ printf $i"/"; }     }')
					cd "$site_parent_dir"
					rm -rf "$site_name"
					tar xjfp "$BACKUP_DIR/sites/$site_name.tar.bz2"
				else
					mkdir -p "$site_dir/public_html"
					mkdir -p "$site_dir/logs"
					chown -R www-data:www-data "$site_dir"
				fi
			fi
		done
	fi
	
	if [ -e /etc/init.d/nginx ] ; then
		/etc/init.d/nginx restart 
	fi
	if [ -e /etc/init.d/apache2 ] ; then
		/etc/init.d/apache2 restart
	fi
	
	cd "$curdir"
}

function backup_projects
{
	if [ ! -n "$1" ]; then
		echo "backup_projects() requires the backup directory as its first argument"
		return 1;
	fi
	local BACKUP_DIR="$1"

	local curdir=$(pwd)
	rm -rf   /tmp/projects
	mkdir -p /tmp/projects
	cd       /tmp/projects

	#NOTE: You need to backup the database separately!
	#      Use backup_mysql function in this library
	if [ -d /srv/projects/redmine ] ; then	
		cp -r /srv/projects/redmine .
	fi
	if [ -d  /srv/projects/git ] ; then	
		cp -r /srv/projects/git .
	fi

	if [ -d /srv/projects/svn ] ; then
		mkdir svn

		proj_list=$(ls /srv/projects/redmine)
		for proj in $proj_list ; do
			if [ -e "/var/projects/svn/$proj" ] ; then
				svnadmin hotcopy "/var/projects/svn/$proj" "./svn/$proj"
			fi
		done
	fi

	cd ..
	tar cjfp "$BACKUP_DIR/projects.tar.bz2" projects
	rm -rf projects

	cd "$curdir"
}

function restore_projects
{
	if [ ! -n "$1" ]; then
		echo "restore_projects() requires the backup directory as its first argument"
		return 1;
	fi
	local BACKUP_DIR="$1"

	local curdir=$(pwd)

	git_install
	gitolite_install


	if [ -e "$BACKUP_DIR/projects.tar.bz2" ] ; then
		mkdir -p /srv/
		cd /srv
		rm -rf tmp
		mkdir tmp
		cd tmp
		tar xjfp "$BACKUP_DIR/projects.tar.bz2"
		if [ ! -d ./projects/git ] ; then
			mv /srv/projects/git ./projects/
		fi
		rm -rf /srv/projects
		mv projects /srv/
		cd ..
		rm -rf tmp

		admin_keys=$(find . -name "id_rsa*")
		for k in $admin_keys ; do
			cp "$k" /root/.ssh/
		done

		chown -R www-data:www-data /srv/projects
		if [ -d /srv/projects/git ] ; then
			chown -R git:www-data /srv/projects/git
		fi
		if [ -d /srv/projects/git/grack ] ; then
			chown -R www-data:www-data /srv/projects/git/grack
		fi
	fi
 
	if [ -d "/srv/projects/svn" ] ; then
		install_svn
	fi

	cd "$curdir"

}


