#!/bin/sh

# See https://github.com/tianon/docker-postgres-upgrade
#
# 0a. before running this script, make sure to update the database image to the postgres $NEW and the $NEW data path
# in the docker-compose file
# 0b. Also make sure there are no other scripts in the postgres-data directory such as analyze_new_cluster.sh or delete_old_cluster.sh as they might have wrong permissions

set -e

APP_PATH=$1
CONTAINER_NAME=$2
OLD=$3
NEW=$4

cd "$APP_PATH"

# 1. stop db container
echo "Stopping DB container $CONTAINER_NAME"
docker stop "$CONTAINER_NAME"

# 2. Create new directory
DATA_PATH="$APP_PATH/postgres-data/$NEW/data"
echo "Creating $DATA_PATH"
mkdir -p "$DATA_PATH"

# 3. run upgrade container
echo "Running upgrade container"
docker run --rm \
  -v "$APP_PATH"/postgres-data:/var/lib/postgresql \
  tianon/postgres-upgrade:"$OLD"-to-"$NEW" \
  --link

# 4. pull and run latest database container
UPDATE_SCRIPT="$APP_PATH/docker-update.sh"
echo "Updating containers $UPDATE_SCRIPT"
sh "$UPDATE_SCRIPT"

# 5. Fix pg_hba
echo "Fixing pg_hba"
echo "host all all all md5" >> "$APP_PATH"/postgres-data/"$NEW"/data/pg_hba.conf
docker restart "$CONTAINER_NAME"

# 6. generate optimizer statistics
echo "Waiting a bit"
sleep 10
echo "Generating optimizer statistics"
docker exec -t "$CONTAINER_NAME" /usr/lib/postgresql/"$NEW"/bin/vacuumdb -U postgres --all --analyze-in-stages
