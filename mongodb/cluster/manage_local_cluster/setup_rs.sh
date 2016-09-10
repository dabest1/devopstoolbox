#!/bin/bash

# Purpose:
#     Set up replica sets.

version="1.0.2"

hostname="$(hostname | awk -F. '{print $1}')"

mongo --port 27000 --eval "$(cat <<HERE_DOCUMENT
cfg = {
      "_id" : "a",
      "members" : [
          {
              "_id" : 0,
              "host" : "$hostname:27000"
          }
      ]
  };
printjson(rs.initiate(cfg));
rs.add("$hostname:27001");
rs.add("$hostname:27002");
printjson(rs.conf());
HERE_DOCUMENT
)"

mongo --port 27100 --eval "$(cat <<HERE_DOCUMENT
cfg = {
      "_id" : "b",
      "members" : [
          {
              "_id" : 0,
              "host" : "$hostname:27100"
          }
      ]
  };
printjson(rs.initiate(cfg));
rs.add("$hostname:27101");
rs.add("$hostname:27102");
printjson(rs.conf());
HERE_DOCUMENT
)"

mongo --port 27200 --eval "$(cat <<HERE_DOCUMENT
cfg = {
      "_id" : "c",
      "members" : [
          {
              "_id" : 0,
              "host" : "$hostname:27200"
          }
      ]
  };
printjson(rs.initiate(cfg));
rs.add("$hostname:27201");
rs.add("$hostname:27202");
printjson(rs.conf());
HERE_DOCUMENT
)"

mongo --port 27300 --eval "$(cat <<HERE_DOCUMENT
cfg = {
      "_id" : "d",
      "members" : [
          {
              "_id" : 0,
              "host" : "$hostname:27300"
          }
      ]
  };
printjson(rs.initiate(cfg));
rs.add("$hostname:27301");
rs.add("$hostname:27302");
printjson(rs.conf());
HERE_DOCUMENT
)"
