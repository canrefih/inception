#!/bin/bash

set -e

if [ ! -f /run/secrets/ftp_password ]; then
    echo "ERROR: FTP password secret not found."
    exit 1
fi

FTP_PASSWORD=$(cat /run/secrets/ftp_password)

if [ -z "$FTP_PASSWORD" ]; then
    echo "ERROR: FTP password is empty."
    exit 1
fi

echo "ftpuser:${FTP_PASSWORD}" | chpasswd

exec /usr/sbin/vsftpd /etc/vsftpd.conf
