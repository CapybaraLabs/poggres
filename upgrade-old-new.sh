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

# Run upgrade container
echo "Running upgrade container"
docker run --rm \
  -v "$APP_PATH"/postgres-data:/var/lib/postgresql \
  tianon/postgres-upgrade:"$OLD"-to-"$NEW" \
  --link

# Run latest database container
UPDATE_SCRIPT="$APP_PATH/docker-update.sh"
echo "Updating containers $UPDATE_SCRIPT"
sh "$UPDATE_SCRIPT"

# Fix pg_hba
echo "Fixing pg_hba"
echo "host all all all md5" >> "$APP_PATH"/postgres-data/"$NEW"/data/pg_hba.conf
docker restart "$CONTAINER_NAME"

# Generate optimizer statistics
echo "Waiting a bit"
sleep 10
echo "Generating optimizer statistics"
docker exec -t "$CONTAINER_NAME" /usr/lib/postgresql/"$NEW"/bin/vacuumdb -U postgres --all --analyze-in-stages
