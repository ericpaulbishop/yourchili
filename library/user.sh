#!/bin/bash


function add_user
{
	local USER="$1"
	local PASS="$2"
	local ADMIN="$3"


	if [ "$ADMIN" = "1" ] ; then
		aptitude install -y sudo
		admin_exists=$(grep "^admin:" /etc/group)
		if [ -z "$admin_exists" ] ; then
			groupadd admin
			chmod 777 /etc/sudoers
			cat /etc/sudoers | grep -v admin > /etc/sudoers.tmp
			echo "%admin ALL=(ALL) ALL" >>/etc/sudoers.tmp
			mv /etc/sudoers.tmp /etc/sudoers
			chmod 0440 /etc/sudoers
		fi
		useradd "$USER" -m -s /bin/bash -G admin >/dev/null 2>&1
	else
		useradd "$USER" -m -s /bin/bash >/dev/null 2>&1
	fi
	printf "$PASS\n$PASS\n" | passwd "$USER" >/dev/null 2>&1
}


