"""cbm URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/1.10/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  url(r'^$', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  url(r'^$', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.conf.urls import url, include
    2. Add a URL to urlpatterns:  url(r'^blog/', include('blog.urls'))
"""
from django.conf.urls import url
from django.contrib import admin
from controlcenter.views import controlcenter
# Not to be used in production:
from django.contrib.staticfiles.urls import staticfiles_urlpatterns

from . import views

app_name = 'cbm'
urlpatterns = [
    url(r'^admin/', admin.site.urls, name='admin'),
    url(r'^admin/dashboard/', controlcenter.urls),
    url(r'^$', views.HomeView.as_view(), name='home'),
    url(r'^overview/$', views.overview, name='overview'),
    #url(r'^node/$', views.NodeView.as_view(), name='node'),
    url(r'^node/$', views.node_table, name='node'),
    #url(r'^cluster/$', views.ClusterView.as_view(), name='cluster'),
    url(r'^cluster/$', views.cluster_table, name='cluster'),
    #url(r'^backup/$', views.BackupView.as_view(), name='backup'),
    url(r'^backup/$', views.backup_table, name='backup'),
]

# Not to be used in production:
urlpatterns += staticfiles_urlpatterns()
