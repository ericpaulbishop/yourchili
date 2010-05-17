#!/bin/bash

function randomString {
	if [ ! -n "$1" ];
		then LEN=20
		else LEN="$1"
	fi

	echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c $LEN) # generate a random string
}
