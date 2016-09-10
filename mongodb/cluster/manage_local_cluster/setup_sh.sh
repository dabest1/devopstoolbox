#!/bin/bash

# Purpose:
#     Set up sharding.

version="1.0.2"

hostname="$(hostname | awk -F. '{print $1}')"

mongo --port 27017 --eval "$(cat <<HERE_DOCUMENT
sh.addShard("a/$hostname:27000");
sh.addShard("b/$hostname:27100");
sh.addShard("c/$hostname:27200");
sh.addShard("d/$hostname:27300");
sh.status();
HERE_DOCUMENT
)"
