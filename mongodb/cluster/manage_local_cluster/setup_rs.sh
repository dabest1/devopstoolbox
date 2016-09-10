#!/bin/bash

# Purpose:
#     Set up replica sets.

version="1.0.1"

mongo --port 27000 --eval '
cfg = {
      "_id" : "a",
      "members" : [
          {
              "_id" : 0,
              "host" : "myhost:27000"
          }
      ]
  };
printjson(rs.initiate(cfg));
rs.add("myhost:27001");
rs.add("myhost:27002");
printjson(rs.conf());
'

mongo --port 27100 --eval '
cfg = {
      "_id" : "b",
      "members" : [
          {
              "_id" : 0,
              "host" : "myhost:27100"
          }
      ]
  };
printjson(rs.initiate(cfg));
rs.add("myhost:27101");
rs.add("myhost:27102");
printjson(rs.conf());
'

mongo --port 27200 --eval '
cfg = {
      "_id" : "c",
      "members" : [
          {
              "_id" : 0,
              "host" : "myhost:27200"
          }
      ]
  };
printjson(rs.initiate(cfg));
rs.add("myhost:27201");
rs.add("myhost:27202");
printjson(rs.conf());
'

mongo --port 27300 --eval '
cfg = {
      "_id" : "d",
      "members" : [
          {
              "_id" : 0,
              "host" : "myhost:27300"
          }
      ]
  };
printjson(rs.initiate(cfg));
rs.add("myhost:27301");
rs.add("myhost:27302");
printjson(rs.conf());
'
