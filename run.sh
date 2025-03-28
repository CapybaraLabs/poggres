#!/bin/bash

# We are using this script, because we need to reliably execute a script on each start of the db container,
# to migrate the database for containers with an external volume persisting the database data, where the scripts in
# /docker-entrypoint-initdb.d/ are getting skipped, or add databases & extensions.
# Relevant issue: https://github.com/docker-library/postgres/issues/191

set -e

# For this to work properly, make sure the ENTRYPOINT is written in a way so this script is PID 1. See https://hynek.me/articles/docker-signals/
_term() {
	echo "Caught termination signal!"
	# We want a fast shutdown here due to the default 10 seconds
	# which docker waits until sending a SIGKILL which we want to avoid.
	# Relevant docs: https://www.postgresql.org/docs/10/static/server-shutdown.html
	# and https://www.postgresql.org/docs/current/app-pg-ctl.html
	su -c "pg_ctl stop -m fast" postgres
}
trap _term SIGTERM SIGINT

# save env vars to a place where they can later be accessed by cron jobs (for backups etc)
declare -p | grep -Ev 'BASHOPTS|BASH_VERSINFO|EUID|PPID|SHELLOPTS|UID' > /container.env

# ensure cron is running
cron

# running the official postgres entry script in the background
echo "Running entry point"
docker-entrypoint.sh postgres "$@" &
child=$!

# run our own init script
echo "Running init db"
initdb.sh

# Wait on the "docker-entrypoint.sh postgres &" process that we started in the background
echo "Waiting for exit"
wait "$child"
