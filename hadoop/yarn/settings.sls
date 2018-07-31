{% set p  = salt['pillar.get']('yarn', {}) %}
{% set pc = p.get('config', {}) %}
{% set g  = salt['grains.get']('yarn', {}) %}
{% set gc = g.get('config', {}) %}
{% set p_hdfs  = salt['pillar.get']('hdfs', {}) %}

{%- set resourcetracker_port        = gc.get('resourcetracker_port', pc.get('resourcetracker_port', '8031')) %}
{%- set scheduler_port              = gc.get('scheduler_port', pc.get('scheduler_port', '8030')) %}
{%- set resourcemanager_port        = gc.get('resourcemanager_port', pc.get('resourcemanager_port', '8032')) %}
{%- set resourcemanager_webapp_port = gc.get('resourcemanager_webapp_port', pc.get('resourcemanager_webapp_port', '8088')) %}
{%- set resourcemanager_admin_port  = gc.get('resourcemanager_admin_port', pc.get('resourcemanager_admin_port', '8033')) %}
{%- set nodemanager_port            = gc.get('nodemanager_port', pc.get('nodemanager_port', '50024')) %}
{%- set nodemanager_webapp_port     = gc.get('nodemanager_webapp_port', pc.get('nodemanager_webapp_port', '50025')) %}
{%- set nodemanager_localizer_port  = gc.get('nodemanager_localizer_port', pc.get('nodemanager_localizer_port', '50026')) %}
{%- set resourcemanager_target      = g.get('resourcemanager_target', p.get('resourcemanager_target', 'roles:hadoop_master')) %}
{%- set nodemanager_target          = g.get('nodemanager_target', p.get('nodemanager_target', 'roles:hadoop_slave')) %}
# this is a deliberate duplication as to not re-import hadoop/settings multiple times
{%- set targeting_method            = salt['grains.get']('hadoop:targeting_method', salt['pillar.get']('hadoop:targeting_method', 'grain')) %}
{%- set ha_cluster_id               = salt['grains.get']('ha_cluster_id', salt['pillar.get']('ha_cluster_id', None)) %}

{%- set minion_hosts                = [salt['network.get_hostname'](),
                                       grains['fqdn'],
                                       grains['nodename']] + salt['network.ip_addrs']() %}

{%- set is_clusters                 = True if p.get('clusters') else False %} 
{%- set pillar_cluster_id           = [] %}

{%- if is_clusters and ha_cluster_id == None %}
  {%- for cluster_name, cluster_value in p.clusters.items() %}
    {%- set yarn_hosts = cluster_value.get('resourcemanager_hosts', []) + cluster_value.get('nodemanager_hosts', []) %}
    {%- if cluster_value.get('resourcemanager_on_namenode', False) %}
      {%- set yarn_hosts = yarn_hosts + p_hdfs.get('clusters', {}).get(cluster_name, {}).get('namenode_hosts', []) %}
    {%- endif %}
    {%- if cluster_value.get('nodemanagers_on_datanodes', False) %}
      {%- set yarn_hosts = yarn_hosts + p_hdfs.get('clusters', {}).get(cluster_name, {}).get('datanode_hosts', []) %}
    {%- endif %}
    {%- for minion_host in minion_hosts %}
      {%- if minion_host in yarn_hosts %}
        {%- do pillar_cluster_id.append(cluster_name) %}
        {%- break %}
      {%- endif %}
    {%- endfor %}
    {%- if pillar_cluster_id %}
      {%- break %}
    {%- endif %}
  {%- endfor %}
{%- endif %}

{%- if pillar_cluster_id %}
  {%- set ha_cluster_id = pillar_cluster_id[0] %}
{%- endif %}

