#!/bin/bash

function escape_path
{
	str=$1
	str=$(echo "$str" | sed 's/\//\\\//g')
	str=$(echo "$str" | sed 's/\./\\./g')
	str=$(echo "$str" | sed 's/\-/\\-/g')
	str=$(echo "$str" | sed 's/\$/\\$/g')
	str=$(echo "$str" | sed 's/\^/\\^/g')
	echo "$str"
}

