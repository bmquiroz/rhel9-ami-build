#!/bin/bash
set -eux

yum install lvm -y

handle_directory() {
    local dir_path="$1"
    local backup_path="${dir_path}_backup"

    if [ -d "$dir_path" ]; then
        # Directory exists, make a backup
        echo "Directory $dir_path exists, creating a backup..."
        mv "$dir_path" "$backup_path"
    fi
    # Create the directory anew (this might be redundant if LVM mount will create it)
    mkdir -pv "$dir_path"
}

restore_backup() {
    local dir_path="$1"
    local backup_path="${dir_path}_backup"

    if [ -d "$backup_path" ]; then
        # Copy contents and permissions from backup to the original directory
        echo "Restoring data from $backup_path to $dir_path..."
        cp -a "$backup_path/"* "$dir_path/"
        # Remove the backup directory after restore
        rm -rf "$backup_path"
    fi
}

# Create directories or copy if they exist
handle_directory /home
handle_directory /opt
handle_directory /opt/Tanium
handle_directory /tmp
handle_directory /var
handle_directory /var/log
handle_directory /var/tmp
handle_directory /var/log/audit
handle_directory /apps
handle_directory /dump

pvcreate /dev/xvdg
vgcreate system /dev/xvdg

lvcreate --name home_lv --size 1GB system
lvcreate --name opt_lv --size 8GB system
lvcreate --name opt_tan_lv --size 15GB system
lvcreate --name tmp_lv --size 5GB system
lvcreate --name var_lv --size 10GB system
lvcreate --name log_lv --size 5GB system
lvcreate --name vtmp_lv --size 2GB system
lvcreate --name audit_lv  --size 2GB system
lvcreate --name apps_lv  --size 2GB system
lvcreate --name dump_lv  --size 4GB system

mkfs.xfs /dev/mapper/system-home_lv
mkfs.xfs /dev/mapper/system-opt_lv
mkfs.xfs /dev/mapper/system-opt_tan_lv
mkfs.xfs /dev/mapper/system-tmp_lv
mkfs.xfs /dev/mapper/system-var_lv
mkfs.xfs /dev/mapper/system-log_lv
mkfs.xfs /dev/mapper/system-vtmp_lv
mkfs.xfs /dev/mapper/system-audit_lv
mkfs.xfs /dev/mapper/system-apps_lv
mkfs.xfs /dev/mapper/system-dump_lv

mount -t xfs /dev/mapper/system-home_lv /home
mount -t xfs /dev/mapper/system-opt_lv /opt
mount -t xfs /dev/mapper/system-opt_tan_lv /opt
mount -t xfs /dev/mapper/system-tmp_lv /tmp
mount -t xfs /dev/mapper/system-var_lv /var
mount -t xfs /dev/mapper/system-log_lv /var/log
mount -t xfs /dev/mapper/system-vtmp_lv /var/tmp
mount -t xfs /dev/mapper/system-audit_lv /var/log/audit
mount -t xfs /dev/mapper/system-apps_lv /apps
mount -t xfs /dev/mapper/system-dump_lv /dump

restore_backup /home
restore_backup /opt
restore_backup /opt
restore_backup /tmp
restore_backup /var
restore_backup /var/log
restore_backup /var/tmp
restore_backup /var/log/audit
restore_backup /apps
restore_backup /dump

/usr/bin/echo '/dev/mapper/system-home_lv /home           xfs    nodev,nosuid        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-opt_lv /opt     xfs    nodev        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-opt_tan_lv /opt/Tanium          xfs    nodev        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-tmp_lv /tmp         xfs    nodev,noexec,nosuid        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-var_lv /var         xfs    nodev        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-log_lv /var/log         xfs    nodev,noexec,nosuid        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-vtmp_lv /var/tmp          xfs    nodev,noexec,nosuid        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-audit_lv /var/log/audit          xfs    nodev,noexec,nosuid        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-apps_lv /apps         xfs    nodev,noexec,nosuid        0 0' >> /etc/fstab
/usr/bin/echo '/dev/mapper/system-dump_lv /dump         xfs    nodev,noexec,nosuid        0 0' >> /etc/fstab

chmod 777 /tmp

df -h