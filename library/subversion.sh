#!/bin/bash


####################
# Apache (For SVN) #
####################



#SVN requires apache
function apache_install {

	if [ -z "$1" ] ; then
		echo "First argument of apache_install must be default apache port"
		return 1
	fi
	local PORT=$1
	local SSL_PORT=443

	if [ -n "$2" ] ; then
		SSL_PORT=$2
	fi

	local PERCENT_MEM=10
	if [ -n "$3" ]; then 
		PERCENT_MEM="$3"
	fi


	# installs apache2 with prefork MPM
	aptitude -y install apache2-mpm-prefork ssl-cert 
	local PERPROCMEM=20   # the amount of memory in MB each apache process is likely to utilize, assume apache processes will explode in size like they always do
	local MAXREQUESTS=100 # number of sessions served before apache process is refreshed, 0 for unlimited
	local MEM=$(grep MemTotal /proc/meminfo | awk '{ print int($2/1024) }') # how much memory in MB this system has
	local MAXCLIENTS=$(( 1+(MEM*PERCENT_MEM/100/PERPROCMEM) )) # calculate MaxClients
	MAXCLIENTS=${MAXCLIENTS/.*} # cast to an integer
	sed -i -e "s/\(^[ \t]*StartServers[ \t]*\)[0-9]*/\1$MAXCLIENTS/" /etc/apache2/apache2.conf
	sed -i -e "s/\(^[ \t]*MinSpareServers[ \t]*\)[0-9]*/\11/" /etc/apache2/apache2.conf
	sed -i -e "s/\(^[ \t]*MaxSpareServers[ \t]*\)[0-9]*/\1$MAXCLIENTS/" /etc/apache2/apache2.conf
	sed -i -e "s/\(^[ \t]*MaxClients[ \t]*\)[0-9]*/\1$MAXCLIENTS/" /etc/apache2/apache2.conf
	sed -i -e "s/\(^[ \t]*MaxRequestsPerChild[ \t]*\)[0-9]*/\1$MAXREQUESTS/" /etc/apache2/apache2.conf

	#turn off KeepAlive
	sed -i -e "s/\(^[ \t]*KeepAlive[ \t]*\)On/\1Off/" /etc/apache2/apache2.conf
	/etc/init.d/apache2 restart >/dev/null 2>&1


	#create SSL certificate, if one doesn't already exist in /etc/apache2/ssl/apache.pem
	mkdir /etc/apache2/ssl
	if [ ! -e "/etc/apache2/ssl/apache.pem" ] || [ ! -e "/etc/apache2/ssl/apache.key" ] ; then
		if [ -d "$NGINX_CONF_PATH/ssl" ] ; then
			mkdir /etc/apache2/ssl
			cp "$NGINX_CONF_PATH/ssl/nginx.pem" "/etc/apache2/ssl/apache.pem"
			cp "$NGINX_CONF_PATH/ssl/nginx.key" "/etc/apache2/ssl/apache.key"
		else
			make-ssl-cert generate-default-snakeoil --force-overwrite
			cp /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/apache2/ssl/apache.pem
			cp /etc/ssl/private/ssl-cert-snakeoil.key /etc/apache2/ssl/apache.key
		fi
	fi


	a2dissite default # disable the interfering default virtualhost

	cat << EOF >/etc/apache2/ports.conf

NameVirtualHost *:$PORT
Listen          $PORT

<Ifmodule mod_ssl.c>
	Listen  $SSL_PORT
</IfModule>
EOF

		#create SSL & non-SSL virtual hosts, but don't enable them
		mkdir -p /srv/www/apache_nossl/public_html /srv/www/apache_nossl/logs
		mkdir -p /srv/www/apache_ssl/public_html /srv/www/apache_ssl/logs
		
		echo "<VirtualHost _default_:$PORT>" >> /etc/apache2/sites-available/apache_nossl
		cat <<'EOF' >>/etc/apache2/sites-available/apache_nossl
    DocumentRoot             /srv/www/apache_nossl/public_html/
    ErrorLog                 /srv/www/apache_nossl/logs/error.log
    CustomLog                /srv/www/apache_nossl/logs/access.log combined
</VirtualHost>
EOF

		
		echo "<IfModule mod_ssl.c>" > /etc/apache2/sites-available/apache_ssl
		echo "<VirtualHost _default_:$SSL_PORT>" >> /etc/apache2/sites-available/apache_ssl
		cat <<'EOF' >>/etc/apache2/sites-available/apache_ssl
    DocumentRoot             /srv/www/apache_ssl/public_html/
    ErrorLog                 /srv/www/apache_ssl/logs/error.log
    CustomLog                /srv/www/apache_ssl/logs/access.log combined
    SSLEngine                on
    SSLCertificateFile       /etc/apache2/ssl/apache.pem
    SSLCertificateKeyFile    /etc/apache2/ssl/apache.key
    SSLProtocol              all
    SSLCipherSuite           HIGH:MEDIUM
    <FilesMatch "\.(cgi|shtml|phtml|php)$">
        SSLOptions           +StdEnvVars
    </FilesMatch>
    <Directory /usr/lib/cgi-bin>
        SSLOptions           +StdEnvVars
    </Directory> 
    BrowserMatch ".*MSIE.*" \
        nokeepalive          ssl-unclean-shutdown \
        downgrade-1.0        force-response-1.0
</VirtualHost>
</IfModule>
EOF


	a2ensite apache_ssl
	a2ensite apache_nossl

	#no sites enabled, so just stop apache for now
	/etc/init.d/apache2 restart >/dev/null 2>&1


}


