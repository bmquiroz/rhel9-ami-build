# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Red Hat Enterprise Linux Server 9

### Installs from the first attached CD-ROM/DVD on the system.
cdrom

### Performs the kickstart installation in text mode. 
### By default, kickstart installations are performed in graphical mode.
text

### Accepts the End User License Agreement.
eula --agreed

### Sets the language to use during installation and the default language to use on the installed system.
lang ${vm_guest_os_language}

### Sets the default keyboard type for the system.
keyboard --xlayouts='--vckeymap=${vm_guest_os_keyboard}'

### Configure network information for target system and activate network devices in the installer environment (optional)
### --onboot  enable device attached a boot time
### --device  device to be activated and / or configured 	with the network command
### --bootproto  method to obtain networking 	configuration for device (default dhcp)
### --noipv6  disable IPv6 on 	this device
###
### network --bootproto=static --ip=172.16.11.200 --netmask=255.255.255.0 --gateway=172.16.11.200 --nameserver=172.16.11.4 --hostname centos-linux-8
### network --bootproto=dhcp
network  --bootproto=static --ip=${vm_net_ip} --netmask=${vm_net_mask} --gateway=${vm_net_gw} --nameserver=${vm_net_dns} --hostname ${vm_name}

# standard encrypt root password for unixtech, change to your standard
rootpw --iscrypted ${vm_guest_os_rootpw}

### The selected profile will restrict root login.
### Add a user that can login and escalate privileges.
### user --name=${admin_username} --iscrypted --password=${admin_password} --groups=wheel
user --name=${admin_username} --password=${admin_password} --groups=wheel

### Configure firewall settings for the system.
### --enabled reject incoming connections that are not in response to outbound requests
### --ssh allow sshd service through the firewall
#firewall --enabled --ssh

### Sets up the authentication options for the system.
### The SSDD profile sets sha512 to hash passwords. Passwords are shadowed by default
### See the manual page for authselect-profile for a complete list of possible options.
authselect select sssd

### Sets the state of SELinux on the installed system.
### Defaults to enforcing.
selinux --permissive

# System services
services --enabled="chronyd,rpcbind,crontab"

### Sets the system time zone.
timezone ${vm_guest_os_timezone} --utc
logging

### Sets how the boot loader should be installed.
bootloader --append=" crashkernel=1G-4G:192M,4G-64G:256M,64G-:512M" --location=mbr

### Initialize any invalid partition tables found on disks.
zerombr

### Removes partitions from the system, prior to creation of new partitions. 
### By default, no partitions are removed.
### --linux erases all Linux partitions.
### --initlabel Initializes a disk (or disks) by creating a default disk label for all disks in their respective architecture.
clearpart --all --initlabel

### Modify partition sizes for the virtual machine hardware.
### Create primary system partitions.
part /boot --fstype xfs --size=1024 --label=BOOTFS
part /boot/efi --fstype vfat --size=1024 --label=EFIFS
part pv.01 --fstype="lvmpv" --size=100 --grow

### Create a logical volume management (LVM) group.
volgroup system --pesize=16384 pv.01

### Modify logical volume sizes for the virtual machine hardware.
### Create logical volumes.
logvol swap --fstype swap --name=swap_lv --vgname=system --size=8192 --label=SWAPFS
logvol / --fstype xfs --name=root_lv --vgname=system --size=12288 --label=ROOTFS
logvol /home --fstype xfs --name=home_lv --vgname=system --size=1024 --label=HOMEFS --fsoptions="nodev,nosuid"
logvol /opt --fstype xfs --name=opt_lv --vgname=system --size=8192 --label=OPTFS --fsoptions="nodev"
logvol /opt/Tanium --fstype xfs --name=opt_tan_lv --vgname=system --size=15360 --label=OPTTANFS --fsoptions="nodev"
logvol /tmp --fstype xfs --name=tmp_lv --vgname=system --size=5120 --label=TMPFS --fsoptions="nodev,noexec,nosuid"
logvol /var --fstype xfs --name=var_lv --vgname=system --size=10240 --label=VARFS --fsoptions="nodev"
logvol /var/log --fstype xfs --name=log_lv --vgname=system --size=5120 --label=LOGFS --fsoptions="nodev,noexec,nosuid"
logvol /var/tmp --fstype xfs --name=vtmp_lv --vgname=system --size=2048 --label=LOGFS --fsoptions="nodev,noexec,nosuid"
logvol /var/log/audit --fstype xfs --name=audit_lv --vgname=system --size=2048 --label=AUDITFS --fsoptions="nodev,noexec,nosuid"
logvol /apps --fstype=xfs --name=apps_lv --vgname=system --size=20480 --label=APPSFS 
logvol /dump --fstype=xfs --name=dump_lv --vgname=system --size=4096 --label=DUMPFS
### Modifies the default set of services that will run under the default runlevel.
services --enabled=NetworkManager,sshd
### Do not configure X on the installed system.
skipx
### Packages selection.
%packages
@base
@core
@security-tools
authselect-compat
chrony
expect
gdisk
hwloc
kernel-headers
kexec-tools
krb5-workstation
ksh
make
nc
net-tools
nfs-utils
nmap-ncat
numactl
open-vm-tools
perf
postfix
psmisc
rpcbind
sg3_utils
s-nail
sssd
sysstat
tmux
traceroute
# Packages required for Satellite bootstrap Do We need these?
ansible-core
perl
python3
wget
#removing below packages
-iwl*firmware #not sure about this one.
-crda
-fprintd*
-hunspell*
-iw*
-libfprint
-firewalld
%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

### Post-installation commands.
%post --erroronfail --log=/root/ks-post.log
proxy=http://serverproxy.aon.net:8888
# Add admin user to sudoers
echo "${admin_username} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${admin_username}
chmod 0440 /etc/sudoers.d/${admin_username}
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
systemctl enable vmtoolsd
systemctl start vmtoolsd

#make sure we don't get messages about enabling cockpit and remove issue.net
ln -sfn /dev/null /etc/motd.d/cockpit
ln -sfn /dev/null /etc/issue.d/cockpit.issue
if [ -f /etc/issue.net ] ; then 
   rm /etc/issue.net
fi

#we want a /apps/tmp with sticky bit set
if [ -d /apps ] ; then 
   mkdir /apps/tmp 
   chmod 1777 /apps/tmp
fi
# for some reason the /etc/localtime seems to be created world writable when specifying UTC
chmod 644 /etc/localtime

%end

### Reboot after the installation is complete.
### --eject attempt to eject the media before rebooting.
reboot --eject
