#!/bin/bash
###########################################################################
# Description: This script sets various CIS settings for MBSS compliance.
# we are using the os builtin openscap to do the heavy lifting but doing
# some things manually as well.
# Some things considered dangerous or problematic are not being implemented.
#
# The existance of the file /tmp/reboot will cause the script to set the
# selinux auto-relabel flag and reboot the server.
# if proxy is needed and running unattended then a file called
# /apps/tmp/oscap_proxy should be created prior to running the script with an
# export proxy= in it.
# This has been added as Azure should not have proxy variable set.
# The proxy is used by the openscap for retrieving xml updates, this is
# currently disabled pending the patch repos getting the lastest version
# of the security guide which fixes an issue.
# /apps/tmp/oscap_proxy will be removed after sourcing.
# if you are running interactively then you can just export the proxy
# variable before running if needed.
###########################################################################
#  Modification Log
# ------------------------------------------------------------------------
#   Date       Description of change                           Changed by
# ----------  ----------------------------------------------  ------------
# 2023-08-14  Creation of script                               Tony Horton
# 2023-11-22  modifications for Azure.                         Tony Horton
# 2023-11-27  add missing audit rule 4.1.3.6                   Tony Horton
# 2023-12-04  fix for incorrect log permissions.               Tony Horton
# 2023-12-04  fix for client_alive_count                       Tony Horton
# 2023-12-05  add boot password.                               Tony Horton
# 2023-12-12  add ipv6 kernel stuff                            Tony Horton
# 2023-12-13  fix some more audit rules.                       Tony Horton
# 2024-01-16  set 30 day lockout on all accounts with pwd      Tony Horton
# 2024-01-16  set umask for chronyd log files                  Tony Horton
# 2024-01-29  fix 5.3.7 and add sysstat umask for logs.        Tony Horton
# 2024-03-06  change ipv6 lockdown to per interface.           Tony Horton
# 2024-03-20  set umask for sysstat files.                     Tony Horton
# 2024-03-28  add check for postfix and krb5-workstation       Tony Horton
# 2024-05-07  remove Banner line from /etc/sshd_config.d       Tony Horton
# 2024-05-10  disable scp protocol completely. scp still will  Tony Horton
#             work using sftp protocol if to a compatible 
#             machine / client.
# 2024-05-23  fix issue with ipv6 disable if statement.        Tony Horton
# 2024-05-31  change aide cronjob.                             Tony Horton
# 2024-06-04  don't disable scp if vagrant.                    Tony Horton
###########################################################################

if [ -f /apps/tmp/oscap_proxy ] ; then
   . /apps/tmp/oscap_proxy
   rm -f /apps/tmp/oscap_proxy
fi

#check the oscap packages are present and install if not (missing in Azure)
dnf list installed openscap-scanner |grep -q openscap
if [ $? -ne 0 ] ; then
   dnf -y install openscap-scanner
fi
dnf list installed scap-security-guide |grep -q scap-security-guide
if [ $? -ne 0 ] ; then
   dnf -y install scap-security-guide
fi
#There are also two packages that should be present before oscap runs so that correct audit 
#rules get created. 
dnf list installed krb5-workstation |grep -q krb5-workstation
if [ $? -ne 0 ] ; then
   dnf -y install krb5-workstation
fi
dnf list installed postfix |grep -q postfix
if [ $? -ne 0 ] ; then
   dnf -y install postfix
fi

cd /root
/usr/bin/oscap xccdf eval  --tailoring-file /tmp/ssg-rhel9-ds-tailoring.xml --profile xccdf_net.aon_profile_cis_rhel9_customized --results scan_results.xml --report scan_report.html --fetch-remote-resources --remediate /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
#vagrant's password gets set to expire which breaks the vagrant process so need to undo that. 
#despite excluding the NOPASSWD option from the oscap it is still commenting out the vagrant rule
#so adding it back in to be safe.
id vagrant > /dev/null 2>&1
if [ $? -eq 0 ] ; then
   chage -M 9999 vagrant
   chage -d $(date -d yesterday +%F) vagrant
   echo "vagrant ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10_vagrant
   chmod 440 /etc/sudoers.d/10_vagrant
fi
#image factory uses admin userid make sure it can still login after lockdown. give it 15 days before expiring.
id admin > /dev/null 2>&1
if [ $? -eq 0 ] ; then
   chage -M 15 admin
   chage -d $(date -d yesterday +%F) admin
