import django_tables2 as tables

from .models import Node, Cluster, Backup

class NodeTable(tables.Table):
    class Meta:
        model = Node
        attrs = {'class': 'table table-striped table-bordered table-hover'}


class ClusterTable(tables.Table):
    class Meta:
        model = Cluster
        attrs = {'class': 'table table-striped table-bordered table-hover'}


class BackupTable(tables.Table):
    class Meta:
        model = Backup
        attrs = {'class': 'table table-striped table-bordered table-hover'}