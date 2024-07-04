Nginx
=====

[![Build Status](https://travis-ci.org/ome/ansible-role-nginx.svg)](https://travis-ci.org/ome/ansible-role-nginx)
[![Ansible Role](https://img.shields.io/ansible/role/41090.svg)](https://galaxy.ansible.com/ome/nginx/)

Install upstream Nginx.

TODO: Add configuration options.


Role Variables
--------------

- `nginx_keep_default_configs`: If `true` keep the default site configuration files in `nginx/conf.d`, default `false` (disable them)
- `nginx_stable_repo`: If `false` use the mainline instead of stable repo, default `true`
- `nginx_version`: The packaged version of Nginx, optional, available versions depends on `nginx_stable_repo`. Not supported on Ubuntu.

Log rotation:

- `nginx_logrotate_interval`: Rotate log files at this interval, default `daily`
- `nginx_logrotate_backlog_size`: Number of backlog files to keep, default `366`


Author Information
------------------

ome-devel@lists.openmicroscopy.org.uk
