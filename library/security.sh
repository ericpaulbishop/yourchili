
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
	MAX_CONN_PER_IP_PER_MINUTE="400"

	if [ -n "$1" ] ; then
		MAX_CONN_PER_IP_PER_MINUTE="$1"
	fi
	BURST=$(( 3 + (MAX_CONN_PER_IP_PER_MINUTE/10) ))

	sed -i 's/^\*filter.*$/*filter\n:ufw-before-logging-input - [0:0]/g' /etc/ufw/after.rules
	sed -i 's/^COMMIT.*$//g'                                             /etc/ufw/after.rules
	sed -i 's/^.*hashlimit.*SYNFLOOD.*$/g'                               /etc/ufw/after.rules
	echo "-I ufw-before-logging-input -i eth0 -p tcp --syn -m hashlimit --hashlimit-above $MAX_CONN_PER_IP_PER_MINUTE/min --hashlimit-burst $BURST --hashlimit-mode srcip --hashlimit-name SYNFLOOD --hashlimit-htable-size 32768 --hashlimit-htable-max 32768 --hashlimit-htable-gcinterval 1000 --hashlimit-htable-expire 100000 -j DROP" >> /etc/ufw/after.rules
	echo "COMMIT" >> /etc/ufw/after.rules

	#restart firewall
	ufw disable
	printf "y\ny\ny\n" | ufw enable

}

