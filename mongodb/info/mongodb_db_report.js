listDatabases = db.adminCommand( { listDatabases: 1 } ).databases.sort();
var databases = [];
for (var i in listDatabases) {
  if (listDatabases[i].name != "local") {
    databases.push(listDatabases[i].name);
  }
}
databases = databases.sort();
print("Databases:");
printjson(databases);
print();

for (var i in databases) {
  print("Database:", databases[i]);
  print();
  db = db.getSiblingDB(databases[i]);

  var collectionNames = db.getCollectionNames();
  print("Collections:");
  printjson(collectionNames);
  print();

  for (var i in collectionNames) {
    collectionName = collectionNames[i];
    if (collectionName != "system.indexes" && collectionName != "system.profile") {
      print("Collection:", collectionName);
      count = db.getCollection(collectionName).count();
      print("Record count:", count);
      if (count > 0) {
        cursor = db.getCollection(collectionName).find().sort({$natural:-1}).limit(1);
        printjson(cursor.next());
      }
    }
  }
  print();
}
