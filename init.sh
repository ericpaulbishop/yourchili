#!/bin/bash

./install.sh
source /usr/local/lib/yourchili/yourchili.sh

HOSTNAME="mysite.com"
DB_PASSWORD="password"
NGINX_USER="www-data"
NGINX_GROUP="www-data"


USER="librarian"
USER_PW="ookook"
USER_FIRST_NAME="The"
USER_LAST_NAME="Librarian"
USER_EMAIL="librarian@uu.edu.am"

BACKUP_DIR="/backups" #directory where we store backups



#updates packages to latest versions
upgrade_system

#sets detailed (2-line) bash prompt that includes date/time
#otherwise we just use short 1-line bash prompt (but still colored)
better_bash_prompt 1

#set hostname and allowed ports
#port 22=ssh; 80,443=http,https; 25,110,587=email; 9418=git
set_hostname "$HOSTNAME"
set_open_ports 22 80 443 25 110 587 9418 


# Add an admin user
# Last arg indicates that this is an admin
add_user "$USER" "$USER_PW" "1"

#install mysql, let it use up to 30% of memory
mysql_install "$DB_PASSWORD"
mysql_tune 30

#install nginx, along with both passenger(ruby) and php
nginx_install "$NGINX_USER" "$NGINX_GROUP" "1" "1"


#set up two virtual hosts: mysite.com and thatothersite.com
# nginx_create_site takes 5 parameters:
# 1) The site id, the site will be set up at /srv/www/[site_id]
# 2) Server names for this site, usually a good idea to include both www.[site] and [site]
# 3) Whether rails is enabled for this site (1 or 0)
# 4) A whitespace separated list of all rails base uris (eg., specifying /my_rails_app, means that's address of you rails app)
# 5) Whther php is enabled for this site (e.g should we let php-fpm process .php files?)
#
# The nginx_ensite enables the new configuration and takes the site id as its only argument
#
nginx_create_site "mysite.com"        "mysite.com www.mysite.com"               0 "" 1
nginx_create_site "thatothersite.com" "thatothersite.com www.thatothersite.com" 0 "" 1
nginx_ensite "mysite.com"
nginx_ensite "thatothersite.com"
nginx_delete_site default


#create two redmine installs, one for each vhost, first host has a git project the other an svn project
#admin user in each case is our user specified above, with the same password in all cases
#
# create_redmine_project creates a new redmine install and sets up one project along with Git/SVN hosting for that project
# create_redmine_project takes 12 arguments:
#  1) Root database password
#  2) Redmine installation id (must be unique for every redmine install)
#  3) Project id to create (will appear in all SVN/Git URLs)
#  4) Whether the project is publicly visible (1=yes, 0=no)
#  5) The SCM to use, must be "git" or "svn"
#  6) Full name of the project, not more than 30 characters
#  7) Redmine admin username
#  8) Redmine admin password (doubles as password for redmine database that is created)
#  9) First name of redmine admin user
# 10) Last name of redmine admin user
# 11) Email address of redmine admin user
# 12) Whether to force SSL when using http, if authorization is required (only valid for git projects)
create_redmine_project   "$DB_PASSWORD" "miner1" "my-git-proj1" "1" "git" "My Git One" "$USER" "$USER_PW" "$USER_FIRST_NAME" "$USER_LAST_NAME" "$USER_EMAIL" "1"
create_redmine_project   "$DB_PASSWORD" "miner2" "my-svn-proj1" "1" "svn" "My SVN One" "$USER" "$USER_PW" "$USER_FIRST_NAME" "$USER_LAST_NAME" "$USER_EMAIL"


#add two additional git projects to second redmine installation
#additional projects can be added to an existing redmine installation with add_redmine_project
#
#add_redmine_project is very similar to create_redmine_project, but only takes 12 arguments:
#  1) Redmine installation id to add to 
#  2) Project id to create (will appear in all SVN/Git URLs)
#  3) Whether the project is publicly visible (1=yes, 0=no)
#  4) The SCM to use, must be "git" or "svn"
#  5) Full name of the project, not more than 30 characters
#  6) Redmine admin username (must already exist)
#  7) Redmine admin password 
#  8) Whether to force SSL when using http, if authorization is required (only valid for git projects)
add_redmine_project "miner2" "my-git-proj2" "1" "git" "My Git Two"   "$USER" "$USER_PW" "1"
add_redmine_project "miner2" "my-git-proj3" "1" "git" "My Git Three" "$USER" "$USER_PW" "1"


# now that we've created the redmine installs/projects we need to enable them
# redmine and svn/git are enabled separately
#
# enable_redmine_for_vhost takes 4 arguments:
# 1) the site id
# 2) the redmine id
# 3) whether to force ssl (by redirecting) when connecting to this site (0 or 1)
# 4) should redmine be accessible at site root?  
#    If this last argument is 1, site root redirects to /redmine_id,
#    if it is 0 you must manually visit /redmine_id to access redmine
#
# enable_git_for_vhost and enable_svn_for_vhost take the same 3 arguments:
# 1) site id
# 2) project id
# 3) whether to force use of ssl (by redirecting) for all http connections to git/svn (0 or 1)
#
enable_redmine_for_vhost "mysite.com" "miner1" "0" "1"
enable_redmine_for_vhost "thatothersite.com" "miner2" "0" "1"

enable_git_for_vhost     "mysite.com"        "my-git-proj1" "0"
enable_git_for_vhost     "thatothersite.com" "my-git-proj2" "0"
enable_git_for_vhost     "thatothersite.com" "my-git-proj3" "0"
enable_svn_for_vhost     "thatothersite.com" "my-svn-proj1" "1"



#configure a mail server
#
# This installs necessary software and configures
# one email address (username@domain)
#
# initialize_mail_server takes 3 arguments
# 1) email username
# 2) email domain
# 3) email password
# 4) Allow connections on port 587 (0 or 1)
#

initialize_mail_server "$USER" "mysite.com" "$USER_PW" 1

# subsequent users can be added with
# add_dovecot_user utility which takes 2 parameters
# 1) email address
# 2) password

/usr/sbin/add_dovecot_user "mridcully@mysite.com"        "wowwowsauce"
/usr/sbin/add_dovecot_user "rincewind@mysite.com"        "runrunrun"
/usr/sbin/add_dovecot_user "deanhenry@thatothersite.com" "borntorune"


#configure backups --note that this may nearly double your disk usage
#since everything gets tarred and saved to a different directory once a day
#
# setup_backup_cronjob takes 2 parameters:
# 1) The root database password
# 2) the directory to save backups to
#
setup_backup_cronjob "$DB_PASSWORD" "$BACKUP_DIR"





