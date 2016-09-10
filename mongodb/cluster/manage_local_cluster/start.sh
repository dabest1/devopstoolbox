mkdir a1 a2 a3 b1 b2 b3 c1 c2 c3 d1 d2 d3 cfg1 cfg2 cfg3

echo config servers
mongod --configsvr --dbpath cfg1 --port 26050 --fork --logpath log.cfg1 --logappend
mongod --configsvr --dbpath cfg2 --port 26051 --fork --logpath log.cfg2 --logappend
mongod --configsvr --dbpath cfg3 --port 26052 --fork --logpath log.cfg3 --logappend

echo
echo shard servers
mongod --shardsvr --replSet a --dbpath a1 --logpath log.a1 --port 27000 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet a --dbpath a2 --logpath log.a2 --port 27001 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet a --dbpath a3 --logpath log.a3 --port 27002 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet b --dbpath b1 --logpath log.b1 --port 27100 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet b --dbpath b2 --logpath log.b2 --port 27101 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet b --dbpath b3 --logpath log.b3 --port 27102 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet c --dbpath c1 --logpath log.c1 --port 27200 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet c --dbpath c2 --logpath log.c2 --port 27201 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet c --dbpath c3 --logpath log.c3 --port 27202 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet d --dbpath d1 --logpath log.d1 --port 27300 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet d --dbpath d2 --logpath log.d2 --port 27301 --fork --logappend --smallfiles --oplogSize 50
mongod --shardsvr --replSet d --dbpath d3 --logpath log.d3 --port 27302 --fork --logappend --smallfiles --oplogSize 50

echo
echo mongos processes
mongos --configdb myhost:26050,myhost:26051,myhost:26052 --fork --logappend --logpath log.mongos1 --port 27017
mongos --configdb myhost:26050,myhost:26051,myhost:26052 --fork --logappend --logpath log.mongos2 --port 26061
mongos --configdb myhost:26050,myhost:26051,myhost:26052 --fork --logappend --logpath log.mongos3 --port 26062
mongos --configdb myhost:26050,myhost:26051,myhost:26052 --fork --logappend --logpath log.mongos4 --port 26063

echo
echo process list
ps -A | grep [m]ongo

./setup_rs.sh
sleep 3
./setup_sh.sh