fi
#we also don't want roots password to be expired when first built. we should be building a new image every six months at least.
#set to just under a year (which is within CIS compliance)
chage -M 364 root
chage -d $(date -d yesterday +%F) root
#there are some things that oscap is not doing so we do them here. 
#using functions from Tony's original lockdown script.
concat_file() {
   if [ ! -f $2 ] ; then
      touch $2 #stop grep errors when file hasn't yet been created.
   fi
   grep -q -- "^[[:blank:]]*$1" $2 #don't do it more than once
   if [ $? -ne 0 ] ; then
      echo "$1" >> $2
   fi
}
UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)

#1.3.3 Ensure cryptographic mechanisms are used to protect the integrity of audit tools
concat_file "# Audit Tools" /etc/aide.conf
concat_file "/sbin/auditctl p+i+n+u+g+s+b+acl+xattrs+sha512" /etc/aide.conf
concat_file "/sbin/auditd p+i+n+u+g+s+b+acl+xattrs+sha512" /etc/aide.conf
concat_file "/sbin/ausearch p+i+n+u+g+s+b+acl+xattrs+sha512" /etc/aide.conf
concat_file "/sbin/aureport p+i+n+u+g+s+b+acl+xattrs+sha512" /etc/aide.conf
concat_file "/sbin/autrace p+i+n+u+g+s+b+acl+xattrs+sha512" /etc/aide.conf
concat_file "/sbin/augenrules p+i+n+u+g+s+b+acl+xattrs+sha512" /etc/aide.conf

#1.4.1 Ensure bootloader password is set
cat > /boot/grub2/user.cfg << EOF
GRUB2_PASSWORD=grub.pbkdf2.sha512.10000.D2595042A1D47449CEDEA415E7D27DC913BC3919A188BFC88A687F3EB69F3B76DC051EA0D6057316718A89289ED70A90C06405F0BDDAC34FCF1DE7CB67808D9F.FD3FECD8BDB483EE9E93AB601B6EBBE858FC72405B21021E85A517F90A12AA51ABE5DED8D0BF04EF9777150A3A97C56606AA76B9703A819D32A6BFE70DB712FD
EOF

#1.4.2 Ensure permissions on bootloader config are configured
chown root:root /boot/grub2/user.cfg
chmod u-x,og-rwx /boot/grub2/user.cfg
chown root:root /boot/grub2/grubenv
chmod u-x,og-rwx /boot/grub2/grubenv

#1.8.1.2 /etc/issue
echo "Authorized uses only. All activity may be monitored and reported." > /etc/issue
#1.8.1.3 etc/issue.net
echo "Authorized uses only. All activity may be monitored and reported." > /etc/issue.net
chown root:root /etc/issue.net
chmod u-x,go-wx /etc/issue.net
#We will also set our ssh banner here. 
cat > /etc/ssh/banner << EOF
  +---------------------------------------------------------------------------+
  | This private computer network and server system is protected by multiple  |
  | security systems.  Access to and use of this network and server system    |
  | requires explicit current written authorization.  Unauthorized access     |
  | to, or use of, or any attempt at unauthorized access, use, copying,       |
  | alteration, destruction or damage to, the system, its server, data,       |
  | programs or equipment is a violation of the Federal Computer Fraud and    |
  | Abuse Act of 1986, as amended, as well as applicable state laws and may   |
  | result in serious criminal or civil liability, or both.                   |
  +---------------------------------------------------------------------------+

