#!/bin/bash
set -e

mongosh --quiet --host localhost \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db = db.getSiblingDB('$MONGO_APP_DATABASE'); db.createUser({user: '$MONGO_APP_USER', pwd: '$MONGO_APP_PASSWORD', roles: [{role: 'readWrite', db: '$MONGO_APP_DATABASE'}]})"
