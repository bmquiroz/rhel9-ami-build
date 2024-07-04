#################################################
######### lvm_script_puppet_roles.bash ##########
#################################################

### Change Log ###
### 05-19-2020 add puppet role mysql_819 ###
### 10-12-2020 Cutomized by AWS CE Team  ###

##############################
######### FUNCTIONS ##########
##############################


###########################################
### Function To Add Directories To Path ###
###########################################

add_to_PATH () {

  for dir; do
    d=$(cd -- "$dir" 2>/dev/null && { pwd -P || pwd; })   # canonicalize symbolic links
    if [ -z "$dir" ]; then continue; fi  # skip nonexistent directory
    case ":$PATH:" in
      *":$dir:"*) :;;
      *) PATH=$PATH:$dir;;
    esac
  done

}

##################################################
### Function To Find Disk With Specified Size ####
##################################################

find_disk () {

  DATA_DISK_SIZE_GB=$1
  DATA_DISK_SIZE_FDISK=$((DATA_DISK_SIZE_GB * 1024 * 1024 * 1024)) 

  # DATA_DISK_DEVICE=`fdisk -l | grep $DATA_DISK_SIZE_FDISK | awk '{print $2}' | sed -e 's/://'`
  DATA_DISK_DEVICE=`fdisk -l 2>/dev/null | grep $DATA_DISK_SIZE_FDISK | awk '{print $2}' | grep -v /dev/nvme0 | grep -v /dev/sda  | sed -e 's/://'`
  if [[ $DATA_DISK_DEVICE ]] 
  then
    echo "$DATA_DISK_DEVICE"
  else
    echo ""
  fi

}

##############################################
### Function To Create Partition On RHEL7 ####
##############################################

create_partition_RHEL7 () {

  DATA_DISK_DEVICE=$1

  echo "*** Creating Partition On ${DATA_DISK_DEVICE} ***"
  fdisk ${DATA_DISK_DEVICE} << EEOF
n
p
1


t
8e
w
EEOF
  echo "*** Partition Created On ${DATA_DISK_DEVICE} ***"

}

##############################################
### Function To Create Partition On RHEL6 ####
##############################################

create_partition_RHEL6 () {

  DATA_DISK_DEVICE=$1

  echo "*** Creating Partition On ${DATA_DISK_DEVICE} ***"
  fdisk ${DATA_DISK_DEVICE} << EEOF
u
c
n
p
1


t
8e
w
EEOF
  echo "*** Partition Created On ${DATA_DISK_DEVICE} ***"

}

####################################################################
### Run Appropriate Parition Function Depending On Major Version ###
####################################################################

create_partition () {

  DATA_DISK_DEVICE=$1
  MAJOR_VERSION=$(rpm -q --queryformat '%{RELEASE}' rpm | grep -o [[:digit:]]*\$)

  if [[ $MAJOR_VERSION == "6" ]] 
  then
    echo "*** Major Version is 6, Executing RHEL6 Parition Creation ***"
    create_partition_RHEL6 $DATA_DISK_DEVICE
  elif [[ $MAJOR_VERSION == "7" ]]
  then
    echo "*** Major Version is 7, Executing RHEL7 Parition Creation ***"
    create_partition_RHEL7 $DATA_DISK_DEVICE
  else
    echo "*** Not RHEL6 or RHEL7, Incompatible With This Script.  Exiting. ***"
    exit 1
  fi

}

#########################################
### Function To Create Volume Group  ####
#########################################

create_volume_group () {

  VG_NAME=$1
  DATA_DISK_SIZE_GB=$2
  EXTENT_SIZE=32

  ### Test To Ensure Size Is Number ###
  re='^[0-9]+$'
  if ! [[ $DATA_DISK_SIZE_GB =~ $re ]]
  then
   echo "*** Disk Size Is Not A Digit.  Exiting ***" 
   exit 1
  fi

  ###################
  #### Find Disk ####
  ###################

  echo "*** Looking For Disk With Size Of ${DATA_DISK_SIZE_GB} GB ***"
  DATA_DISK_DEVICE=$(find_disk ${DATA_DISK_SIZE_GB})
  if [[ $DATA_DISK_DEVICE ]]
  then
    echo "*** Found Disk With Size Of $DATA_DISK_SIZE_GB GB.  $DATA_DISK_DEVICE ***"
  else
    echo "*** Could Not Find Disk With Size Of $DATA_DISK_SIZE_GB GB.   Exiting. ***"
    exit 1
  fi

  ################################
  ### Create Partition On Disk ###
  ################################

  echo "*** Creating Partition On ${DATA_DISK_DEVICE} ***"
  echo
  create_partition $DATA_DISK_DEVICE

  ###################################
  #### Examine Partition Details ####
  ###################################

  echo "*** Checking Partition Details ***"
  NVME_VERIFICATION=$(echo ${DATA_DISK_DEVICE} | grep nvme )
  if [[ ${DATA_DISK_DEVICE} == ${NVME_VERIFICATION} ]]
  then
	PARTITION_DEVICE="${DATA_DISK_DEVICE}p1"
  else
    PARTITION_DEVICE="${DATA_DISK_DEVICE}1"
  fi
  fdisk -l | grep ${PARTITION_DEVICE}
  echo

  ################################
  #### Prepare Device For LVM ####
  ################################

  echo "*** Running pvcreate on ${DATA_DISK_DEVICE} ***"
  pvcreate ${PARTITION_DEVICE}

  #############################
  #### Create Volume Group ####
  #############################

  echo "*** Createing Volume Group ${VG_NAME} on  ${DATA_DISK_DEVICE} ***"
  vgcreate -s ${EXTENT_SIZE} ${VG_NAME} ${PARTITION_DEVICE}

}

