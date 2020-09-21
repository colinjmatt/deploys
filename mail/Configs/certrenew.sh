#!/bin/sh
certbot renew --renew-hook "systemctl reload nginx postfix dovecot" >/dev/null 2>&1
