
aptitude install -y tk8.4 libcurl

rm -rf /tmp/git
mkdir -p /tmp/git
cd /tmp/git
wget http://www.kernel.org/pub/software/scm/git/git-1.7.1.tar.bz2 
tar xjf *.tar.bz2
cd git-1.7.1
./configure
make install
