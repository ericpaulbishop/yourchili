INSTALL_LOCATION="/usr/local/lib/redcloud"

if [ -n "$1" ] ; then
	INSTALL_LOCATION="$1"
fi

#remove trailing '/'
INSTALL_LOCATION=$(echo "$INSTALL_LOCATION" | sed 's/\/$//g')

#install
if [ -d ./library ] ; then
	echo "Installing to: $INSTALL_LOCATION"
	rm -rf "$INSTALL_LOCATION"
	mkdir -p "$INSTALL_LOCATION"
	cp -r ./library/* "$INSTALL_LOCATION"
	echo '#!/bin/bash' > "$INSTALL_LOCATION/tmp.tmp.sh"
	echo "REDCLOUD_INSTALL_DIR=\"$INSTALL_LOCATION\"" >> "$INSTALL_LOCATION/tmp.tmp.sh"
	cat "$INSTALL_LOCATION/redcloud.sh" | grep -v -P "^[\t ]*#" >> "$INSTALL_LOCATION/tmp.tmp.sh"
	mv "$INSTALL_LOCATION/tmp.tmp.sh" "$INSTALL_LOCATION/redcloud.sh"
fi
