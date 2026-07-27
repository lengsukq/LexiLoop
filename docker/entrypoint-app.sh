#!/bin/sh
set -eu
DB_PATH="${DATABASE_PATH:-/app/data/app.sqlite}"
DATA_DIR=$(dirname "$DB_PATH")
PENDING="$DATA_DIR/restore-pending.sqlite"
mkdir -p "$DATA_DIR" "${BACKUP_DIR:-$DATA_DIR/backups}" "$(dirname "${ECDICT_DATABASE_PATH:-$DATA_DIR/reference/ecdict.sqlite}")"
if [ -f "$PENDING" ]; then
  STAMP=$(date +%Y%m%d-%H%M%S)
  if [ -f "$DB_PATH" ]; then cp "$DB_PATH" "${BACKUP_DIR:-$DATA_DIR/backups}/before-restore-$STAMP.sqlite"; fi
  rm -f "$DB_PATH-wal" "$DB_PATH-shm"
  mv "$PENDING" "$DB_PATH"
  echo "[LexiLoop] pending restore applied"
fi
exec "$@"
