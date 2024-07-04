#!/bin/bash
set -eux

# cat > /etc/yum.repos.d/aon_rhel-9-for-x86_64-baseos-rpms.repo << EOF
# [aon_rhel-9-for-x86_64-baseos-rpms]
# name=AON - Red Hat Enterprise Linux 9 for x86_64 - BaseOS (RPMs)
# baseurl=http://nclavniapp00530.aonnet.aon.net/pub/rhel9/rhel-9-for-x86_64-baseos-rpms/
# enabled=1
# gpgcheck=0
# priority=1
# proxy=
# sslverify=0
# EOF

# cat > /etc/yum.repos.d/aon_rhel-9-for-x86_64-appstream-rpms.repo << EOF
# [aon_rhel-9-for-x86_64-appstream-rpms]
# name=AON - Red Hat Enterprise Linux 9 for x86_64 - AppStream (RPMs)
# baseurl=http://nclavniapp00530.aonnet.aon.net/pub/rhel9/rhel-9-for-x86_64-appstream-rpms/
# enabled=1
# gpgcheck=0
# priority=1
# proxy=
# sslverify=0
# EOF

/usr/bin/yum -y update

# Problems when Puppet configures sssd if not done.
systemctl disable sssd
rm -f /var/lib/sss/db/*

### Done. ###
echo '> Done'

# reboot