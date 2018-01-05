#!/bin/bash

# Purpose:
#     Create IAM users, add users to group, create access keys, send emails with access key.
# Usage:
#     Set variables within the script, then run script.

version="1.0.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

# Sender email address.
email_from="email@email.com"
# Sender name.
name_from="Name"
# Host to email from.
email_host="host_with_email"
# Email subject.
email_subject="Email subject"
# IAM group name.
groupname="group"
# Name and email of users for which to create IAM accounts.
names_emails="FirstName1 LastName1 <firstname1.lastname1@email.com>; FirstName2 LastName2 <firstname2.lastname2@email.com>"



# Break names and emails into one line per account.
name_email_lines="$(echo "$names_emails" | sed 's/; /;/g' | tr ';' '\n' | tr -d '<>')"

i=0
while read first last email; do
    array_name[$i]="$first $last"
    array_email[$i]="$email"
    array_username[$i]="$(echo "$email" | awk -F'@' '{print $1}' | tr 'A-Z' 'a-z')"
    i=$((i+1))
done <<< "$name_email_lines"
count=$i

for (( i=0; i<$count; i++ )); do
    echo 
    echo ./iam_create_user.sh "${array_username[$i]}"
    echo ./iam_add_user_to_group.sh "${array_username[$i]}" "$groupname"

    {
        echo "Hello ${array_name[$i]},

You have been granted access to ...

"
        ./iam_create_access_key.sh "${array_username[$i]}"
        echo "

Signature line,
$name_from"
    } | ssh "$email_host" "mail -r '$email_from' -s '$email_subject' '${array_email[$i]}'"
done
