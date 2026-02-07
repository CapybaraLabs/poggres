#!/bin/sh

# See https://github.com/tianon/docker-postgres-upgrade
#
# 0a. before running this script, make sure to update the database image to the postgres $NEW and the $NEW data path in the docker compose file
# 0b. Also make sure there are no other scripts in the postgres-data directory such as analyze_new_cluster.sh or delete_old_cluster.sh as they might have wrong permissions

set -e

APP_PATH=$1
CONTAINER_NAME=$2
OLD=$3
NEW=$4

cd "$APP_PATH"

# Pull necessary containers
echo "Pulling containers for later steps"
docker pull tianon/postgres-upgrade:"$OLD"-to-"$NEW"
docker pull napstr/poggres:"$NEW"

CHECKSUMS=$(docker exec "$CONTAINER_NAME" psql -U postgres -t -A -c 'SHOW data_checksums')

# Stop db container
echo "Stopping DB container $CONTAINER_NAME"
docker stop "$CONTAINER_NAME"

# Make backup of the directory
DATA_PATH="$APP_PATH/postgres-data/"
echo "Creating a backup"
tar --use-compress-program="lbzip2" -cvf postgres-data.tar.bz2 "$DATA_PATH"

# Create new directory
NEW_DATA_PATH="$APP_PATH/postgres-data/$NEW/data"
echo "Creating $NEW_DATA_PATH"
mkdir -p "$NEW_DATA_PATH"

# Enable checksums if necessary (new v18 default)
if [ "$OLD" -le 17 ] && [ "$NEW" -ge 18 ] && [ "$CHECKSUMS" = "off" ]; then
	echo "Enabling checksums in PostgreSQL"
	docker run --rm \
    --mount "type=bind,src=$APP_PATH/postgres-data/$OLD/data,dst=/var/lib/postgresql/data" \
    --entrypoint '/bin/sh' \
    napstr/poggres:"$OLD" \
		-c 'pg_checksums --pgdata /var/lib/postgresql/data --enable --progress'
fi

# Run upgrade container
echo "Running upgrade container"
docker run --rm \
  --mount "type=bind,src=$APP_PATH/postgres-data,dst=/var/lib/postgresql" \
  --env "PGDATAOLD=/var/lib/postgresql/$OLD/data" \
  --env "PGDATANEW=/var/lib/postgresql/$NEW/data" \
  tianon/postgres-upgrade:"$OLD"-to-"$NEW" \
  --link

# Run latest database container
UPDATE_SCRIPT="$APP_PATH/docker-update.sh"
echo "Updating containers $UPDATE_SCRIPT"
sh "$UPDATE_SCRIPT"

# Fix pg_hba
echo "Fixing pg_hba"
echo "host all all all scram-sha-256" >> "$APP_PATH"/postgres-data/"$NEW"/data/pg_hba.conf
docker restart "$CONTAINER_NAME"

# Generate optimizer statistics
echo "Waiting a bit"
sleep 10
echo "Generating optimizer statistics"
docker exec -t "$CONTAINER_NAME" vacuumdb -U postgres --all --analyze-in-stages --missing-stats-only
