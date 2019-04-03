#!/usr/bin/env bash

version=1.0.0

aws_profile="default"
hosted_zone_id="my_hosted_zone_id"
domain="mydomain.com"
record_ttl=300
record_type="A"

#hostname="$(hostname)"
hostname="$1"
#record_value="$(hostname -I | awk '{print $1}')"
record_value="$2"
record_comment="Updated on $(date -u '+%FT%TZ')"

if grep -q '[.]' <<<"$hostname"; then
  record_name="$hostname"
else
  record_name="$hostname.$domain"
fi

change_batch_json="$(cat <<HERE_DOC
{
  "Comment": "$record_comment",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "ResourceRecords": [
          {
            "Value": "$record_value"
          }
        ],
        "Name": "$record_name",
        "Type": "$record_type",
        "TTL": $record_ttl
      }
    }
  ]
}
HERE_DOC
)"

aws --profile "$aws_profile" route53 change-resource-record-sets --hosted-zone-id "$hosted_zone_id" --change-batch "$change_batch_json"

exit $?
