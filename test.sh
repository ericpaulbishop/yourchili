#!/bin/bash

. ./library/redcloud.sh


HOSTNAME="cori-celesti.org"
DB_PASSWORD="password"
NGINX_USER="www-data"
NGINX_GROUP="www-data"




create_redmine_project   "$DB_PASSWORD" "miner"  "proj1" "1" "git" "Project One" "admin" "password" "super" "user" "superuser@mydomain.com" "1"
create_redmine_project   "$DB_PASSWORD" "miner2" "proj2" "1" "svn" "Project Two" "admin" "password" "super" "user" "superuser@mydomain.com" "1"

enable_redmine_for_vhost "www.salamander-linux.com" "miner"  "0" "0"
enable_redmine_for_vhost "www.salamander-linux.com" "miner2" "0" "0"

enable_git_for_vhost     "www.salamander-linux.com" "proj1" "0"
enable_svn_for_vhost     "www.salamander-linux.com" "proj2" "1"


add_redmine_project      "miner" "proj3" "1" "svn" "Project Three" "admin" "password"  "1"
enable_svn_for_vhost     "www.salamander-linux.com" "proj3" "1"

add_redmine_project      "miner2" "proj4" "1" "git" "Project Four" "admin" "password"  "1"
enable_git_for_vhost     "www.salamander-linux.com" "proj4" "0"





