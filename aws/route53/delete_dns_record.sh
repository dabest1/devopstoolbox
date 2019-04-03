#!/usr/bin/env bash

version=1.0.0

aws_profile="default"
hosted_zone_id="my_hosted_zone_id"
domain="mydomain.com"

hostname="$1"

if grep -q '[.]' <<<"$hostname"; then
  record_name="$hostname"
else
  record_name="$hostname.$domain"
fi
if ! grep -q '[.]$' <<<"$record_name"; then
  record_name="${record_name}."
fi

record_set="$(aws --profile "$aws_profile" route53 list-resource-record-sets --hosted-zone-id "$hosted_zone_id" --query "ResourceRecordSets[?Name == '$record_name']")"
if [[ $record_set == '[]' ]]; then
  echo "Record not found for '$hostname'."
  exit
fi

record_value="$(echo "$record_set" | jq -r '.[].ResourceRecords[].Value')"
record_type="$(echo "$record_set" | jq -r '.[].Type')"
record_ttl="$(echo "$record_set" | jq -r '.[].TTL')"

change_batch_json="$(cat <<HERE_DOC
{
  "Changes": [
    {
      "Action": "DELETE",
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
