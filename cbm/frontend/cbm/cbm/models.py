from django.db import models
from django.utils import timezone


class Cluster(models.Model):
    cluster_id = models.AutoField(primary_key=True)
    cluster_name = models.CharField(unique=True, max_length=45)
    ts_insert = models.DateTimeField('insert timestamp', default=timezone.now)
    ts_update = models.DateTimeField('update timestamp', default=timezone.now)

    def __str__(self):
        return self.cluster_name

    class Meta:
       managed = False


class Node(models.Model):
    node_id = models.AutoField(primary_key=True)
    cluster_name = models.ForeignKey(Cluster, on_delete=models.CASCADE)
    node_name = models.CharField(max_length=45)
    db_type = models.CharField(max_length=45)
    port = models.IntegerField()
    ts_insert = models.DateTimeField('insert timestamp', default=timezone.now)
    ts_update = models.DateTimeField('update timestamp', default=timezone.now)

    def __str__(self):
        return self.node_name

    class Meta:
       managed = False


class Backup(models.Model):
    backup_id = models.AutoField(primary_key=True)
    node_name = models.ForeignKey(Node, on_delete=models.CASCADE)
    start_time = models.DateTimeField()
    end_time = models.DateTimeField()
    backup_path = models.CharField(max_length=255)
    status = models.CharField(max_length=45)
    backup_size = models.IntegerField(blank=True, null=True)
    compressed_size = models.IntegerField(blank=True, null=True)
    ts_insert = models.DateTimeField('insert timestamp', default=timezone.now)
    ts_update = models.DateTimeField('update timestamp', default=timezone.now)

    def __str__(self):
        return u'%s, %s, %s, %s, %s' % (self.node_name, self.start_time, self.end_time, self.backup_path, self.status)

    class Meta:
       managed = False