EOF
concat_file "Banner /etc/ssh/banner"  "/etc/ssh/sshd_config"
#also oscap seems to set a line for Banner in sshd_config.d directory we want to remove that if it is present.
banner=$(grep -l Banner /etc/ssh/sshd_config.d/*)
if [ "$banner" != "" ] ; then
   sed -i -e '/Banner/d' $banner
fi

#2.1.2 Ensure chrony is configured
sed -i -e 's/OPTIONS=".*$/OPTIONS="-F 2 -u chrony"/' /etc/sysconfig/chronyd
#3.2.1 Ensure IP forwarding is disabled
concat_file "net.ipv6.conf.all.forwarding = 0" "/etc/sysctl.d/60-netipv6_sysctl.conf"
#3.3.1 Ensure source routed packets are not accepted
concat_file "net.ipv6.conf.all.accept_source_route = 0" "/etc/sysctl.d/60-netipv6_sysctl.conf"
concat_file "net.ipv6.conf.default.accept_source_route = 0" "/etc/sysctl.d/60-netipv6_sysctl.conf"
#3.3.2 Ensure ICMP redirects are not accepted
concat_file "net.ipv6.conf.all.accept_redirects = 0" "/etc/sysctl.d/60-netipv6_sysctl.conf"
concat_file "net.ipv6.conf.default.accept_redirects = 0" "/etc/sysctl.d/60-netipv6_sysctl.conf"
#3.3.7 Ensure Reverse Path Filtering is enabled
#think oscap is setting this incorrectly or not removing. 
sed -i -e 's/net.ipv4.conf.default.rp_filter.*$/net.ipv4.conf.default.rp_filter = 1/' /usr/lib/sysctl.d/50-default.conf
#3.3.9 Ensure IPv6 router advertisements are not accepted
concat_file "net.ipv6.conf.all.accept_ra = 0" "/etc/sysctl.d/60-netipv6_sysctl.conf"
concat_file "net.ipv6.conf.default.accept_ra = 0" "/etc/sysctl.d/60-netipv6_sysctl.conf"

#Some of the audit rules set by oscap conflict with those as specified in CIS and register as a fail.  We will delete the oscap created ones and replace with CIS compliant ones. 
#need to add a 00_ to the audit rules as otherwise they run later and delete all preceeding rules. 
rm /etc/audit/rules.d/audit.rules 
concat_file "## First rule - delete all" "/etc/audit/rules.d/00-init.rules"
concat_file "-D" "/etc/audit/rules.d/00-init.rules"
#4.1.1.3 Ensure audit_backlog_limit is sufficient
/usr/sbin/grubby --update-kernel ALL --args 'audit_backlog_limit=8192'
#4.1.3.1 Ensure changes to system administration scope (sudoers) is collected
rm /etc/audit/rules.d/actions.rules
concat_file "-w /etc/sudoers -p wa -k scope" /etc/audit/rules.d/50-scope.rules
concat_file "-w /etc/sudoers.d -p wa -k scope" /etc/audit/rules.d/50-scope.rules
#4.1.3.2 Ensure actions as another user are always logged
rm /etc/audit/rules.d/user_emulation.rules
concat_file "-a always,exit -F arch=b64 -C euid!=uid -F auid!=unset -S execve -k user_emulation" /etc/audit/rules.d/50-user_emulation.rules 
concat_file "-a always,exit -F arch=b32 -C euid!=uid -F auid!=unset -S execve -k user_emulation" /etc/audit/rules.d/50-user_emulation.rules
#4.1.3.3 Ensure events that modify the sudo log file are collected
sed -i -e '/var\/log\/sudo.log/d' /etc/audit/rules.d/logins.rules
concat_file "-w /var/log/sudo.log -p wa -k sudo_log_file" /etc/audit/rules.d/50-sudo.rules
#4.1.3.4 Ensure events that modify date and time information are collected
rm /etc/audit/rules.d/audit_time_rules.rules
rm /etc/audit/rules.d/time-change.rules
concat_file "-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change" /etc/audit/rules.d/50-time-change.rules
concat_file "-a always,exit -F arch=b32 -S adjtimex,settimeofday,clock_settime -k time-change" /etc/audit/rules.d/50-time-change.rules
concat_file "-w /etc/localtime -p wa -k time-change" /etc/audit/rules.d/50-time-change.rules
#4.1.3.5 Ensure events that modify the system's network environment are collected
rm /etc/audit/rules.d/audit_rules_networkconfig_modification.rules
concat_file "-a always,exit -F arch=b64 -S sethostname,setdomainname -k system-locale" /etc/audit/rules.d/50-system_local.rules
concat_file "-a always,exit -F arch=b32 -S sethostname,setdomainname -k system-locale" /etc/audit/rules.d/50-system_local.rules
concat_file "-w /etc/issue -p wa -k system-locale" /etc/audit/rules.d/50-system_local.rules
concat_file "-w /etc/issue.net -p wa -k system-locale" /etc/audit/rules.d/50-system_local.rules
concat_file "-w /etc/hosts -p wa -k system-locale" /etc/audit/rules.d/50-system_local.rules
concat_file "-w /etc/sysconfig/network -p wa -k system-locale" /etc/audit/rules.d/50-system_local.rules
concat_file "-w /etc/sysconfig/network-scripts/ -p wa -k system-locale" /etc/audit/rules.d/50-system_local.rules
#4.1.3.6 Ensure use of privileged commands are collected
UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)
AUDIT_RULE_FILE="/etc/audit/rules.d/50-privileged.rules"
NEW_DATA=()
for PARTITION in $(findmnt -n -l -k -it $(awk '/nodev/ { print $2 }' /proc/filesystems | paste -sd,) | grep -Pv "noexec|nosuid" | awk '{print $1}'); do
   readarray -t DATA < <(find "${PARTITION}" -xdev -perm /6000 -type f | awk -v UID_MIN=${UID_MIN} '{print "-a always,exit -F path=" $1 " -F perm=x -F auid>="UID_MIN" -F auid!=unset -k privileged" }')

   for ENTRY in "${DATA[@]}"; do 
      NEW_DATA+=("${ENTRY}")
   done
done
readarray &> /dev/null -t OLD_DATA < "${AUDIT_RULE_FILE}"
COMBINED_DATA=( "${OLD_DATA[@]}" "${NEW_DATA[@]}" ) 
printf '%s\n' "${COMBINED_DATA[@]}" | sort -u > "${AUDIT_RULE_FILE}"
#4.1.3.7 Ensure unsuccessful file access attempts are collected
UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)
if [ -n "${UID_MIN}" ] ; then 
   rm /etc/audit/rules.d/access.rules
   concat_file "-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=${UID_MIN} -F auid!=unset -k access" /etc/audit/rules.d/50-access.rules 
   concat_file "-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=${UID_MIN} -F auid!=unset -k access" /etc/audit/rules.d/50-access.rules 
   concat_file "-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=${UID_MIN} -F auid!=unset -k access" /etc/audit/rules.d/50-access.rules 
   concat_file "-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=${UID_MIN} -F auid!=unset -k access" /etc/audit/rules.d/50-access.rules 
else
   printf "ERROR: Variable 'UID_MIN' is unset.\n"
fi
#4.1.3.8 Ensure events that modify user/group information are collected
rm /etc/audit/rules.d/audit_rules_usergroup_modification.rules
concat_file "-w /etc/group -p wa -k identity" /etc/audit/rules.d/50-identity.rules
concat_file "-w /etc/passwd -p wa -k identity" /etc/audit/rules.d/50-identity.rules
concat_file "-w /etc/gshadow -p wa -k identity" /etc/audit/rules.d/50-identity.rules
concat_file "-w /etc/shadow -p wa -k identity" /etc/audit/rules.d/50-identity.rules
concat_file "-w /etc/security/opasswd -p wa -k identity" /etc/audit/rules.d/50-identity.rules
#4.1.3.9 Ensure discretionary access control permission modification events are collected
if [ -n "${UID_MIN}" ] ; then 
   rm /etc/audit/rules.d/perm_mod.rules  #also has rules from 4.1.3.10
   concat_file "-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod" /etc/audit/rules.d/50-perm_mod.rules
   concat_file "-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod" /etc/audit/rules.d/50-perm_mod.rules
   concat_file "-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod" /etc/audit/rules.d/50-perm_mod.rules
   concat_file "-a always,exit -F arch=b32 -S lchown,fchown,chown,fchownat -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod" /etc/audit/rules.d/50-perm_mod.rules
   concat_file "-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod" /etc/audit/rules.d/50-perm_mod.rules
   concat_file "-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod" /etc/audit/rules.d/50-perm_mod.rules
#4.1.3.10 Ensure successful file system mounts are collected
   concat_file "-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=unset -k mounts" /etc/audit/rules.d/50-mounts.rules
   concat_file "-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=unset -k mounts" /etc/audit/rules.d/50-mounts.rules
else
   printf "ERROR: Variable 'UID_MIN' is unset.\n"
fi
#4.1.3.11 Ensure session initiation information is collected
mv /etc/audit/rules.d/session.rules /etc/audit/rules.d/50-session.rules
#4.1.3.12 Ensure login and logout events are collected
#fix entries that oscap created. 
rm /etc/audit/rules.d/logins.rules
concat_file "-w /var/log/lastlog -p wa -k logins" /etc/audit/rules.d/50-login.rules
concat_file "-w /var/run/faillock -p wa -k logins" /etc/audit/rules.d/50-login.rules

#4.1.3.13 Ensure file deletion events by users are collected
if [ -n "${UID_MIN}" ] ; then 
   rm /etc/audit/rules.d/delete.rules
   concat_file "-a always,exit -F arch=b64 -S rename,unlink,unlinkat,renameat -F auid>=${UID_MIN} -F auid!=unset -F key=delete" /etc/audit/rules.d/50-delete.rules
   concat_file "-a always,exit -F arch=b32 -S rename,unlink,unlinkat,renameat -F auid>=${UID_MIN} -F auid!=unset -F key=delete" /etc/audit/rules.d/50-delete.rules
fi
#4.1.3.14 Ensure events that modify the system's Mandatory Access Controls are collected
rm /etc/audit/rules.d/MAC-policy.rules
concat_file "-w /etc/selinux -p wa -k MAC-policy" /etc/audit/rules.d/50-MAC-policy.rules
concat_file "-w /usr/share/selinux -p wa -k MAC-policy" /etc/audit/rules.d/50-MAC-policy.rules
#4.1.3.15 Ensure successful and unsuccessful attempts to use the chcon command are recorded
rm /etc/audit/rules.d/privileged.rules
if [ -n "${UID_MIN}" ] ; then 
   concat_file "-a always,exit -F path=/usr/bin/chcon -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng" /etc/audit/rules.d/50-perm_chng.rules
#4.1.3.16 Ensure successful and unsuccessful attempts to use the setfacl command are recorded
   concat_file "-a always,exit -F path=/usr/bin/setfacl -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng" /etc/audit/rules.d/50-perm_chng.rules
#4.1.3.17 Ensure successful and unsuccessful attempts to use the chacl command are recorded
   concat_file "-a always,exit -F path=/usr/bin/chacl -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng" /etc/audit/rules.d/50-perm_chng.rules
#4.1.3.18 Ensure successful and unsuccessful attempts to use the usermod command are recorded
   concat_file "-a always,exit -F path=/usr/sbin/usermod -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k usermod" /etc/audit/rules.d/50-usermod.rules
fi
#4.1.3.19 Ensure kernel module loading unloading and modification is collected
if [ -n "${UID_MIN}" ] ; then 
   rm /etc/audit/rules.d/modules.rules
   rm /etc/audit/rules.d/module-change.rules
   concat_file "-a always,exit -F arch=b64 -S init_module,finit_module,delete_module,create_module,query_module -F auid>=${UID_MIN} -F auid!=unset -k kernel_modules" /etc/audit/rules.d/50-kernel_modules.rules
   concat_file "-a always,exit -F path=/usr/bin/kmod -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k kernel_modules" /etc/audit/rules.d/50-kernel_modules.rules
fi
#4.1.3.20 Ensure the audit configuration is immutable
rm /etc/audit/rules.d/immutable.rules
concat_file "-e 2"  "/etc/audit/rules.d/99-finalize.rules"

/usr/sbin/augenrules --load
#4.1.4.5 Ensure audit configuration files are 640 or more restrictive
find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) -exec chmod u-x,g-wx,o-rwx {} +
#4.2.1.4 Ensure rsyslog default file permissions are configured
sed -ri '/^#### GLOBAL DIRECTIVES ####/a $DirCreateMode 0750' /etc/rsyslog.conf
sed -ri '/^#### GLOBAL DIRECTIVES ####/a $FileCreateMode 0640' /etc/rsyslog.conf
sed -ri '/^#### GLOBAL DIRECTIVES ####/a $Umask 0027' /etc/rsyslog.conf
#4.2.2.3 Ensure journald is configured to compress large log files oscap has '' 
sed -i -e '/^Compress=/d' /etc/systemd/journald.conf
concat_file "Compress=yes"  "/etc/systemd/journald.conf"
#4.2.2.4 Ensure journald is configured to write logfiles to persistent disk oscap has ''
sed -i -e '/^Storage=/d' /etc/systemd/journald.conf
concat_file "Storage=persistent"  "/etc/systemd/journald.conf"
#4.2.3 Ensure all logfiles have appropriate permissions and ownership
#code from CIS document. fixed missing UID_MIN
UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)

find /var/log -type f | while read -r fname; do
   bname="$(basename "$fname")"
   fugname="$(stat -Lc "%U %G" "$fname")"
   funame="$(awk '{print $1}' <<< "$fugname")"
   fugroup="$(awk '{print $2}' <<< "$fugname")"
   fuid="$(stat -Lc "%u" "$fname")"
   fmode="$(stat -Lc "%a" "$fname")"
   case "$bname" in
      lastlog | lastlog.* | wtmp | wtmp.* | wtmp-* | btmp | btmp.* | btmp-*)
         ! grep -Pq -- '^\h*[0,2,4,6][0,2,4,6][0,4]\h*$' <<< "$fmode" && echo -e "- changing mode on \"$fname\"" && chmod ug-x,o-wx "$fname"
         ! grep -Pq -- '^\h*root\h*$' <<< "$funame" && echo -e "- changing owner on \"$fname\"" && chown root "$fname"
         ! grep -Pq -- '^\h*(utmp|root)\h*$' <<< "$fugroup" && echo -e "- changing group on \"$fname\"" && chgrp root "$fname"
         ;;
      secure | auth.log | syslog | messages)
         ! grep -Pq -- '^\h*[0,2,4,6][0,4]0\h*$' <<< "$fmode" && echo -e "- changing mode on \"$fname\"" && chmod u-x,g-wx,o-rwx "$fname"
         ! grep -Pq -- '^\h*(syslog|root)\h*$' <<< "$funame" && echo -e "- changing owner on \"$fname\"" && chown root "$fname"
         ! grep -Pq -- '^\h*(adm|root)\h*$' <<< "$fugroup" && echo -e "- changing group on \"$fname\"" && chgrp root "$fname"
         ;;
      SSSD | sssd)
         ! grep -Pq -- '^\h*[0,2,4,6][0,2,4,6]0\h*$' <<< "$fmode" && echo -e "- changing mode on \"$fname\"" && chmod ug-x,o-rwx "$fname"
         ! grep -Piq -- '^\h*(SSSD|root)\h*$' <<< "$funame" && echo -e "- changing owner on \"$fname\"" && chown root "$fname"
         ! grep -Piq -- '^\h*(SSSD|root)\h*$' <<< "$fugroup" && echo -e "- changing group on \"$fname\"" && chgrp root "$fname"
         ;;
      gdm | gdm3)
         ! grep -Pq -- '^\h*[0,2,4,6][0,2,4,6]0\h*$' <<< "$fmode" && echo -e "- changing mode on \"$fname\"" && chmod ug-x,o-rwx
         ! grep -Pq -- '^\h*root\h*$' <<< "$funame" && echo -e "- changing owner on \"$fname\"" && chown root "$fname"
         ! grep -Pq -- '^\h*(gdm3?|root)\h*$' <<< "$fugroup" && echo -e "- changing group on \"$fname\"" && chgrp root "$fname"
         ;;
      *.journal | *.journal~)
         ! grep -Pq -- '^\h*[0,2,4,6][0,4]0\h*$' <<< "$fmode" && echo -e "- changing mode on \"$fname\"" && chmod u-x,g-wx,o-rwx "$fname"
         ! grep -Pq -- '^\h*root\h*$' <<< "$funame" && echo -e "- changing owner on \"$fname\"" && chown root "$fname"
         ! grep -Pq -- '^\h*(systemd-journal|root)\h*$' <<< "$fugroup" && echo -e "- changing group on \"$fname\"" && chgrp root "$fname"
         ;;
      *)
         ! grep -Pq -- '^\h*[0,2,4,6][0,4]0\h*$' <<< "$fmode" && echo -e "- changing mode on \"$fname\"" && chmod u-x,g-wx,o-rwx "$fname"
         if [ "$fuid" -ge "$UID_MIN" ] || ! grep -Pq -- '(adm|root|'"$(id -gn "$funame")"')' <<< "$fugroup"; then
            if [ -n "$(awk -v grp="$fugroup" -F: '$1==grp {print $4}' /etc/group)" ] || ! grep -Pq '(syslog|root)' <<< "$funame"; then
               [ "$fuid" -ge "$UID_MIN" ] && echo -e "- changing owner on \"$fname\"" && chown root "$fname"
               ! grep -Pq -- '^\h*(adm|root)\h*$' <<< "$fugroup" && echo -e "- changing group on \"$fname\"" && chgrp root "$fname"
            fi
         fi
         ;;
   esac
done

#check if vmtoolsd is present and if so add a umask to fix world readable log file.
systemctl list-units|grep -q vmtoolsd
if [[ $? -eq 0 ]] && [[ ! -d /etc/systemd/system/vmtoolsd.service.d ]] ; then 
   mkdir /etc/systemd/system/vmtoolsd.service.d
   cat > /etc/systemd/system/vmtoolsd.service.d/umask.conf << EOF
[Service]
UMask=0027
EOF
fi 
#check if chronyd is present and if so add a umask to fix world readable log file.
systemctl list-units|grep -q chronyd
if [[ $? -eq 0 ]] && [[ ! -d /etc/systemd/system/chronyd.service.d ]] ; then 
   mkdir /etc/systemd/system/chronyd.service.d
   cat > /etc/systemd/system/chronyd.service.d/umask.conf << EOF
[Service]
UMask=0027
EOF
fi 
#check if sysstat is present and if so add a umask to fix world readable log file.
systemctl list-units|grep -q sysstat
if [ $? -eq 0 ] ; then 
   sed -ri 's/umask\s+022/umask 027/' /etc/sysconfig/sysstat
fi

#4.5.1.4 Ensure inactive password lock is 30 days or less
for i in $(grep -E '^[^:]+:[^!*]' /etc/shadow |awk -F : '{print $1}') ; do 
   chage --inactive 30 $i
done
#5.1.8 Ensure cron is restricted to authorized users
#oscap is not creating /etc/cron.allow
if [ ! -f /etc/cron.allow ] ; then
   echo root > /etc/cron.allow
   chown root:root /etc/cron.allow
   chmod 600 /etc/cron.allow
fi
if [ -f /etc/cron.deny ] ; then 
   rm /etc/cron.deny
fi
#5.1.9 Ensure at is restricted to authorized users (this isn't being set by oscap)
[ ! -e /etc/at.allow ] && echo root > /etc/at.allow
chown root:root /etc/at.allow
chmod u-x,go-rwx /etc/at.allow
#5.2.4 Ensure SSH access is limited 
#this will be overwritten by puppet. 
concat_file "DenyUsers bin daemon"  "/etc/ssh/sshd_config"
#5.2.20 Ensure SSH Idle Timeout Interval is configured
concat_file "ClientAliveInterval 300"  "/etc/ssh/sshd_config"
sed -i -e '/^ClientAliveCountMax/d' /etc/ssh/sshd_config
concat_file "ClientAliveCountMax 3"  "/etc/ssh/sshd_config"

#5.3.1 Create custom authselect profile
if [ ! -d /etc/authselect/custom/CIS ] ; then
   authselect create-profile CIS -b sssd --symlink-meta
fi
# we need two items from 5.5.5 done at this point so it goes into our custom authselect profile.
# any other customizations should be done at this point as well.
concat_file "session     optional                                     pam_umask.so" "/etc/authselect/custom/CIS/password-auth"
concat_file "session     optional                                     pam_umask.so" "/etc/authselect/custom/CIS/system-auth"
#5.5.1 Ensure password creation requirements are configured
for fn in system-auth password-auth; do
   file="/etc/authselect/custom/CIS/$fn"
   if ! grep -Pq -- '^\h*password\h+requisite\h+pam_pwquality.so(\h+[^#\n\r]+)?\h+.*enforce_for_root\b.*$' "$file"; then
      sed -ri 's/^\s*(password\s+requisite\s+pam_pwquality.so\s+)(.*)$/\1\2 enforce_for_root/' "$file"

   fi

   if grep -Pq -- '^\h*password\h+requisite\h+pam_pwquality.so(\h+[^#\n\r]+)?\h+retry=([4-9]|[1-9][0-9]+)\b.*$' "$file"; then
      sed -ri '/pwquality/s/retry=\S+/retry=3/' "$file"
   elif ! grep -Pq -- '^\h*password\h+requisite\h+pam_pwquality.so(\h+[^#\n\r]+)?\h+retry=\d+\b.*$' "$file"; then

      sed -ri 's/^\s*(password\s+requisite\s+pam_pwquality.so\s+)(.*)$/\1\2 retry=3/' "$file"
   fi
done
authselect apply-changes
#5.3.2 Select authselect profile
authselect select custom/CIS with-faillock without-nullok --force
authselect apply-changes
#5.3.7 Ensure access to the su command is restricted
if ! grep -Pq -- '^auth\s+required\s+pam_wheel\.so\s+use_uid\s+group=' /etc/pam.d/su; then
   if grep -Pq -- '^auth\s+required\s+pam_wheel\.so\s+use_uid' /etc/pam.d/su; then
      sed -ri '/^auth\s+required\s+pam_wheel\.so\s+use_uid/ s/$/ group=wheel/' /etc/pam.d/su
   else
      if grep -Pq -- '^#auth\s+required\s+pam_wheel\.so\s+use_uid' /etc/pam.d/su; then
         sed -i -e 's/#auth[[:space:]]\+required[[:space:]]\+pam_wheel.so[[:space:]]\+use_uid/auth\t\trequired\tpam_wheel.so\tuse_uid group=wheel/' /etc/pam.d/su
      fi
   fi
fi
#5.5.3 Ensure password reuse is limited
pwhistory()
{
   file=$1
   if ! grep -Pq -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwhistory\.so\h+([^#\n\r]+\h+)?remember=([5-9]|[1-9][0-9]+)\b.*$' "$file"; then
      if grep -Pq -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwhistory\.so\h+([^#\n\r]+\h+)?remember=\d+\b.*$' "$file"; then
         sed -ri 's/^\s*(password\s+(requisite|required|sufficient)\s+pam_pwhistory\.so\s+([^#\n\r]+\s+)?)(remember=\S+\s*)(\s+.*)?$/\1 remember=5 \5/' $file
      elif grep -Pq -- '^\h*password\h+(requisite|required|sufficient)\h+pam_pwhistory\.so\h+([^#\n\r]+\h+)?.*$' "$file"; then
         sed -ri '/^\s*password\s+(requisite|required|sufficient)\s+pam_pwhistory\.so/ s/$/ remember=5/' $file
      else
         sed -ri '/^\s*password\s+(requisite|required|sufficient)\s+pam_unix\.so/i password required pam_pwhistory.so remember=5 use_authtok' $file
      fi
   fi
   if ! grep -Pq -- '^\h*password\h+(requisite|required|sufficient)\h+pam_unix\.so\h+([^#\n\r]+\h+)?remember=([5-9]|[1-9][0-9]+)\b.*$' "$file"; then
      if grep -Pq -- '^\h*password\h+(requisite|required|sufficient)\h+pam_unix\.so\h+([^#\n\r]+\h+)?remember=\d+\b.*$' "$file"; then
         sed -ri 's/^\s*(password\s+(requisite|required|sufficient)\s+pam_unix\.so\s+([^#\n\r]+\s+)?)(remember=\S+\s*)(\s+.*)?$/\1 remember=5 \5/' $file
      else
         sed -ri '/^\s*password\s+(requisite|required|sufficient)\s+pam_unix\.so/ s/$/ remember=5/' $file
      fi
   fi
}

pwhistory "/etc/authselect/$(head -1 /etc/authselect/authselect.conf | grep 'custom/')/system-auth"
pwhistory "/etc/authselect/$(head -1 /etc/authselect/authselect.conf | grep 'custom/')/password-auth"
authselect apply-changes

#5.5.3 set TMOUT value, not using oscap one.
echo "readonly TMOUT=900 ; export TMOUT" > /etc/profile.d/tmout.sh
chmod 644  /etc/profile.d/tmout.sh

#5.6.5 Ensure default user umask is 027 or more restrictive
sed -ri 's/umask\s+022/umask 027/' /etc/bashrc
echo umask 027 > /etc/profile.d/umask.sh
chown root:root /etc/profile.d/umask.sh
chmod 644 /etc/profile.d/umask.sh

#set history format for command history.
echo 'export HISTTIMEFORMAT="%F %T "' > /etc/profile.d/bash_hist.sh
chmod 0644 /etc/profile.d/bash_hist.sh

#USERGROUPS_ENAB needs to be set to yes or puppet has issues creating accounts. 
sed -i -e 's/USERGROUPS_ENAB[[:space:]]\+no/USERGROUPS_ENAB\tyes/' /etc/login.defs

#set history format for command history.
echo 'export HISTTIMEFORMAT="%A %F %T "' > /etc/profile.d/bash_hist.sh

#Disable IPv6 as per Redhdat's recommended method.
#not using ipv6.disable=1 on kernel boot params as it can cause issues.
#some processes break or behave badly when disabled via boot param.
ifname=$(/usr/sbin/ifconfig |grep -e ens -e eth|grep -v ether|/usr/bin/awk -F : '{print $1}')
if [ "$ifname" != "" ] ; then
   cat > /etc/sysctl.d/ipv6.conf << EOF
# First, disable for all interfaces
net.ipv6.conf.all.disable_ipv6 = 1

# By default, we do not disable IPv6 on localhost, as it's important for multiple
# components. If you want to disable it anyway, change the following
# value to 1.
net.ipv6.conf.lo.disable_ipv6 = 0

# If using the sysctl method, the protocol must be disabled on all specific interfaces, as well.
EOF
   for i in $(echo $ifname) ; do
      concat_file "net.ipv6.conf.${i}.disable_ipv6 = 1" /etc/sysctl.d/ipv6.conf
      /usr/bin/nmcli con mod ${i} ipv6.method disabled
   done
else
   echo "could not determine interface name(s). IPv6 shutdown has not been performed"
fi

#We need iptables for puppet managed firewall. 
dnf -y install iptables-services

id vagrant > /dev/null 2>&1
if [ $? -ne 0 ] ; then #vagrant breaks if disabled.
   #disable scp protocol 
   touch  /etc/ssh/disable_scp
fi

#change aide cron job. oscap one generates mail to root which may be large.  
#we will write output to /var/log/aide/ make sure it exists.
if [ ! -d /var/log/aide ] ; then
   mkdir /var/log/aide
   chmod 700 /var/log/aide
fi
#remove oscap one and replace with our new entry.
#put day name in the output file so we have seven days worth that will auto overwrite.
sed -i -e '/\/usr\/sbin\/aide --check/d' /etc/crontab
echo "#job to run aide to check system integrity" > /etc/cron.d/aide_check
echo '05 4 * * * root /usr/sbin/aide --check > /var/log/aide/aide_check_$(/usr/bin/date +\%a).out' >> /etc/cron.d/aide_check
chmod 600 /etc/cron.d/aide_check


if [ -f /tmp/reboot ] ; then
   #make sure we fully relable the system for selinux
   rm /tmp/reboot
   touch /.autorelabel
   /usr/sbin/reboot
fi
