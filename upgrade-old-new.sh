#!/bin/sh

# See https://github.com/tianon/docker-postgres-upgrade
#
# 0. before running this script, make sure to update the database image to the postgres $NEW and the $NEW data path
# in the docker-compose file

set -e

APP_PATH=$1
CONTAINER_NAME=$2
OLD=$3
NEW=$4

# 1. stop db container
docker stop "$CONTAINER_NAME"

# 2. Create new directory
mkdir -p "$APP_PATH"/postgres-data/"$NEW"/data

# 3. run upgrade container
docker run --rm \
  -v "$APP_PATH"/postgres-data:/var/lib/postgresql \
  tianon/postgres-upgrade:"$OLD"-to-"$NEW" \
  --link

# 4. pull and run latest database container
"$APP_PATH"/docker-update.sh

# 5. Fix pg_hba
echo "host all all all md5" >> "$APP_PATH"/postgres-data/"$NEW"/data/pg_hba.conf
docker restart "$CONTAINER_NAME"

# 6. generate optimizer statistics
sleep 10
docker exec -t "$CONTAINER_NAME" /usr/lib/postgresql/"$NEW"/bin/vacuumdb -U postgres --all --analyze-in-stages
