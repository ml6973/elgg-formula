{% from "elgg-formula/elgg/map.jinja" import elgg with context %}

{% set mysql_root_password = salt['pillar.get']('mysql:server:root_password', salt['grains.get']('server_id')) %}
{% set smtp_server = salt['pillar.get']('smtp:server', salt['grains.get']('server_id')) %}
{% set smtp_port = salt['pillar.get']('smtp:port', salt['grains.get']('server_id')) %}
{% set smtp_username = salt['pillar.get']('smtp:username', salt['grains.get']('server_id')) %}
{% set smtp_password = salt['pillar.get']('smtp:password', salt['grains.get']('server_id')) %}
{% set elgg_plugins = salt['pillar.get']('elgg:plugins', salt['grains.get']('server_id')) %}


#
# Install useful packages
#
elgg_packages:
  pkg:
    - installed
    - pkgs: {{ elgg.pkgs }}

apache2:
  service.running:
    - restart: True
    - watch:
      - file: /etc/php5/apache2/php.ini

#
# Enable mod_rewrite for Elgg
#
Apache mod_rewrite:
  apache_module.enable:
    - name: rewrite

#
# Copy sql backup template, set mysql password and update the database
#
/root/elgg_backup.sql:
  file.managed:
    - source: salt://elgg-formula/files/elab_ss.sql
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - defaults:
        data_root: /opt/eLab-data
        html_path: /var/www/html/sites/eLab-ss
        smtp_username: {{ smtp_username }}

{% if salt['grains.get']('mysql_password_updated') != True %}
set mysql password:
  cmd.run:
    - name: mysqladmin -u root password {{ mysql_root_password }}
  grains.present:
    - name: mysql_password_updated
    - value: True
{% endif %}

mysql -uroot -p{{ mysql_root_password }} < /root/elgg_backup.sql:
  cmd.run

#
# Clone git repo create data directory and copy web content
#
clone repo:
  git.latest:
    - name: https://github.com/cloudandbigdatalab/eLab-Social-Networking.git
    - target: /opt/eLab-Social-Networking
    - rev: master

/opt/eLab-data:
  file.directory:
    - user: www-data
    - group: www-data
    - makedirs: True

/var/www/html/sites/eLab-ss:
  file.directory:
    - makedirs: True

copy web content:
  cmd.run:
    - name: cp -rf /opt/eLab-Social-Networking/WebContent/. /var/www/html/sites/eLab-ss/
  file.directory:
    - name: /var/www/html/sites/eLab-ss
    - user: www-data
    - group: www-data
    - recurse:
      - user
      - group


/var/www/html/sites/eLab-ss/elgg-config/settings.php:
  file.managed:
    - source: salt://elgg-formula/files/settings.php
    - template: jinja
    - user: www-data
    - group: www-data
    - defaults:
        mysql_root_password: {{ mysql_root_password }}

#
# Clone elgg plugins
#
{% for plugin_name, plugin_info in grains['CODEBASE'].iteritems() %}
clone {{ plugin_info['REPO'] }}:
  git.latest:
    - target: /var/www/html/sites/eLab-ss/mod/{{ plugin_name }}
    - name: {{ plugin_info['REPO'] }}
    - rev: {{ plugin_info['BRANCH'] }}
{% endfor %}

/etc/apache2/sites-available/000-default.conf:
  file.managed:
    - source: salt://elgg-formula/files/000-default.conf

/etc/php5/apache2/php.ini:
  file.managed:
    - source: salt://elgg-formula/files/php.ini
    - template: jinja
    - defaults:
        smtp_server: {{ smtp_server }}
        smtp_port: {{ smtp_port }}
        smtp_username: {{ smtp_username }}
        smtp_password: {{ smtp_password }}



service apache2 restart:
  cmd.run