{%- if is_clusters and ha_cluster_id != None %}
  {%- set resourcemanager_hosts = p.clusters.get(ha_cluster_id, {}).get('resourcemanager_hosts', []) %}
  {%- set nodemanager_hosts = p.clusters.get(ha_cluster_id, {}).get('nodemanager_hosts', []) %}
  {%- if p.clusters.get(ha_cluster_id, {}).get('resourcemanager_on_namenode', False) %}
    {%- set resourcemanager_hosts = resourcemanager_hosts + p_hdfs.get('clusters', {}).get(ha_cluster_id, {}).get('namenode_hosts', []) %}
  {%- endif %}
  {%- if p.clusters.get(ha_cluster_id, {}).get('nodemanagers_on_datanodes', False) %}
    {%- set nodemanager_hosts = nodemanager_hosts + p_hdfs.get('clusters', {}).get(ha_cluster_id, {}).get('datanode_hosts', []) %}
  {%- endif %}
{%- else %}
  {%- set resourcemanager_hosts = g.get('resourcemanager_hosts', p.get('resourcemanager_hosts', salt['mine.get'](resourcemanager_target, 'network.interfaces', expr_form=targeting_method)|sort)) %}
  {%- set nodemanager_hosts = g.get('nodemanager_hosts', p.get('nodemanager_hosts', [])) %}  
  {%- if p.get('resourcemanager_on_namenode', False) %}
    {%- set resourcemanager_hosts = resourcemanager_hosts + p_hdfs.get('namenode_hosts', []) %}
  {%- endif %}
  {%- if p.get('nodemanagers_on_datanodes', False) %}
    {%- set nodemanager_hosts = nodemanager_hosts + p_hdfs.get('datanode_hosts', []) %}
  {%- endif %}
{%- endif %}

{%- set local_disks                  = salt['grains.get']('yarn_data_disks', ['/yarn_data']) %}
{%- set config_yarn_site             = gc.get('yarn-site', pc.get('yarn-site', {})) %}
{%- set config_capacity_scheduler    = gc.get('capacity-scheduler', pc.get('capacity-scheduler', {})) %}
# these are system accounts blacklisted with the YARN LCE
{%- set banned_users                 = gc.get('banned_users', pc.get('banned_users', ['hdfs','yarn','mapred','bin'])) %}

{%- set is_resourcemanager           = salt['match.' ~ targeting_method](resourcemanager_target) %}
{%- set is_nodemanager               = salt['match.' ~ targeting_method](nodemanager_target) %}

{%- set is_resourcemanager_in_pillar = [] %}
{%- set is_nodemanager_in_pillar     = [] %}

{%- if not is_resourcemanager %}
  {%- for minion_host in minion_hosts %}
    {%- if minion_host in resourcemanager_hosts %}
      {%- do is_resourcemanager_in_pillar.append(True) %}
      {% break %}
    {%- endif %}
  {%- endfor %}
{%- endif %}

{%- if not is_nodemanager %}
  {%- for minion_host in minion_hosts %}
    {%- if minion_host in nodemanager_hosts %}
      {%- do is_nodemanager_in_pillar.append(True) %}
      {% break %}
    {%- endif %}
  {%- endfor %}
{%- endif %}

{%- if is_resourcemanager_in_pillar %}
  {%- set is_resourcemanager = True %}
{%- endif %}

{%- if is_nodemanager_in_pillar %}
  {%- set is_nodemanager = True %}
{%- endif %}

{%- if ha_cluster_id == None %}
  {%- set ha_cluster_id = 'hdfscluster' %}
{%- endif %}

{%- set yarn = {} %}
{%- do yarn.update({ 'resourcetracker_port'        : resourcetracker_port,
                     'scheduler_port'              : scheduler_port,
                     'resourcemanager_port'        : resourcemanager_port,
                     'resourcemanager_webapp_port' : resourcemanager_webapp_port,
                     'resourcemanager_admin_port'  : resourcemanager_admin_port,
                     'resourcemanager_hosts'       : resourcemanager_hosts,
                     'nodemanager_port'            : nodemanager_port,
                     'nodemanager_webapp_port'     : nodemanager_webapp_port,
                     'nodemanager_localizer_port'  : nodemanager_localizer_port,
                     'local_disks'                 : local_disks,
                     'first_local_disk'            : local_disks|sort()|first(),
                     'config_yarn_site'            : config_yarn_site,
                     'config_capacity_scheduler'   : config_capacity_scheduler,
                     'banned_users'                : banned_users,
                     'is_resourcemanager'          : is_resourcemanager,
                     'is_nodemanager'              : is_nodemanager,
                     'ha_cluster_id'               : ha_cluster_id,
                   }) %}
