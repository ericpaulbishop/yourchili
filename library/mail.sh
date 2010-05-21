
#################################
#	Mail Functions          #
#################################


function initialize_mail_server
{
	local TEST_USER_NAME="$1"
	local TEST_USER_DOMAIN="$2"
	local TEST_USER_PASS="$3"
	local PORT_587_ENABLED="$4"

	upgrade_system

	if [ -d	"/srv/mail" ] ; then
		echo "ERROR: mail server already initialized"
		return 1;
	fi
	
	#install postfix
	echo "postfix_2.6.5 postfix/destinations     string localhost" | debconf-set-selections
	echo "postfix_2.6.5 postfix/mailname         string localhost" | debconf-set-selections
	echo "postfix_2.6.5 postfix/main_mailer_type select Internet Site" | debconf-set-selections
	aptitude install -y postfix mailx dovecot-common dovecot-imapd dovecot-pop3d whois sasl2-bin mkpasswd
	
	postconf -e "mailbox_command = "
	postconf -e "home_mailbox = Maildir/"
	postconf -e "inet_interfaces = all"
	postconf -e "myhostname = localhost"
	
	postconf -e "virtual_mailbox_domains = /etc/postfix/vhosts"
	postconf -e "virtual_mailbox_base = /srv/mail"
	postconf -e "virtual_mailbox_maps = hash:/etc/postfix/vmaps"
	postconf -e "virtual_minimum_uid = 1000"
	postconf -e "virtual_uid_maps = static:5000"
	postconf -e "virtual_gid_maps = static:5000"
	
	postconf -e "smtp_tls_security_level = may"
	postconf -e "smtpd_tls_security_level = may"
	postconf -e "smtpd_tls_auth_only = no"
	postconf -e "smtp_tls_note_starttls_offer = yes"
	postconf -e "smtpd_tls_key_file = /etc/postfix/ssl/smtp_cert_key.pem"
	postconf -e "smtpd_tls_cert_file = /etc/postfix/ssl/smtp_cert.pem"
	postconf -e "smtpd_tls_CAfile_file = /etc/postfix/ssl/cacert.pem"
	postconf -e "smtpd_tls_loglevel = 1"
	postconf -e "smtpd_tls_received_header = yes"
	postconf -e "smtpd_tls_session_cache_timeout = 3600s"
	postconf -e "tls_random_source = dev:/dev/urandom"
	
	
	
	#configure tls
	local curdir=$(pwd)
	rm -rf /etc/postfix/ssl /tmp/tmp_cert
	mkdir -p /etc/postfix/ssl
	mkdir -p /tmp/tmp_cert
	cd /tmp/tmp_cert
	mkdir demoCA
	mkdir demoCA/newcerts
	mkdir demoCA/private
	touch demoCA/index.txt
	echo "01" >> demoCA/serial
	ca_pass=$(randomString 10)
	cat /etc/ssl/openssl.cnf | sed 's/supplied/optional/g' > openssl.cnf
	openssl req -new -x509 -keyout cakey.pem -out cacert.pem -days 99999 -passout "pass:$ca_pass" -batch
	openssl req -nodes -new -x509 -keyout newreq.pem -out newreq.pem -days 99999 -batch
	openssl x509 -x509toreq -in newreq.pem -signkey newreq.pem -out tmp.pem
	openssl ca -batch -passin "pass:$ca_pass" -keyfile ./cakey.pem -cert ./cacert.pem -config ./openssl.cnf -policy policy_anything -out newcert.pem -infiles tmp.pem
	grep -B 100 "END RSA PRIVATE KEY" newreq.pem > newcertkey.pem
	mv cacert.pem /etc/postfix/ssl/cacert.pem
	mv newcert.pem /etc/postfix/ssl/smtp_cert.pem
	mv newcertkey.pem /etc/postfix/ssl/smtp_cert_key.pem
	cd "$curdir"
	rm -rf /tmp/tmp_cert
	
	cat <<'EOF' >/etc/default/saslauthd
#
# Settings for saslauthd daemon
# Please read /usr/share/doc/sasl2-bin/README.Debian for details.
#

# Should saslauthd run automatically on startup? (default: no)
START=yes

PWDIR="/var/spool/postfix/var/run/saslauthd"
PARAMS="-m ${PWDIR}"
PIDFILE="${PWDIR}/saslauthd.pid"


# Description of this saslauthd instance. Recommended.
# (suggestion: SASL Authentication Daemon)
DESC="SASL Authentication Daemon"

# Short name of this saslauthd instance. Strongly recommended.
# (suggestion: saslauthd)
NAME="saslauthd"

# Which authentication mechanisms should saslauthd use? (default: pam)
#
# Available options in this Debian package:
# getpwent  -- use the getpwent() library function
# kerberos5 -- use Kerberos 5
# pam       -- use PAM
# rimap     -- use a remote IMAP server
# shadow    -- use the local shadow password file
# sasldb    -- use the local sasldb database file
# ldap      -- use LDAP (configuration is in /etc/saslauthd.conf)
#
# Only one option may be used at a time. See the saslauthd man page
# for more information.
#
# Example: MECHANISMS="pam"
MECHANISMS="pam"

# Additional options for this mechanism. (default: none)
# See the saslauthd man page for information about mech-specific options.
MECH_OPTIONS=""

# How many saslauthd processes should we run? (default: 5)
# A value of 0 will fork a new process for each connection.
THREADS=5

# Other options (default: -c -m /var/run/saslauthd)
# Note: You MUST specify the -m option or saslauthd won't run!
#
# WARNING: DO NOT SPECIFY THE -d OPTION.
# The -d option will cause saslauthd to run in the foreground instead of as
# a daemon. This will PREVENT YOUR SYSTEM FROM BOOTING PROPERLY. If you wish
# to run saslauthd in debug mode, please run it by hand to be safe.
#
# See /usr/share/doc/sasl2-bin/README.Debian for Debian-specific information.
# See the saslauthd man page and the output of 'saslauthd -h' for general
# information about these options.
#
# Example for postfix users: "-c -m /var/spool/postfix/var/run/saslauthd"
OPTIONS="-c -m /var/spool/postfix/var/run/saslauthd"
EOF
	
	dpkg-statoverride --force --update --add root sasl 755 /var/spool/postfix/var/run/saslauthd
	

	#if dovecot version > 1.1 we need ssl = yes, otherwise ssl_disable = no
	ssl_enabled="ssl_disable = no"
	dovecot_major_version=$(dovecot --version | sed 's/\./ /g' | awk ' { v=(100*$1 + $2); print v ; } ' )
	if [ "$dovecot_major_version" -gt 101 ] ; then
		ssl_enabled="ssl = yes"
	fi

	
	#configure virtual mailboxes
	
	groupadd -g 5000 vmail
	useradd -m -u 5000 -g 5000 -s /bin/bash -d /srv/mail vmail
	echo "$ssl_enabled" > /etc/dovecot/dovecot.conf
	cat <<'EOF' >>/etc/dovecot/dovecot.conf
base_dir = /var/run/dovecot/
disable_plaintext_auth = no
protocols = imap pop3
shutdown_clients = yes
log_path = /var/log/dovecot
info_log_path = /var/log/dovecot.info
log_timestamp = "%Y-%m-%d %H:%M:%S "
login_dir = /var/run/dovecot/login
login_chroot = yes
login_user = dovecot
login_greeting = Dovecot ready.
mail_location = maildir:/srv/mail/%d/%n
mmap_disable = no
valid_chroot_dirs = /var/spool/vmail

protocol pop3 {
  login_executable = /usr/lib/dovecot/pop3-login
  mail_executable = /usr/lib/dovecot/pop3
  pop3_uidl_format = %08Xu%08Xv
}
  
protocol imap {
  login_executable = /usr/lib/dovecot/imap-login
  mail_executable = /usr/lib/dovecot/imap
}
auth_executable = /usr/lib/dovecot/dovecot-auth
auth_verbose = yes
auth default {
  mechanisms = plain  digest-md5
  passdb passwd-file {
    args = /etc/dovecot/passwd
  }
  userdb passwd-file {
    args = /etc/dovecot/users
  }
  user = root
}
EOF
	
	cat <<'EOF' >/usr/sbin/add_dovecot_user
#!/bin/sh
if [ -z "$1" ] ; then
	echo "You must specify email address (full username) as first parameter"
fi
if [ -z "$2" ] ; then
	echo "You must specify password as second parameter"
fi

echo "$1" > /tmp/user
user=`cat /tmp/user | cut -f1 -d "@"`
domain=`cat /tmp/user | cut -f2 -d "@"`

touch /etc/dovecot/users
cat /etc/dovecot/users | grep -v "^$user@$domain:" > /etc/dovecot/users.tmp
echo "$user@$domain::5000:5000::/srv/mail/$domain/:/bin/false::" >>/etc/dovecot/users.tmp
mv /etc/dovecot/users.tmp /etc/dovecot/users

touch /etc/postfix/vhosts
cat /etc/postfix/vhosts | grep -v "$domain" > /etc/postfix/vhosts.tmp
echo $domain >> /etc/postfix/vhosts.tmp
mv /etc/postfix/vhosts.tmp /etc/postfix/vhosts

touch /etc/postfix/vmaps
cat /etc/postfix/vmaps | grep -v "$1" >/etc/postfix/vmaps.tmp
echo $1 $domain/$user/ >>/etc/postfix/vmaps.tmp
mv /etc/postfix/vmaps.tmp /etc/postfix/vmaps

/usr/bin/maildirmake.dovecot /srv/mail/$domain/$user 5000:5000
chown -R vmail /srv/mail/*
chgrp -R vmail /srv/mail/*

mkpasswd --hash=md5 $2 >/tmp/hash
echo "$1:`cat /tmp/hash`" >> /etc/dovecot/passwd

postmap /etc/postfix/vmaps
/etc/init.d/postfix restart
EOF
	chmod +x /usr/sbin/add_dovecot_user
	
	touch /etc/postfix/vhosts
	touch /etc/postfix/vmaps
	touch /etc/dovecot/passwd
	touch /etc/dovecot/users
	chmod 640 /etc/dovecot/users /etc/dovecot/passwd
	
	/usr/sbin/add_dovecot_user "$TEST_USER_NAME@$TEST_USER_DOMAIN" "$TEST_USER_PASS"
	
	
	#set ports smtp server will run on
	if [ "$PORT_587_ENABLED" = "0" ] ; then
		cat /etc/postfix/master.cf | sed 's/^submission.*inet/#submission inet/g' > /etc/postfix/master.cf.tmp
	else
		cat /etc/postfix/master.cf | sed 's/^#submission.*inet/submission inet/g' > /etc/postfix/master.cf.tmp
	fi
	mv /etc/postfix/master.cf.tmp /etc/postfix/master.cf
	

	mkdir -p /etc/ssl/private/
	mkdir -p /etc/ssl/certs
	cp /etc/postfix/ssl/smtp_cert.pem /etc/ssl/certs/dovecot.pem
	cp /etc/postfix/ssl/smtp_cert_key.pem /etc/ssl/private/dovecot.pem

	#restart
	/etc/init.d/saslauthd restart
	/etc/init.d/dovecot restart
	/etc/init.d/postfix restart
}



function backup_mail_config
{
	if [ ! -n "$1" ]; then
		echo "backup_mail_config() requires the backup directory as its first argument"
		return 1;
	fi
	local BACKUP_DIR="$1"

	rm -rf	 /tmp/mail_backup
	mkdir -p /tmp/mail_backup
	cp -rp /etc/postfix /tmp/mail_backup/
	cp -rp /etc/dovecot /tmp/mail_backup/
	cp -rp /srv/mail  /tmp/mail_backup/
	local curdir=$(pwd)	
	cd /tmp
	tar cjfp "$BACKUP_DIR/mail_backup.tar.bz2" mail_backup
	cd "$curdir"
	rm -rf /tmp/mail_backup
}



function restore_mail_config
{
	if [ ! -n "$1" ]; then
		echo "restore_mail_config() requires the backup directory as its first argument"
		return 1;
	fi
	local BACKUP_DIR="$1"

	if [ ! -e /srv/mail ] ; then
		initialize_mail_server "dummy_user" "dummy.com" "dummy_pass" "1"
	fi

	if [ -e "$BACKUP_DIR/mail_backup.tar.bz2" ] ; then
		rm -rf /tmp/mail_backup
		tar -C /tmp -xjf $BACKUP_DIR/mail_backup.tar.bz2
		rm -rf /etc/postfix /etc/dovecot /srv/mail/*
		mv /tmp/mail_backup/postfix /etc/
		mv /tmp/mail_backup/dovecot /etc/
		mv /tmp/mail_backup/vmail/* /srv/mail
		chown -R vmail /srv/mail/*
		chgrp -R vmail /srv/mail/*
		rm -rf /tmp/mail_backup
	

		
		#if dovecot version > 1.1 we need ssl = yes, otherwise ssl_disable = no
		dovecot_major_version=$(dovecot --version | sed 's/\./ /g' | awk ' { v=(100*$1 + $2); print v ; } ' )
		if [ "$dovecot_major_version" -gt 101 ] ; then
			sed -i -e 's/^ssl_disable.*no.*$/ssl = yes/g' /etc/dovecot/dovecot.conf
			sed -i -e 's/^ssl_disable.*yes.*$/ssl = no/g' /etc/dovecot/dovecot.conf
		fi


		/etc/init.d/saslauthd restart
		/etc/init.d/dovecot restart
		/etc/init.d/postfix restart
	fi
}


