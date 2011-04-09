#!/bin/bash

./install.sh
source /usr/local/lib/redcloud/redcloud.sh

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


nginx_create_site "mysite.com"        "mysite.com www.mysite.com"               0 "" 1
nginx_ensite "mysite.com"
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
create_chili_project   "$DB_PASSWORD" "miner1" "my-git-proj1" "1" "git" "My Git One" "$USER" "$USER_PW" "$USER_FIRST_NAME" "$USER_LAST_NAME" "$USER_EMAIL" "1"


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
enable_chili_for_vhost "mysite.com" "miner1" "0" "1"

