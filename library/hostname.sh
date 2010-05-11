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


