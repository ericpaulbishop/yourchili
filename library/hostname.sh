#!/bin/bash

#################################
#	Hostname                #
#################################

function set_hostname
{
	if [ ! -n "$1" ]; then
		echo "set_hostname() requires hostname as its first argument"
		return 1;
	fi

	local HNAME="$1"
	echo "$HNAME" > /etc/hostname
	echo "$HNAME" > /proc/sys/kernel/hostname
	
	touch /etc/hosts
	cat /etc/hosts | grep -v "$HNAME" > /etc/hosts.tmp
	echo -e "\n127.0.0.1 $HNAME\n" >> /etc/hosts.tmp
	mv /etc/hosts.tmp /etc/hosts

}

function backup_hostname
{
	if [ ! -n "$1" ]; then
		echo "backup_hostname() requires the backup directory as its first argument"
		return 1;
	fi
	
	local BACKUP_DIR="$1"

	if [ -e /etc/hostname ] ; then
		cp /etc/hostname "$BACKUP_DIR/"
	fi
	if [ -e /etc/hosts ] ; then
		cp /etc/hosts "$BACKUP_DIR/"
	fi
	if [ -e /etc/mailname ] ; then
		cp /etc/mailname "$BACKUP_DIR/"
	fi
}

function restore_hostname
{
	if [ ! -n "$1" ]; then
		echo "restore_hostname() requires the backup directory as its first argument"
		return 1;
	fi
	
	local BACKUP_DIR="$1"

	if [ -e "$BACKUP_DIR/hostname" ] ; then
		cp "$BACKUP_DIR/hostname" /etc/hostname 
		hostname $(cat /etc/hostname)
	fi
	if [ -e "$BACKUP_DIR/hosts" ] ; then
		cp "$BACKUP_DIR/hosts" /etc/hosts
	fi
	if [ -e "$BACKUP_DIR/mailname" ] ; then
		cp "$BACKUP_DIR/mailname" /etc/mailname
	fi
}

function system_ip
{
	# returns the IP assigned to first ethernet device
	dev=$(ifconfig | grep "Ethernet"  | awk ' { print $1 } ' | head -n 1)
	if [ -z "$dev" ] ; then
		echo $(ifconfig eth0 | awk -F: '/inet addr:/ {print $2}' | awk '{ print $1 }')
	else
		echo $(ifconfig $dev | awk -F: '/inet addr:/ {print $2}' | awk '{ print $1 }')
	fi
}	
	 
function get_rdns_for_ip
{
	# calls host on an IP address and returns its reverse dns 
	if [ ! -e /usr/bin/host ]; then
		aptitude -y install dnsutils > /dev/null
	fi
	echo $(host $1 | awk '/pointer/ {print $5}' | sed 's/\.$//')
}
	 
function get_rdns
{
	# returns the reverse dns of the primary IP assigned to this system
	echo $(get_rdns $(system_ip))
}

