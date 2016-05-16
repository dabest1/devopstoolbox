#!/bin/bash

# Purpose:
#     Lists all AWS profiles that are found in ~/.aws/config and 
#     ~/.aws/credentials files.

version=1.0.0

echo "To switch AWS profile, run the following command followed by a profile name:"
echo "export AWS_PROFILE="
echo
< ~/.aws/config grep '^\[.*\]$' | tr -d '[]' | sed 's/profile //'
< ~/.aws/credentials grep '^\[.*\]$' | tr -d '[]'
