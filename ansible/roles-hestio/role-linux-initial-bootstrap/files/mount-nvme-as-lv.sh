#!/bin/env bash


get_nvme_devices() {
	local my_devs=$(lsblk -ld -o NAME,MODEL --noheadings | grep "Amazon EC2 NVMe Instance Storage" |  cut -f 1 -d" ")
	local my_return
	for i in $my_devs
	do
		if docker_storage $i
		then
			continue
		fi
		if root_disk $i
		then
			continue
		fi
		my_return="$i $my_return"
	done
	echo $my_return
}

root_disk() {
	local my_device=$1
	if $(df --output=source / | grep $my_device > /dev/null 2>&1)
	then
		return 0
	else
		return 1
	fi
}
docker_storage() {
	local my_device=$1
	if [ -z "$docker_vgname" ]
	then
		return 1
	fi
	if $(pvs -o pv_name,vg_name | grep $docker_vgname | grep $my_device > /dev/null 2>&1)
	then
		return 0
	else
		return 1
	fi
}

prep_disk() {
	local mydisk=$1
	#create_primary_partition $mydisk

	# Remove the FS headers from the volume as they make pvcreate think there is an FS on the device
	# wipefs -f -a $mydisk
	
	# Create the PV
	pvcreate -ff $mydisk
	
}

create_primary_partition() {
	local my_disk=$1
	# Create a primary partition for lvm
	parted ${my_disk} --script mklabel msdos mkpart primary 0% 100% set 1 lvm on
}

check_4_lvm(){
	if ! $(which pvs > /dev/null 2>&1 )
	then
		echo $0: WARNING: LVM commands not available
		exit 1
	fi
}

# Tidy up LVM
reset_lvm() {
	# This function is intended to remove all traces of LVM on the nvme drives.

	local my_device=$1
	local my_vgname my_lvnames my_lv my_pv_count
	# Remove nvme PV's 
	if $(pvs $my_device > /dev/null 2>&1)
	then

		my_vgname=$(pvs ${my_device} -o vg_name --noheadings | tr -d [:blank:] )
		my_lvnames=$(vgs $my_vgname -o lv_name --noheadings)
		my_pvcount=$(vgs $my_vgname -o pv_count --noheadings | tr -d [:blank:] )

		if [ ! -z "${my_vgname}" ]
		then
			for my_lv in $my_lvnames
			do
				lvremove -y /dev/${my_vgname}/${my_lv}
				if $(dmsetup info -C /dev/${my_vgname}/${my_lv} > /dev/null 2>&1)
				then
					dmsetup remove ${my_vgname}-${my_lv}
				fi
			done
			if [ $my_pvcount -le 1 ]
			then
				vgremove $my_vgname
				pvremove $my_device
			else
				vgreduce $my_vgname $my_device
			fi
		fi
		
	fi
}

docker_storage_setup="/etc/sysconfig/docker-storage-setup"
if [ -f $docker_storage_setup ]
then
	. $docker_storage_setup
	docker_vgname=$VG
fi


devices=$(get_nvme_devices)
full_name_devices=$( echo $devices | sed "s?nvme?/dev/nvme?g")

vg=ephemeralvg
lv=lvol0
mount_point=/tempdata


if $(df | grep ${mount_point} >/dev/null 2>&1)
then
	echo "$mount_point is mounted"
	exit 0
fi


for disk in $full_name_devices
do
	# Pre-requistite
	check_4_lvm
	# Tidy up disk
	reset_lvm $disk
done

for disk in $full_name_devices
do
	echo "Disk - $disk"
	prep_disk $disk
done	

if [ -n "$full_name_devices" ]
then

	# Create the VG
	vgcreate -f $vg $full_name_devices
	
	# Create the LV
	lvcreate -y -q -l 100%VG $vg -n $lv
	
	# Create a FS
	mkfs.ext4 -F /dev/$vg/$lv

	if [[ ! -d "$mount_point" ]]
	then
		mkdir $mount_point
	fi
	
	# Mount the FS
	mount /dev/${vg}/${lv} $mount_point
fi	
