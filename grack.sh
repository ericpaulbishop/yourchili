#create test repo
project_root='/srv/git'
project_dir="$project_root/test"

mkdir -p "$project_dir"
cd "$project_dir"
git init
echo 'oogabooga' > file1
echo 'ook ook! Librarian poo!' > file2
git add file1
git add file2
git commit -a -m "initialize test repo"
chown -R www-data:www-data "$project_root"


#install grack
cd /srv
git clone http://github.com/schacon/grack.git
cd grack
rm -rf .git
escaped_proj_root=$(echo "$project_root" | sed 's/\//\\\//g')
sed -i -e  "s/project_root.*\$/project_root => \"$escaped_proj_root\",/"  config.ru
mkdir tmp
mkdir public

# put link in nginx_ssl
cd /srv/www/nginx_ssl/public_html/
ln -s /srv/grack/public git

#NOTE: you still need to enable rails in nginx vhost config

chown -R www-data:www-data "/srv/"






