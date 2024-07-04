#!/bin/bash
set -x

#ensure we have isexplor id on the machine.
groupadd -g 1621 unixtech
useradd -g unixtech -u 996379 -m -c "App ID - UNIXTECH" isexplor
if [ ! -d /home/isexplor/.ssh ] ; then 
   mkdir /home/isexplor/.ssh 
   chown isexplor:unixtech /home/isexplor/.ssh
   chmod 700 /home/isexplor/.ssh
fi
echo "from="10.236.40.203" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDGThEVKVabgKil+NOrzkw691KWvgr5iNnI1T6lGuOTeQ143mRijmNOAvyht5lqDI8FZ4I2sMePNiFMECE4zQUgkDphjkXH8zd04TytET55KSph13au+eFnaK+i0wRzpnc3O5QO4sFchvDBur/ykNgN9DahXAJlHcfFy+iXDeXFl8sMn5V2GDwostnDidjLsWJXjH8+A5j2R9jncPY4kMP65L7GSKYyIx42J6DbyGHE1SE8fCPyL6uWBY2O9X7Yj1G52yqE4G+NtuxSVPX8L4kWggWzkEr4ANVh5LY1sCAsLIgJp7d09b5CICw1AU2/QqryZVPdpm1yF+h9Sn9qibx/ isexplor@localserver" > /home/isexplor/.ssh/authorized_keys
chown isexplor:unixtech /home/isexplor/.ssh/authorized_keys
chmod 600 /home/isexplor/.ssh/authorized_keys
echo "%unixtech  ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/unixtech
chmod 0440 /etc/sudoers.d/unixtech

#also ensure cmdbscan id is on machine so can be discovered even if puppet has not run.
groupadd -g 999987654 cmdbscan
useradd -g cmdbscan -u 999878788 -m -c "App ID - CMDB Scan" cmdbscan
if [ ! -d /home/cmdbscan/.ssh ] ; then 
   mkdir /home/cmdbscan/.ssh 
   chown cmdbscan:cmdbscan /home/cmdbscan/.ssh
   chmod 700 /home/cmdbscan/.ssh
fi
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDjnJ5RyfVFBeARdImxve9VMbM3uvhFpA2XRY5C/BgFE/JO5YglVqUA393lTIu9kG/7G7A8AVq80WU5VwuHpOepgF5ChEaserfvauA84q7HbgQdtHt7SdBPwABFw1IoDULzhamEE7vF2Fy1838GEOaEgeQuaSvEwrlSP968vu3sF7bkO3jbGnCPFHwVRQm8XSiElgtwmzgo7Ri1rNEdTFErijqkw+fq62ILoPMRNLH0oSlUuC7loD5r/s1JQLgsL4Hghy8FZpd5MwlBakT9NGd8MmPEujClP3BJlVgPno9BxsiCZkeJ3N6ihXlFYnCcR6Hasnr31XxJqPH6kFkK//G7 cmdbscan@Aon" > /home/cmdbscan/.ssh/authorized_keys
chown cmdbscan:cmdbscan /home/cmdbscan/.ssh/authorized_keys
chmod 600 /home/cmdbscan/.ssh/authorized_keys
cat > /etc/sudoers.d/20_cmdbscan << EOF
cmdbscan   ALL = (root) NOPASSWD: /usr/bin/dmidecode,/bin/dmidecode,/sbin/dmidecode,/usr/sbin/dmidecode,/usr/bin/fdisk,/bin/fdisk,/sbin/fdisk,/usr/sbin/fdisk,/usr/bin/multipath,/bin/multipath,/sbin/multipath,/usr/sbin/multipath,/usr/bin/lsof,/bin/lsof,/sbin/lsof,/usr/sbin/lsof,/usr/bin/dmsetup,/bin/dmsetup,/sbin/dmsetup,/usr/sbin/dmsetup,/usr/bin/netstat,/bin/netstat,/sbin/netstat,/usr/sbin/netstat,/usr/bin/cat,/bin/cat,/sbin/cat,/usr/sbin/cat,/usr/bin/ifconfig,/bin/ifconfig,/sbin/ifconfig,/usr/sbin/ifconfig,/usr/bin/ethtool,/bin/ethtool/sbin/ethtool,/usr/sbin/ethtool,/usr/bin/mii-tool,/bin/mii-tool,/sbin/mii-tool,/usr/sbin/mii-tool,/usr/bin/ls,/bin/ls,/sbin/ls,/usr/sbin/ls,/usr/bin/stat,/bin/stat,/sbin/stat,/usr/sbin/stat
EOF
chmod 440 /etc/sudoers.d/20_cmdbscan

# Stop Logging
service rsyslogd stop
service auditd stop

# Clean Out Yum
yum clean all

# Remove Host SSH Keys
rm -rf /etc/ssh/ssh_host_*

# Remove udev rules
rm -rf /etc/udev/rules.d/70-*

# Remove MAC address from network configuration
#sed -i '/^HWADDR/d' /etc/sysconfig/network-scripts/ifcfg-eth0

# Remove Bigfix Logs
#rm -rf /var/opt/BESClient/__BESData/__Global/Logs/*

# Remove Temp Files
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /apps/tmp/*

# Remove SAR data
rm -rf /var/log/sa/*

# Remove System Logs
find /var/log -type f ! -name "lastlog" -exec truncate {} --size 0 \;

# Clear the lastlog
echo > /var/log/wtmp
echo > /var/log/btmp
echo > /var/log/lastlog

# Remove bash history
rm -rf ~root/.bash_history

# Remove kickstart file
rm -rf ~root/anaconda-ks.cfg

# Clean up /etc/hosts
sed -i '3,$d' /etc/hosts

#remove repos used in patching stage.
rm /etc/yum.repos.d/aon_*.repo

#Now we are clean index the system.
/usr/bin/updatedb
systemctl enable mlocate-updatedb.timer

#the next bit is to ensure small vagrant box size. 
id vagrant > /dev/null 2>&1
if [ $? -eq 0 ] ; then
   swapuuid="`/sbin/blkid -o value -l -s UUID -t TYPE=swap`";
   case "$?" in
     2|0) ;;
     *) exit 1 ;;
   esac

   if [ "x${swapuuid}" != "x" ]; then
       # Whiteout the swap partition to reduce box size
       # Swap is disabled till reboot
       swappart="`readlink -f /dev/disk/by-uuid/$swapuuid`";
       /sbin/swapoff "$swappart";
       dd if=/dev/zero of="$swappart" bs=1M 2>/dev/null || echo "dd exit code $? is suppressed";
       /sbin/mkswap -U "$swapuuid" "$swappart";
   fi

   for i in /apps /var /opt  /usr /tmp /var/tmp /var/log /var/log/audit /home /dump ; do
      dd if=/dev/zero of=${i}/junk bs=1M 2>/dev/null || echo "dd exit code $? is suppressed";
      rm -f $i/junk
   done
fi

sync
echo '> Shutting down the VM ...'
shutdown --poweroff
