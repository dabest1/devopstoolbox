#!/usr/bin/env bash

hosts="host1 host2 host3"
username="ec2-user"
private_key_file="~/.ssh/privatekey.pem"

while :; do
  for host in $hosts; do
    echo $host:
    status="$(ssh -i "$private_key_file" "$username"@"$host" /etc/init.d/mongod status)"
    echo $status
    running="$(echo $status | grep running)"
    #if [[ -z $running ]]; then
      # Do something.
    #fi
  done
done
