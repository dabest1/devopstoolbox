#!/bin/bash

# Purpose:
#     Set up sharding.

version="1.0.1"

mongo --port 27017 --eval '
sh.addShard("a/myhost:27000");
sh.addShard("b/myhost:27100");
sh.addShard("c/myhost:27200");
sh.addShard("d/myhost:27300");
sh.status();
'
