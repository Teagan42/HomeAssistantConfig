# Log messages to stderr.
log() {
	echo "$1"
}


# Escape string to be safely usable in LDAP DN components and URIs.
# https://ldapwiki.com/wiki/DN%20Escape%20Values
ldap_dn_escape() {
	escaped=$(echo "$1" | sed -r \
		-e 's/[,\\#+<>;"=/?]/\\\0/g' \
		-e 's/^ (.*)$/\\ \1/' \
		-e 's/^(.*) $/\1\\ /' \
	)
	[ -z "$DEBUG" ] || log "Escaped '$1' to '$escaped'."
	echo "$escaped"
}


# The different client implementations.
ldap_auth_curl() {
	[ -z "$DEBUG" ] || verbose="-v"
	attrs=$(echo "$ATTRS" | sed "s/ /,/g")
	output=$(curl $verbose -s -m "$TIMEOUT" -u "$USERDN:$password" \
		"$SERVER/$BASEDN?dn,$attrs?$SCOPE?$FILTER")
	[ $? -ne 0 ] && return 1
	return 0
}

ldap_auth_ldapsearch() {
	if [ $(dpkg-query -l | grep ldap-utils | wc -l) -eq 0 ];
	then \
		apt-get update; \
		apt-get install -y ldap-utils; \
	fi
	common_opts="-o nettimeout=$TIMEOUT -H $SERVER -x"
	[ -z "$DEBUG" ] || common_opts="-v $common_opts"
	if [ -z "$BASEDN" ]; then
		output=$(ldapwhoami $common_opts -D "$USERDN" -w "$password")
	else
		output=$(ldapsearch $common_opts -LLL \
			-D "$USERDN" -w "$password" \
			-s "$SCOPE" -b "$BASEDN" "$FILTER" dn $ATTRS)
	fi
	[ $? -ne 0 ] && return 20
	return 0
}


# Source the config file.
if [ -z "$1" ]; then
	log "Usage: ldap-auth.sh <config-file>"
	exit 2
fi
CONFIG_FILE=$(realpath "$1")
if [ ! -e "$CONFIG_FILE" ]; then
	log "'$CONFIG_FILE': not found"
	exit 3
elif [ ! -f "$CONFIG_FILE" ]; then
	log "'$CONFIG_FILE': not a file"
	exit 4
elif [ ! -r "$CONFIG_FILE" ]; then
	log "'$CONFIG_FILE': no read permission"
	exit 5
fi
. "$CONFIG_FILE"

# Validate config.
err=0
if [ -z "$SERVER" ] || [ -z "$USERDN" ]; then
	log "SERVER and USERDN need to be configured."
	err=6
fi
if [ -z "$TIMEOUT" ]; then
	log "TIMEOUT needs to be configured."
	err=7
fi
if [ ! -z "$BASEDN" ]; then
	if [ -z "$SCOPE" ] || [ -z "$FILTER" ]; then
		log "BASEDN, SCOPE and FILTER may only be configured together."
		err=8
	fi
elif [ ! -z "$ATTRS" ]; then
	log "Configuring ATTRS only makes sense when enabling searching."
	err=9
fi

# Check username and password are present and not malformed.
if [ -z "$username" ] || [ -z "$password" ]; then
	log "Need username and password environment variables."
	err=10
elif [ ! -z "$USERNAME_PATTERN" ]; then
	username_match=$(echo "$username" | sed -r "s/$USERNAME_PATTERN/x/")
	if [ "$username_match" != "x" ]; then
		log "Username '$username' has an invalid format."
		err=11
	fi
fi

[ $err -ne 0 ] && exit 2

# Do the authentication.
case "$CLIENT" in
	"curl")
		ldap_auth_curl
		;;
	"ldapsearch")
		ldap_auth_ldapsearch
		;;
	*)
		log "Unsupported client '$CLIENT', revise the configuration."
		exit 2
		;;
esac

result=$?

entries=0
if [ $result -eq 0 ] && [ ! -z "$BASEDN" ]; then
	entries=$(echo "$output" | grep -cie '^dn\s*:')
	[ "$entries" != "1" ] && result=1
fi

if [ ! -z "$DEBUG" ]; then
	cat >&2 <<-EOF
		Result: $result
		Number of entries: $entries
		Client output:
		$output
		EOF
fi

if [ $result -ne 0 ]; then
	log "User '$username' failed to authenticate."
	type on_auth_failure > /dev/null && on_auth_failure
	exit 1
fi

log "User '$username' authenticated successfully."
type on_auth_success > /dev/null && on_auth_success
exit 0