###########################################
### Function To Create Logical Volume  ####
###########################################

create_logical_volume () {

  LVOL_SIZE_MB=$1
  LVOL_NAME=$2
  VG_NAME=$3
  MOUNT_POINT=$4

  #############################
  ### Create Logical Volume ###
  #############################

  echo "*** Creating Logical Volume ${LVOL_NAME} ***"
  lvcreate -L ${LVOL_SIZE_MB} -n ${LVOL_NAME} ${VG_NAME}

  #########################
  ### Create Filesystem ###
  #########################

  echo "*** Creating Filesystem on ${LVOL_NAME} ***"
  mkfs.ext4 /dev/${VG_NAME}/${LVOL_NAME}

  ##########################
  ### Create Mount Point ###
  ##########################

  echo "*** Creating Mount Point ${MOUNT_POINT} ***"
  if [ -z "$dir" ]; 
  then 
    echo "*** Mount Point Already Exists ***"
  else
    mkdir -p ${MOUNT_POINT}
  fi

  #############################
  ### Create Entry In fstab ###
  #############################

  echo "*** Creating fstab entry for ${MOUNT_POINT} ***"
  echo "/dev/mapper/${VG_NAME}-${LVOL_NAME} ${MOUNT_POINT}            ext4    defaults        1 2" >> /etc/fstab

  ####################
  ### Mount Volume ###
  ####################

  echo "*** Mounting on ${MOUNT_POINT} ***"
  mount ${MOUNT_POINT}

}



##################################
######### END FUNCTIONS ##########
##################################



###########################
###### BEGIN PROGRAM ######
###########################

###########################################################
### Add Appropriate Paths To Cover Both RHEL6 and RHEL7 ###
###########################################################
add_to_PATH /bin /sbin /usr/bin /usr/sbin /usr/local/sbin


################################################################################
### Check To Ensure One Arguemnt Was Passed - This Should Be The Puppet Role ###
################################################################################
if [[ $# -ne 1 ]]
then
    echo "*** Error: Must Specify One Argument (Puppet Role).  Exiting ***"
    exit 1
else
    PUPPET_ROLE="$1"
fi

echo "*** Puppet Role is $PUPPET_ROLE ***"

####################################################
### LVM Configuration Snippets For Each Role     ###
###                                              ###
### This Should Be All The Needs Modifying       ###
### When Adding A Role To The Script As Follows: ###
###                                              ###
### 1) Create Case Statement Entry For New Role  ###
### (Use Existing Case Entry As a Template)      ###
###                                              ###
### 2) Change DATA_DISK_SIZE_GB as appropriate   ###
###     for the role                             ###
###                                              ###
### 3) Change VG_NAME as appropriate for role    ###
###                                              ###
### 4) Modify create_logical_volume statements   ###
###     as appropriate for the role.   Ensure    ###
###     correct sizes and mount points for each  ###
###     be careful the size fits in the given    ###
###     space as there isn't error checking to   ###
###     cover this yet                           ###
####################################################

case $PUPPET_ROLE in

apache_server_62)

  ### Disk Size To Look For and VG Name ###
  DATA_DISK_SIZE_GB="300"
  VG_NAME="app"

  ### Create Volume Group ###
  create_volume_group $VG_NAME $DATA_DISK_SIZE_GB

  ### Create Logical Volumes ###
  create_logical_volume 51200 lvol01 ${VG_NAME} /apps/covalent
  create_logical_volume 51200 lvol02 ${VG_NAME} /apps/applications
  create_logical_volume 51200 lvol03 ${VG_NAME} /apps/application-logs
  create_logical_volume 51200 lvol04 ${VG_NAME} /apps/WWW
  create_logical_volume 51200 lvol05 ${VG_NAME} /apps/webtech
  create_logical_volume 25600 lvol06 ${VG_NAME} /usr/global
  ;;

jboss_64)

  ### Disk Size To Look For and VG Name ###
  DATA_DISK_SIZE_GB="200"
  VG_NAME="app"

  ### Create Volume Group ###
  create_volume_group $VG_NAME $DATA_DISK_SIZE_GB

  ### Create Logical Volumes ###
  create_logical_volume 51200 lvol01 ${VG_NAME} /apps/jboss
  create_logical_volume 51200 lvol02 ${VG_NAME} /apps/applications
  create_logical_volume 51200 lvol03 ${VG_NAME} /apps/application-logs
  create_logical_volume 25600 lvol04 ${VG_NAME} /usr/global
  ;;


