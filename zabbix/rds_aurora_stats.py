#!/usr/bin/python
import datetime
import sys
from optparse import OptionParser
import boto.ec2.cloudwatch

version = "1.0.2"

### Arguments
parser = OptionParser()
parser.add_option("-i", "--instance-id", dest="instance_id",
                help="DBInstanceIdentifier")
parser.add_option("-a", "--access-key", dest="access_key",
                help="AWS Access Key")
parser.add_option("-k", "--secret-key", dest="secret_key",
                help="AWS Secret Access Key")
parser.add_option("-m", "--metric", dest="metric",
                help="RDS cloudwatch metric")
parser.add_option("-r", "--region", dest="region",
                help="RDS region")

(options, args) = parser.parse_args()

if (options.instance_id == None):
    parser.error("-i DBInstanceIdentifier is required")
if (options.access_key == None):
    parser.error("-a AWS Access Key is required")
if (options.secret_key == None):
    parser.error("-k AWS Secret Key is required")
if (options.metric == None):
    parser.error("-m RDS cloudwatch metric is required")

### Real code
metrics = {
    "ActiveTransactions":{"type":"float", "value":None},
    "AuroraBinlogReplicaLag":{"type":"float", "value":None},
    "AuroraReplicaLag":{"type":"float", "value":None},
    "AuroraReplicaLagMaximum":{"type":"float", "value":None},
    "AuroraReplicaLagMinimum":{"type":"float", "value":None},
    "BinLogDiskUsage":{"type":"float", "value":None},
    "BlockedTransactions":{"type":"float", "value":None},
    "BufferCacheHitRatio":{"type":"float", "value":None},
    "CPUUtilization":{"type":"float", "value":None},
    "CommitLatency":{"type":"float", "value":None},
    "CommitThroughput":{"type":"float", "value":None},
    "DDLLatency":{"type":"float", "value":None},
    "DDLThroughput":{"type":"float", "value":None},
    "DMLLatency":{"type":"float", "value":None},
    "DMLThroughput":{"type":"float", "value":None},
    "DatabaseConnections":{"type":"float", "value":None},
    "Deadlocks":{"type":"float", "value":None},
    "DeleteLatency":{"type":"float", "value":None},
    "DeleteThroughput":{"type":"float", "value":None},
    "DiskQueueDepth":{"type":"float", "value":None},
    "EngineUptime":{"type":"float", "value":None},
    "FreeLocalStorage":{"type":"float", "value":None},
    "FreeableMemory":{"type":"float", "value":None},
    "InsertLatency":{"type":"float", "value":None},
    "InsertThroughput":{"type":"float", "value":None},
    "LoginFailures":{"type":"float", "value":None},
    "NetworkReceiveThroughput":{"type":"float", "value":None},
    "NetworkThroughput":{"type":"float", "value":None},
    "NetworkTransmitThroughput":{"type":"float", "value":None},
    "Queries":{"type":"float", "value":None},
    "ReadIOPS":{"type":"float", "value":None},
    "ReadLatency":{"type":"float", "value":None},
    "ReadThroughput":{"type":"float", "value":None},
    "ResultSetCacheHitRatio":{"type":"float", "value":None},
    "SelectLatency":{"type":"float", "value":None},
    "SelectThroughput":{"type":"float", "value":None},
    "UpdateLatency":{"type":"float", "value":None},
    "UpdateThroughput":{"type":"float", "value":None},
    "WriteIOPS":{"type":"float", "value":None},
    "WriteLatency":{"type":"float", "value":None},
    "WriteThroughput":{"type":"float", "value":None}
}
end = datetime.datetime.utcnow()
start = end - datetime.timedelta(minutes=5)

# Get the region.
if (options.region == None):
    options.region = 'us-east-1'
    
for r in boto.ec2.cloudwatch.regions():
   if (r.name == options.region):
      region = r
      break

conn = boto.ec2.cloudwatch.CloudWatchConnection(options.access_key, options.secret_key,region=region)

for k,vh in metrics.items():
    if (k == options.metric):
        try:
                res = conn.get_metric_statistics(60, start, end, k, "AWS/RDS", "Average", {"DBInstanceIdentifier": options.instance_id})
        except Exception, e:
                print "status err Error running rds_stats: %s" % e.error_message
                sys.exit(1)
        average = res[-1]["Average"] # last item in result set
        #if (k == "FreeStorageSpace" or k == "FreeableMemory"):
                #average = average / 1024.0**3.0
        if vh["type"] == "float":
                metrics[k]["value"] = "%.4f" % average
        if vh["type"] == "int":
                metrics[k]["value"] = "%i" % average

        #print "metric %s %s %s" % (k, vh["type"], vh["value"])
        print "%s" % (vh["value"])
        break
