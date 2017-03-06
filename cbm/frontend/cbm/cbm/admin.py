from django.contrib import admin

from .models import Cluster, Node, Backup

class NodeAdmin(admin.ModelAdmin):
    list_display = ['node_name', 'cluster_name', 'db_type', 'port']
    search_fields = ['node_name', 'db_type', 'port']

class BackupAdmin(admin.ModelAdmin):
    list_display = ['backup_id', 'node_name', 'start_time', 'end_time', 'backup_path', 'status']
    search_fields = ['backup_path', 'status']
    list_filter = ['start_time', 'end_time']

class ClusterAdmin(admin.ModelAdmin):
    list_display = ['cluster_name']
    search_fields = ['cluster_name']

admin.site.register(Cluster, ClusterAdmin)
admin.site.register(Node, NodeAdmin)
admin.site.register(Backup, BackupAdmin)