mulesoft_4)

  ### Disk Size To Look For and VG Name ###
  DATA_DISK_SIZE_GB="175"
  VG_NAME="app"

  ### Create Volume Group ###
  create_volume_group $VG_NAME $DATA_DISK_SIZE_GB

  ### Create Logical Volumes ###
  create_logical_volume 51200 lvol01 ${VG_NAME} /apps/ipaas
  create_logical_volume 51200 lvol02 ${VG_NAME} /apps/applications
  create_logical_volume 51200 lvol03 ${VG_NAME} /apps/application-logs
  ;;


mysql_8|mysql_819)

  ### Disk Size To Look For and VG Name ###
  DATA_DISK_SIZE_GB="750"
  VG_NAME="app"

  ### Create Volume Group ###
  create_volume_group $VG_NAME $DATA_DISK_SIZE_GB

  ### Create Logical Volumes ###
  create_logical_volume 204800 lvol01 ${VG_NAME} /apps/mysql
  create_logical_volume 409600 lvol02 ${VG_NAME} /apps/mysql/data01
  create_logical_volume 51200 lvol03 ${VG_NAME} /apps/mysql/binlog01
  create_logical_volume 51200 lvol04 ${VG_NAME} /apps/mysql/workspace
  ;;

oracle_11|oracle_12|oracle_122|oracle_18|oracle_19)

  ### Disk Size To Look For and VG Name ###
  DATA_DISK_SIZE_GB="750"
  VG_NAME="app"

  ### Create Volume Group ###
  create_volume_group $VG_NAME $DATA_DISK_SIZE_GB

  ### Create Logical Volumes ###
  create_logical_volume 204800 lvol01 ${VG_NAME} /apps/oracle
  create_logical_volume 307200 lvol02 ${VG_NAME} /apps/oracle/data01
  create_logical_volume 51200 lvol03 ${VG_NAME} /apps/oracle/temp01
  create_logical_volume 51200 lvol04 ${VG_NAME} /apps/oracle/redo01
  create_logical_volume 51200 lvol05 ${VG_NAME} /apps/oracle/archives01
  create_logical_volume 51200 lvol06 ${VG_NAME} /apps/oracle/workspace
  ;;

postgres_10|postgres_11)

  ### Disk Size To Look For and VG Name ###
  DATA_DISK_SIZE_GB="650"
  VG_NAME="app"

  ### Create Volume Group ###
  create_volume_group $VG_NAME $DATA_DISK_SIZE_GB

  ### Create Logical Volumes ###
  create_logical_volume 204800 lvol01 ${VG_NAME} /apps/postgres
  create_logical_volume 307200 lvol02 ${VG_NAME} /apps/postgres/data01
  create_logical_volume 51200 lvol03 ${VG_NAME} /apps/postgres/archives01
  create_logical_volume 51200 lvol04 ${VG_NAME} /apps/postgres/workspace
  ;;

tcserver_29|tcserver_32|tcserver_4)

  ### Disk Size To Look For and VG Name ###
  DATA_DISK_SIZE_GB="200"
  VG_NAME="app"

  ### Create Volume Group ###
  create_volume_group $VG_NAME $DATA_DISK_SIZE_GB

  ### Create Logical Volumes ###
  create_logical_volume 51200 lvol01 ${VG_NAME} /apps/tcserver
  create_logical_volume 51200 lvol02 ${VG_NAME} /apps/applications
  create_logical_volume 51200 lvol03 ${VG_NAME} /apps/application-logs
  create_logical_volume 25600 lvol04 ${VG_NAME} /usr/global
  ;;


websphere_85)

  ### Disk Size To Look For and VG Name ###
  DATA_DISK_SIZE_GB="200"
  VG_NAME="app"

  ### Create Volume Group ###
  create_volume_group $VG_NAME $DATA_DISK_SIZE_GB

  ### Create Logical Volumes ###
  create_logical_volume 51200 lvol01 ${VG_NAME} /apps/WebSphere
  create_logical_volume 51200 lvol02 ${VG_NAME} /apps/applications
  create_logical_volume 51200 lvol03 ${VG_NAME} /apps/application-logs
  create_logical_volume 25600 lvol04 ${VG_NAME} /usr/global
  ;;

*)

  echo "*** Puppet Role ${PUPPET_ROLE} Has No Extra Disk Configuration.   Exiting ***"
  ;;

esac

########################################
### Show Mount Points After Creation ###
########################################

echo "*** Mount Points After Configuration Are As Follows: ***"
df
