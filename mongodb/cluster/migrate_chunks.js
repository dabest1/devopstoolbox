// Usage:
//     mongo mongos.example.com/admin migrate_chunks.js
// Original source:
//     https://www.andrewzammit.com/blog/mongodb-migrate-and-merge-all-chunks-in-shard/

var databaseName = 'database'; // your database name
var collectionName = 'collection'; // your collection
var adminUsername = ''; // user with clusterAdmin role
var adminPassword = ''; // that user's password
var sleepMsBetweenMoveChunk = 60000 // Sleep time in milliseconds

var version = '1.0.2'

var namespace = databaseName+'.'+collectionName;
var admindb = db.getSiblingDB('admin');
var configdb = db.getSiblingDB('config');

admindb.auth(adminUsername,adminPassword);

if ( sh.getBalancerState() ) {
	print('balancer is enabled, turn it off');
	quit();
}

var foundDatabase = configdb.databases.findOne({_id:databaseName,partitioned:true});
if ( !foundDatabase || !foundDatabase.primary ) {
	print('no partitioned database found with name '+databaseName);
	quit();
}

var primaryShard = foundDatabase.primary;
print('primary shard is '+primaryShard);

var eligibleChunks = configdb.chunks.find({ns:namespace,shard:{$ne:primaryShard}});
if ( eligibleChunks.count() === 0 ) {
	print('no eligible chunks were found, either none exist or they are all already on the primary shard.');
}

var i = 0;
eligibleChunks.forEach(function(chunk) {
	i++;
	print(i+' moving chunk id '+chunk._id.toString());
	var result = admindb.runCommand({moveChunk:namespace,bounds:[chunk.min,chunk.max],to:primaryShard});
	if ( !result || !result.ok ) {
		print(i+' error moving chunk with id '+chunk._id.toString());
		print(JSON.stringify(result));
		quit();
	}
	print(i+' moved chunk successfully');
	print("Sleeping for "+sleepMsBetweenMoveChunk+" ms...")
	sleep(sleepMsBetweenMoveChunk)
});
