#!/bin/bash
set -e

while ! psql -U "$POSTGRES_USER" -tAc "SELECT 1 FROM pg_roles WHERE rolname='$POSTGRES_USER';" | grep -q 1; do
	echo "Waiting on postgres own initial setup to finish"
	sleep 1
done
sleep 1
while ! pg_isready -U "$POSTGRES_USER"; do
	echo "Waiting on postgres to be ready"
	sleep 1
done

PSQL="psql -v ON_ERROR_STOP=1 -U $POSTGRES_USER"

# make sure the role exists
$PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ROLE';" | grep -q 1 || createuser -U "$POSTGRES_USER" "$ROLE"
# make sure the role has a password
$PSQL -tAc "ALTER USER $ROLE WITH PASSWORD '$PASSWORD';"

for database in $DB; do
	# make sure the database exists
	$PSQL -tc "SELECT 1 FROM pg_database WHERE datname = '$database';" | grep -q 1 || $PSQL -c "CREATE DATABASE $database WITH OWNER = $ROLE;"
	# make sure the database is owned by the role
	$PSQL -c "ALTER DATABASE $database OWNER TO $ROLE;"
	$PSQL -c "GRANT ALL PRIVILEGES ON DATABASE $database TO $ROLE;"

	# make sure extensions are set up
	for extension in $EXTENSIONS; do
		$PSQL -d "$database" -c "CREATE EXTENSION IF NOT EXISTS $extension WITH SCHEMA pg_catalog;"
		$PSQL -d "$database" -c "ALTER EXTENSION $extension SET SCHEMA pg_catalog;"
	done
done

# Credits: https://twitter.com/samokhvalov/status/732359133010092032
echo '+------------------------+'
echo '|   ____  ______  ___    |'
echo '|  /    )/      \/   \   |'
echo '| (     / __    _\    )  |'
echo '|  \    (/ o)  ( o)   )  |'
echo '|   \_  (_  )   \ )  /   |'
echo '|     \  /\_/    \)_/    |'
echo '|      \/  //|  |\\      |'
echo '|          v |  | v      |'
echo '|            \__/        |'
echo '|                        |'
echo '|    postgres go brrr    |'
echo '+------------------------+'
