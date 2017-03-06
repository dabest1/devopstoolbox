from django.views import generic
from django.shortcuts import render
from django_tables2 import RequestConfig
from django.utils import timezone

from .models import Cluster, Node, Backup
from .tables import NodeTable, ClusterTable, BackupTable


class HomeView(generic.ListView):
    template_name = 'cbm/home.html'
    context_object_name = 'home'

    def get_queryset(self):
        return 0

class ClusterView(generic.ListView):
    template_name = 'cbm/cluster.html'
    context_object_name = 'cluster_list'

    def get_queryset(self):
        return Cluster.objects


class NodeView(generic.ListView):
    template_name = 'cbm/node.html'
    context_object_name = 'node_list'

    def get_queryset(self):
        return Node.objects


class BackupView(generic.ListView):
    template_name = 'cbm/backup.html'
    context_object_name = 'backup_list'

    def get_queryset(self):
        return Backup.objects


def node_table(request):
    table = NodeTable(Node.objects.all())
    RequestConfig(request).configure(table)
    return render(request, 'cbm/table.html', {'table': table})


def cluster_table(request):
    table = ClusterTable(Cluster.objects.all())
    RequestConfig(request).configure(table)
    return render(request, 'cbm/table.html', {'table': table})


def backup_table(request):
    table = BackupTable(Backup.objects.all().order_by('-start_time'))
    RequestConfig(request).configure(table)
    return render(request, 'cbm/table.html', {'table': table})


def overview(request):
    table = BackupTable(Backup.objects.filter(start_time__gte=timezone.now() - timezone.timedelta(days=2)))
    RequestConfig(request).configure(table)
    return render(request, 'cbm/table.html', {'table': table})