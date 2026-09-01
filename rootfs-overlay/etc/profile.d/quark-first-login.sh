#!/bin/bash
# Show a non-blocking provisioning reminder on interactive root logins.

if [ "$(id -u)" -eq 0 ] && [ -t 1 ] && \
   [ ! -e /var/lib/quark-first-login/done ]; then
	printf '%s\n' \
		'' \
		'Quark-N initial setup has not been completed.' \
		'Run: quark-first-login' \
		''
fi
