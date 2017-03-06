from controlcenter import Dashboard, widgets
from .models import Node, Cluster, Backup

class Nodes(widgets.ItemList):
    model = Node
    list_display = ('pk', 'node_name', 'cluster_name', 'db_type', 'port')

class Clusters(widgets.ItemList):
    model = Cluster
    list_display = ('pk', 'cluster_name')

class Backups(widgets.ItemList):
    model = Backup
    list_display = ('pk', 'node_name', 'start_time', 'end_time', 'backup_path', 'status')

class MyDashboard(Dashboard):
    widgets = (
        Nodes,
        Clusters,
        Backups,
    )