#################
# Subversion    #
#################


#note this requires apache, which we're going to reverse proxy with nginx
function install_svn
{
	#only install if svn isn't initialized
	if [ ! -d "/srv/projects/svn" ] ; then

		#install apache
		apache_install "$APACHE_HTTP_PORT" "$APACHE_HTTPS_PORT" #should be firewalled -- we're just going to serve SVN through these ports to NGINX
		apache_tune 
		aptitude -y install wget subversion subversion-tools libapache2-svn libapache-dbi-perl libapache2-mod-perl2 libdbd-mysql-perl libdigest-sha1-perl libapache2-mod-wsgi

		#enable necessary apache modules	
		a2enmod rewrite
		a2enmod ssl
		a2enmod dav_svn
		a2enmod perl



		#create svn root directory
		mkdir -p "/srv/projects/svn"

		#grant permissions to apache for necessary directories
		chown    www-data:www-data "/srv/projects/"
		chown -R www-data:www-data "/srv/projects/svn"

		#restart apache
		/etc/init.d/apache2 restart

	fi

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



function enable_svn_for_vhost
{
	local VHOST_ID=$1
	local PROJ_ID=$2
	local FORCE_SVN_SSL=$3

	# setup nossl_include
	# if svn requires ssl just add rewrite, otherwise pass to apache http port
	# if redmine requires ssl add rewrite, otherwise nothing
	nossl_include="$NGINX_CONF_PATH/${PROJ_ID}_${VHOST_ID}_svn.conf"
	if [ "$FORCE_SVN_SSL" = "1" ] || [ "$FORCE_SVN_SSL" = "true" ]  ; then
		cat << EOF >"$nossl_include"
location ~ ^/svn/.*\$
{
	rewrite ^(.*)\$ https://\$host\$1 permanent;
}
EOF
	else
		cat << EOF >"$nossl_include"
location ~ ^/svn/.*\$
{
	proxy_set_header   X-Forwarded-Proto http;
	proxy_pass         http://localhost:$APACHE_HTTP_PORT;
}
EOF
	fi
	

	# setup ssl_include
	# always pass ssl to apache https port
	ssl_include="$NGINX_CONF_PATH/${PROJ_ID}_ssl_svn.conf"
	cat << EOF >"$ssl_include"
	location ~ ^/svn/.*\$
	{
		proxy_set_header   X-Forwarded-Proto https;
		proxy_pass         https://localhost:$APACHE_HTTPS_PORT;
	}
EOF

	ssl_config="/etc/nginx/sites-available/$NGINX_SSL_ID"
	if [ ! -e "$ssl_config" ] ; then
		nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "/git/$PROJ_ID.git" "1"
	fi

	nginx_add_include_for_vhost "$vhost_config" "$nossl_include"
	nginx_add_include_for_vhost "$ssl_config"   "$ssl_include"

	/etc/init.d/nginx restart
}





function better_redmine_auth_pm
{

	#default Redmine.pm only works with SVNParentPath, not SVNPath
	#Dump a better version that fixes this (still works with SVNParentPath too)
	mkdir -p /usr/lib/perl5/Apache/Authn
	cat << 'EOF' >/usr/lib/perl5/Apache/Authn/Redmine.pm
package Apache::Authn::Redmine;

=head1 Apache::Authn::Redmine

Redmine - a mod_perl module to authenticate webdav subversion users
against redmine database

=head1 SYNOPSIS

This module allow anonymous users to browse public project and
registred users to browse and commit their project. Authentication is
done against the redmine database or the LDAP configured in redmine.

This method is far simpler than the one with pam_* and works with all
database without an hassle but you need to have apache/mod_perl on the
svn server.

=head1 INSTALLATION

For this to automagically work, you need to have a recent reposman.rb
(after r860) and if you already use reposman, read the last section to
migrate.

Sorry ruby users but you need some perl modules, at least mod_perl2,
DBI and DBD::mysql (or the DBD driver for you database as it should
work on allmost all databases).

On debian/ubuntu you must do :

  aptitude install libapache-dbi-perl libapache2-mod-perl2 libdbd-mysql-perl

If your Redmine users use LDAP authentication, you will also need
Authen::Simple::LDAP (and IO::Socket::SSL if LDAPS is used):

  aptitude install libauthen-simple-ldap-perl libio-socket-ssl-perl

=head1 CONFIGURATION

   ## This module has to be in your perl path
   ## eg:  /usr/lib/perl5/Apache/Authn/Redmine.pm
   PerlLoadModule Apache::Authn::Redmine
   <Location /svn>
     DAV svn
     SVNParentPath "/var/svn"

     AuthType Basic
     AuthName redmine
     Require valid-user

     PerlAccessHandler Apache::Authn::Redmine::access_handler
     PerlAuthenHandler Apache::Authn::Redmine::authen_handler
  
     ## for mysql
     RedmineDSN "DBI:mysql:database=databasename;host=my.db.server"
     ## for postgres
     # RedmineDSN "DBI:Pg:dbname=databasename;host=my.db.server"

     RedmineDbUser "redmine"
     RedmineDbPass "password"
     ## Optional where clause (fulltext search would be slow and
     ## database dependant).
     # RedmineDbWhereClause "and members.role_id IN (1,2)"
     ## Optional credentials cache size
     # RedmineCacheCredsMax 50
  </Location>

To be able to browse repository inside redmine, you must add something
like that :

   <Location /svn-private>
     DAV svn
     SVNParentPath "/var/svn"
     Order deny,allow
     Deny from all
     # only allow reading orders
     <Limit GET PROPFIND OPTIONS REPORT>
       Allow from redmine.server.ip
     </Limit>
   </Location>

and you will have to use this reposman.rb command line to create repository :

  reposman.rb --redmine my.redmine.server --svn-dir /var/svn --owner www-data -u http://svn.server/svn-private/

=head1 MIGRATION FROM OLDER RELEASES

If you use an older reposman.rb (r860 or before), you need to change
rights on repositories to allow the apache user to read and write
S<them :>

  sudo chown -R www-data /var/svn/*
  sudo chmod -R u+w /var/svn/*

And you need to upgrade at least reposman.rb (after r860).

=cut

use strict;
use warnings FATAL => 'all', NONFATAL => 'redefine';

use DBI;
use Digest::SHA1;
# optional module for LDAP authentication
my $CanUseLDAPAuth = eval("use Authen::Simple::LDAP; 1");

use Apache2::Module;
use Apache2::Access;
use Apache2::ServerRec qw();
use Apache2::RequestRec qw();
use Apache2::RequestUtil qw();
use Apache2::Const qw(:common :override :cmd_how);
use APR::Pool ();
use APR::Table ();


 use Apache2::Directive qw();

my @directives = (
  {
    name => 'RedmineDSN',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
    errmsg => 'Dsn in format used by Perl DBI. eg: "DBI:Pg:dbname=databasename;host=my.db.server"',
  },
  {
    name => 'RedmineDbUser',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
  },
  {
    name => 'RedmineDbPass',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
  },
  {
    name => 'RedmineDbWhereClause',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
  },
  {
    name => 'RedmineCacheCredsMax',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
    errmsg => 'RedmineCacheCredsMax must be decimal number',
  },
  {
    name => 'SVNPath',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
  }
);

sub SVNPath { set_val('SVNPath', @_); }


sub RedmineDSN { 
  my ($self, $parms, $arg) = @_;
  $self->{RedmineDSN} = $arg;
  my $query = "SELECT 
                 hashed_password, auth_source_id, permissions
              FROM members, projects, users, roles, member_roles
              WHERE 
                projects.id=members.project_id
                AND member_roles.member_id=members.id
                AND users.id=members.user_id 
                AND roles.id=member_roles.role_id
                AND users.status=1 
                AND login=? 
                AND identifier=? ";
  $self->{RedmineQuery} = trim($query);
}

sub RedmineDbUser { set_val('RedmineDbUser', @_); }
sub RedmineDbPass { set_val('RedmineDbPass', @_); }
sub RedmineDbWhereClause { 
  my ($self, $parms, $arg) = @_;
  $self->{RedmineQuery} = trim($self->{RedmineQuery}.($arg ? $arg : "")." ");
}

sub RedmineCacheCredsMax { 
  my ($self, $parms, $arg) = @_;
  if ($arg) {
    $self->{RedmineCachePool} = APR::Pool->new;
    $self->{RedmineCacheCreds} = APR::Table::make($self->{RedmineCachePool}, $arg);
    $self->{RedmineCacheCredsCount} = 0;
    $self->{RedmineCacheCredsMax} = $arg;
  }
}

sub trim {
  my $string = shift;
  $string =~ s/\s{2,}/ /g;
  return $string;
}

sub set_val {
  my ($key, $self, $parms, $arg) = @_;
  $self->{$key} = $arg;
}

Apache2::Module::add(__PACKAGE__, \@directives);


my %read_only_methods = map { $_ => 1 } qw/GET PROPFIND REPORT OPTIONS/;

sub access_handler {
  my $r = shift;

  unless ($r->some_auth_required) {
      $r->log_reason("No authentication has been configured");
      return FORBIDDEN;
  }

  my $method = $r->method;
  return OK unless defined $read_only_methods{$method};

  my $project_id = get_project_identifier($r);

  $r->set_handlers(PerlAuthenHandler => [\&OK])
      if is_public_project($project_id, $r);

  return OK
}

sub authen_handler {
  my $r = shift;
  
  my ($res, $redmine_pass) =  $r->get_basic_auth_pw();
  return $res unless $res == OK;
  
  if (is_member($r->user, $redmine_pass, $r)) {
      return OK;
  } else {
      $r->note_auth_failure();
      return AUTH_REQUIRED;
  }
}

sub is_public_project {
    my $project_id = shift;
    my $r = shift;

    my $dbh = connect_database($r);
    my $sth = $dbh->prepare(
        "SELECT is_public FROM projects WHERE projects.identifier = ?;"
    );

    $sth->execute($project_id);
    my $ret = 0;
    if (my @row = $sth->fetchrow_array) {
    	if ($row[0] eq "1" || $row[0] eq "t") {
    		$ret = 1;
    	}
    }
    $sth->finish();
    undef $sth;
    $dbh->disconnect();
    undef $dbh;

    $ret;
}

# perhaps we should use repository right (other read right) to check public access.
# it could be faster BUT it doesn't work for the moment.
# sub is_public_project_by_file {
#     my $project_id = shift;
#     my $r = shift;

#     my $tree = Apache2::Directive::conftree();
#     my $node = $tree->lookup('Location', $r->location);
#     my $hash = $node->as_hash;

#     my $svnparentpath = $hash->{SVNParentPath};
#     my $repos_path = $svnparentpath . "/" . $project_id;
#     return 1 if (stat($repos_path))[2] & 00007;
# }

sub is_member {
  my $redmine_user = shift;
  my $redmine_pass = shift;
  my $r = shift;

  my $dbh         = connect_database($r);
  my $project_id  = get_project_identifier($r);

  my $pass_digest = Digest::SHA1::sha1_hex($redmine_pass);

  my $cfg = Apache2::Module::get_config(__PACKAGE__, $r->server, $r->per_dir_config);
  my $usrprojpass;
  if ($cfg->{RedmineCacheCredsMax}) {
    $usrprojpass = $cfg->{RedmineCacheCreds}->get($redmine_user.":".$project_id);
    return 1 if (defined $usrprojpass and ($usrprojpass eq $pass_digest));
  }
  my $query = $cfg->{RedmineQuery};
  my $sth = $dbh->prepare($query);
  $sth->execute($redmine_user, $project_id);

  my $ret;
  while (my ($hashed_password, $auth_source_id, $permissions) = $sth->fetchrow_array) {

      unless ($auth_source_id) {
	  my $method = $r->method;
          if ($hashed_password eq $pass_digest && ((defined $read_only_methods{$method} && $permissions =~ /:browse_repository/) || $permissions =~ /:commit_access/) ) {
              $ret = 1;
              last;
          }
      } elsif ($CanUseLDAPAuth) {
          my $sthldap = $dbh->prepare(
              "SELECT host,port,tls,account,account_password,base_dn,attr_login from auth_sources WHERE id = ?;"
          );
          $sthldap->execute($auth_source_id);
          while (my @rowldap = $sthldap->fetchrow_array) {
            my $ldap = Authen::Simple::LDAP->new(
                host    =>      ($rowldap[2] eq "1" || $rowldap[2] eq "t") ? "ldaps://$rowldap[0]" : $rowldap[0],
                port    =>      $rowldap[1],
                basedn  =>      $rowldap[5],
                binddn  =>      $rowldap[3] ? $rowldap[3] : "",
                bindpw  =>      $rowldap[4] ? $rowldap[4] : "",
                filter  =>      "(".$rowldap[6]."=%s)"
            );
            $ret = 1 if ($ldap->authenticate($redmine_user, $redmine_pass));
          }
          $sthldap->finish();
          undef $sthldap;
      }
  }
  $sth->finish();
  undef $sth;
  $dbh->disconnect();
  undef $dbh;

  if ($cfg->{RedmineCacheCredsMax} and $ret) {
    if (defined $usrprojpass) {
      $cfg->{RedmineCacheCreds}->set($redmine_user.":".$project_id, $pass_digest);
    } else {
      if ($cfg->{RedmineCacheCredsCount} < $cfg->{RedmineCacheCredsMax}) {
        $cfg->{RedmineCacheCreds}->set($redmine_user.":".$project_id, $pass_digest);
        $cfg->{RedmineCacheCredsCount}++;
      } else {
        $cfg->{RedmineCacheCreds}->clear();
        $cfg->{RedmineCacheCredsCount} = 0;
      }
    }
  }

  $ret;
}

sub get_project_identifier
{
	my $r = shift;
	my $cfg = Apache2::Module::get_config(__PACKAGE__, $r->server, $r->per_dir_config);
	my $identifier = "";
	if(defined($cfg->{SVNPath}))
	{
		#SVNPath
		$identifier = $r->location;
		$identifier =~ s/\/+$//g;
		$identifier =~ s/^.*\///g;
	}
	else 
	{
		#SVNParentPath
		my $location = $r->location;
		($identifier) = $r->uri =~ m{$location/*([^/]+)};
	}
	return $identifier;

}

sub connect_database {
    my $r = shift;
    
    my $cfg = Apache2::Module::get_config(__PACKAGE__, $r->server, $r->per_dir_config);
    return DBI->connect($cfg->{RedmineDSN}, $cfg->{RedmineDbUser}, $cfg->{RedmineDbPass});
}

1;

EOF


}


