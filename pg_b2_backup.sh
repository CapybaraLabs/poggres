#!/bin/bash
# this requires the backblaze CLI tool to be installed (pip install b2)

# pass six args:
#  - database name (needs to exist in postgres)
#  - app name (meta information)
#  - symmetric encryption password
#  - bucket name (target of the upload)
#  - backblaze account id
#  - backblaze app key
#
# example: ./pg_b2_backup.sh foo next-big-thing top_secret backups-daily xyy yzz
#
# the resulting file can be decrypted again with something like
# gpg --batch --passphrase top_secret --output foo_next-big-thing_2020-04-20.dump.gz --decrypt foo_next-big-thing_2020-04-20.dump.gz.gpg

set -e
date

# Verify we are root
if [ "$EUID" -ne 0 ]; then
	echo "Please run as root"
	exit 1
fi

DB=$1
APP=$2
PASS=$3
BUCKET=$4
B2_ACCOUNT_ID=$5
B2_APP_KEY=$6
echo "Backing up db ${DB} of app ${APP} to bucket ${BUCKET}."

DUMPDIR="/tmp"

#will look like: app_db_2017-12-31.dump
FILENAME=$(date +%Y-%m-%d)_${APP}_${DB}.dump.gz.gpg
INFO="--info app=${APP} --info db=${DB}"

mkdir -p ${DUMPDIR}

# cleanup any old backups
if [ -f "${DUMPDIR}/${FILENAME}" ]; then
	rm -f "${DUMPDIR}/${FILENAME}"
fi

# dump & encrypt it
su - postgres -c "pg_dump ${DB}" | gzip | gpg --batch --passphrase "${PASS}" --output "${DUMPDIR}/${FILENAME}" --symmetric

# calculate sha1 sum
SHA1=$(sha1sum "${DUMPDIR}/${FILENAME}" | sed -En "s/^([0-9a-f]{40}).*/\1/p")

#log in to backblaze
b2 account authorize "${B2_ACCOUNT_ID}" "${B2_APP_KEY}"

# upload it
b2 file upload --sha1 "${SHA1}" \
	${INFO} \
	--quiet \
	"${BUCKET}" \
	"${DUMPDIR}/${FILENAME}" \
	"${FILENAME}"

# log out
b2 account clear

# clean up
if [ -f "${DUMPDIR}/${FILENAME}" ]; then
	rm -f "${DUMPDIR}/${FILENAME}"
fi
