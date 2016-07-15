var databaseName = 'database'; // your database name
var collectionName = 'collection'; // your collection
var adminUsername = 'username'; // user with clusterAdmin role
var adminPassword = 'password'; // that user's password

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
});
