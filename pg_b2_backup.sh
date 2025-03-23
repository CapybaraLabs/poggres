#!/bin/bash
#
# Prerequisites:
#   sudo apt install backblaze-b2 pv lbzip2
#
# pass seven args:
#  - database name (needs to exist in postgres)
#  - app name (meta information)
#  - symmetric encryption password
#  - bucket name (target of the upload)
#  - backblaze account id
#  - backblaze app key
#  - qualifier (optional, defaults to daily)
#
# example: ./pg_b2_backup.sh foo next-big-thing top_secret backups xyy yzz daily
#
# the resulting file can be decrypted again with something like
# gpg --batch --passphrase top_secret --output foo_next-big-thing_2020-04-20.dump.bz2 --decrypt foo_next-big-thing_2020-04-20.dump.bz2.gpg

set -e
date

# Verify we are root
if [ "$EUID" -ne 0 ]; then
	echo "Please run as root"
	exit 1
fi

# Read arguments
DB=$1
APP=$2
PASS=$3
BUCKET=$4
B2_APP_KEY_ID=$5
B2_APP_KEY=$6
# the qualifier is used as a prefix for the file name, so lifecycle rules can be created in b2
QUALIFIER=${7:-daily}
echo "Backing up db ${DB} of app ${APP} to bucket ${BUCKET} with qualifier ${QUALIFIER}."

# Showing progress may spam log files, so we only do it when running in an interactive shell (e.g. for debugging the script).
SHOW_PROGRESS=false
if [ -t 1 ]; then
  echo "Running in a TTY."
  SHOW_PROGRESS=true
else
  echo "Running outside a TTY."
fi

DUMPDIR="/tmp"

#will look like: daily_2017-12-31_app_db.dump
FILENAME=${QUALIFIER}_$(date +%Y-%m-%d)_${APP}_${DB}.dump.bz2.gpg
DUMPFILE=${DUMPDIR}/${FILENAME}

mkdir -p ${DUMPDIR}

# cleanup any old backups
if [ -f "${DUMPFILE}" ]; then
	rm -f "${DUMPFILE}}"
fi

# Ensure dump file is cleaned up on exit
# shellcheck disable=SC2064 # the value is not changing
trap "rm -f ${DUMPFILE} && echo 'Dump file at ${DUMPFILE} cleaned up'" EXIT

# Dump & Encrypt it
# See https://community.centminmod.com/threads/compression-comparison-benchmarks-zstd-vs-brotli-vs-pigz-vs-bzip2-vs-xz-etc.12764/
# for comparison of compression algorithms. We pick lbzip2 for a great balance of speed and compression ratio.
echo "Dumping & encrypting at ${DUMPFILE}"
pv_zip() {
	if [ "${SHOW_PROGRESS}" = true ]; then
		pv | lbzip2;
	else
		lbzip2;
	fi
}
su - postgres -c "pg_dump ${DB}" | pv_zip | gpg --batch --passphrase "${PASS}" --output "${DUMPFILE}" --symmetric
echo "Dumped and encrypted at ${DUMPFILE}"

# calculate sha1 sum
SHA1=$(sha1sum "${DUMPFILE}" | sed -En "s/^([0-9a-f]{40}).*/\1/p")
echo "sha1sum is ${SHA1}"

#log in to backblaze
backblaze-b2 authorize-account "${B2_APP_KEY_ID}" "${B2_APP_KEY}"
echo "Logged into b2"

# upload it
PROGRESS=""
if [ "${SHOW_PROGRESS}" = false ]; then
  PROGRESS="--noProgress"
fi
backblaze-b2 upload-file --sha1 "${SHA1}" \
	--info app="${APP}" --info db="${DB}" \
	${PROGRESS} \
	"${BUCKET}" \
	"${DUMPFILE}" \
	"${FILENAME}"
echo "Uploaded to b2"

# log out
backblaze-b2 clear-account
echo "Logged out of b2"

echo "Done"
