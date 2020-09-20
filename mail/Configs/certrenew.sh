#!/bin/sh
certbot renew --renew-hook "systemctl reload nginx postfix dovecot"
