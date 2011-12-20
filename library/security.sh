#!/bin/bash

#################################
#	Security                #
#################################

function set_open_ports
{
	#set open ports using ufw, and 
	#install fail2ban too while we're at it... 
	#(fail2ban temporarily blocks IPs that make a bunch of failed login attempts via ssh)
	aptitude install -y  fail2ban ufw
	
	#up the max fail2ban attempts to 12, since I can be a bit dimwitted at times...
	cat /etc/fail2ban/jail.conf | sed 's/maxretry.*/maxretry = 12/g' > /etc/fail2ban/jail.conf.tmp
	mv /etc/fail2ban/jail.conf.tmp /etc/fail2ban/jail.conf 

	#reset, removing all old rules
	printf "y\ny\ny\n" | ufw reset

	#always allow ssh
	ufw default deny
	ufw allow ssh
	ufw logging on

	#set allowed ports
	while [ -n "$1" ] ; do
		ufw allow "$1"
		shift
	done
	
	#enable firewall
	printf "y\ny\ny\n" | ufw enable
}

function prevent_syn_flood
{
	local MAX_CONN_PER_IP_PER_SECOND="200"
	if [ -n "$1" ] ; then
		MAX_CONN_PER_IP_PER_SECOND="$1"
	fi


	sed -i 's/^.*synflooders.*$//g'   /etc/ufw/before.rules
	sed -i 's/^COMMIT.*$//g'          /etc/ufw/before.rules

	echo "-I ufw-before-input -i eth0 -p tcp --syn -m hashlimit --hashlimit-above $MAX_CONN_PER_IP_PER_SECOND/sec --hashlimit-burst $MAX_CONN_PER_IP_PER_SECOND --hashlimit-mode srcip --hashlimit-name SYNFLOOD --hashlimit-htable-size 32768 --hashlimit-htable-max 32768 --hashlimit-htable-gcinterval 1000 --hashlimit-htable-expire 100000 -m recent --name synflooders --set -j DROP" >> /etc/ufw/before.rules
	echo "-I ufw-before-input -i eth0 -m recent --name synflooders --rcheck -j DROP" >> /etc/ufw/before.rules
	echo "COMMIT" >> /etc/ufw/before.rules

	#restart firewall
	ufw disable
	printf "y\ny\ny\n" | ufw enable

}


# requires public keys to activate as parameters
# function will die with error if no public keys are specified
function disable_password_ssh_auth
{
	if [ -z "$1" ] ; then
		echo "ERROR: NO PUBLIC KEYS SPECIFIED, CANNOT DISABLE PASSWORD AUTH"
		return
	fi
	
	sed -i 's/^.*ChallengeResponseAuthentication.*$/ChallengeResponseAuthentication no/g'  /etc/ssh/sshd_config
	sed -i 's/^.*PasswordAuthentication.*$/PasswordAuthentication no/g'                    /etc/ssh/sshd_config
	sed -i 's/^.*UsePAM.*$/UsePAM no/g'                                                    /etc/ssh/sshd_config
	
	#allow root login
	sed -i 's/^.*PermitRootLogin.*$/PermitRootLogin yes/g'                                                    /etc/ssh/sshd_config
	
	mkdir -p /root/.ssh
	while [ -n "$1" ] ; do
		echo "$1" >> /root/.ssh/authorized_keys
		shift
	done

	restart ssh
}



