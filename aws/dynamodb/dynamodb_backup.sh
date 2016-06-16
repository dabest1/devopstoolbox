#!/bin/bash

# Purpose:
#     Backup AWS DynamoDB tables. Script wrapper for dynamodump.py.

version=1.0.0

dynamodump="python /root/git/dynamodump/dynamodump.py"
region="us-east-1"
accessKey=""
secretKey=""

tables="table1
table2
table3"

for table in $tables; do
    echo "Table: $table"
    $dynamodump -r $region --accessKey $accessKey --secretKey $secretKey -m backup -s $table
    #$dynamodump -r $region --accessKey $accessKey --secretKey $secretKey -m restore -s $table -d new_table_name 
done
