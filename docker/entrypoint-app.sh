#!/bin/sh
set -eu
# PostgreSQL mode: no local database files to manage.
# The DATABASE_URL environment variable is used to connect to the database.
exec "$@"
