#!/bin/bash

# Purpose:
#     Lists all AWS profiles that are found in ~/.aws/config and 
#     ~/.aws/credentials files.

version="1.0.1"

echo "To switch AWS profile, run the following command followed by a profile name:"
echo "export AWS_PROFILE="
echo
echo "~/.aws/credentials:"
< ~/.aws/credentials grep '^\[.*\]$' | tr -d '[]'
echo
echo "~/.aws/config:"
< ~/.aws/config grep '^\[.*\]$' | tr -d '[]' | sed 's/profile //'
