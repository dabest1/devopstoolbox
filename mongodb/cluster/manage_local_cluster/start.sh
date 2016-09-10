#!/bin/bash

# Purpose:
#     Create and start MongoDB cluster.

version="1.0.2"

mkdir a1 a2 a3 b1 b2 b3 c1 c2 c3 d1 d2 d3 cfg1 cfg2 cfg3

echo config servers
mongod --configsvr --dbpath cfg1 --port 26050 --fork --logpath cfg1.log --logappend
mongod --configsvr --dbpath cfg2 --port 26051 --fork --logpath cfg2.log --logappend
mongod --configsvr --dbpath cfg3 --port 26052 --fork --logpath cfg3.log --logappend

echo
echo shard servers
mongod --shardsvr --replSet a --dbpath a1 --logpath a1.log --port 27000 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet a --dbpath a2 --logpath a2.log --port 27001 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet a --dbpath a3 --logpath a3.log --port 27002 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet b --dbpath b1 --logpath b1.log --port 27100 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet b --dbpath b2 --logpath b2.log --port 27101 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet b --dbpath b3 --logpath b3.log --port 27102 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet c --dbpath c1 --logpath c1.log --port 27200 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet c --dbpath c2 --logpath c2.log --port 27201 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet c --dbpath c3 --logpath c3.log --port 27202 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet d --dbpath d1 --logpath d1.log --port 27300 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet d --dbpath d2 --logpath d2.log --port 27301 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet d --dbpath d3 --logpath d3.log --port 27302 --fork --logappend --smallfiles --oplogSize 50

echo
echo mongos processes
mongos --configdb myhost:26050,myhost:26051,myhost:26052 --fork --logappend --logpath mongos1.log --port 27017
mongos --configdb myhost:26050,myhost:26051,myhost:26052 --fork --logappend --logpath mongos2.log --port 26061
mongos --configdb myhost:26050,myhost:26051,myhost:26052 --fork --logappend --logpath mongos3.log --port 26062
mongos --configdb myhost:26050,myhost:26051,myhost:26052 --fork --logappend --logpath mongos4.log --port 26063

echo
echo process list
ps -A | grep [m]ongo

echo
echo set up replica sets
./setup_rs.sh

sleep 3
echo set up sharding
./setup_sh.sh
