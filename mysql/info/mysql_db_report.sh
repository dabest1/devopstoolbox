#!/usr/bin/env bash

username="root"
password="password"
database="mydatabase"

echo "Host: $HOSTNAME"
echo
echo "Database: $database"
echo
echo "Tables:"
tables="$(mysql --batch --skip-column-names -u"$username" -p"$password" "$database" -e 'SHOW TABLES')"
echo "$tables"
echo

for table in $tables; do
  echo "Table: $table"
  echo -n "Row count: "
  mysql --batch --skip-column-names -u"$username" -p"$password" "$database" -e "SELECT count(*) FROM $table;"
  mysql --vertical -u"$username" -p"$password" "$database" -e "SELECT * FROM $table LIMIT 1;"
  echo
done
