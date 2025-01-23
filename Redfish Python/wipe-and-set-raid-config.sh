#!/bin/bash -x

IDRAC_HOST=${1:?Missing host}
IDRAC_USER=root
IDRAC_PASS=calvin

export SSHPASS=${IDRAC_PASS}

# RAID controller common name, can be changed btween systems, but for now it's the same
RAID_CONTROLLER=RAID.Slot.1-1
PV_SUFFIX=Enclosure.Internal.0-1:RAID.Slot.1-1

function racadm() {
    local SSHPASS=${IDRAC_PASS:-calvin}
    sshpass -e ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=keyboard-interactive,password $*
}

function get_pdisks_with_attributes() {
	local host_name=${1:?Missing Hostname}

	racadm.sh "${host_name}" storage get pdisks --refkey RAID.Slot.1-1 -o -p state,status,mediatype | awk '
/^Disk/ {
    if (disk != "") print disk, state, status, media
    disk = $0
    state = status = media = ""
}
/State/ { state = $3 }
/Status/ { status = $3 }
/MediaType/ { media = $3 }
END { print disk, state, status, media }
'
#Disk.Bay.0:Enclosure.Internal.0-1:RAID.Slot.1-1 Online Ok SSD
#Disk.Bay.1:Enclosure.Internal.0-1:RAID.Slot.1-1 Online Ok SSD
#Disk.Bay.2:Enclosure.Internal.0-1:RAID.Slot.1-1 Online Ok HDD
}

function generate_pdisk_list_from_index() {
    local indexs=($@)
    local delimiter=","
    local disks=()
    for i in "${indexs[@]}"; do
        disks+=("Disk.Bay.${i}:${PV_SUFFIX}")
    done

    # Join the array elements with the delimiter
    joined_string=$(IFS="$delimiter"; echo "${disks[*]}")

    # Print the result
    echo "$joined_string"
}

filter_disks() {
  local disk_type="$1"
  local matching_lines

  # filter lines and join them with a comma
  matching_lines=$(awk '/'$disk_type'/ {print $1}' <<< "$disk_list" | paste -sd "," -)

  echo "$matching_lines"
}

# # Sample input data
# disk_list="Disk.Bay.0:Enclosure.Internal.0-1:RAID.Slot.1-1 Online Ok SSD
# Disk.Bay.1:Enclosure.Internal.0-1:RAID.Slot.1-1 Online Ok SSD
# Disk.Bay.2:Enclosure.Internal.0-1:RAID.Slot.1-1 Ready Ok HDD
# Disk.Bay.9:Enclosure.Internal.0-1:RAID.Slot.1-1 Ready Ok HDD"
disk_list=$(get_pdisks_with_attributes ${IDRAC_HOST})

function get_all_vdisks() {
    python DeleteVirtualDiskREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" --get-virtualdisks ${RAID_CONTROLLER} | awk -F, '/Disk.Virtual/ {print $1}'
}


function delete_all_vdisks() {

    # python DeleteVirtualDiskREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" --get-virtualdisks ${RAID_CONTROLLER} | awk -F, '/Disk.Virtual/ {print $1}' \
    get_all_vdisks \
        | xargs -rtI{} python DeleteVirtualDiskREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" --delete {}
}


function get_all_pdisks() {
    python CreateVirtualDiskREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" --get-disks ${RAID_CONTROLLER} | awk '/Disk.Bay/ {print $3}' | tr -d ',' | sort
}

function set_boot_vdisk() {
    python SetBootVdREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" --set ${RAID_CONTROLLER} --boot-vd "${1:?Missing boot vdisk}"
}

function reset_controller() {
    python ResetConfigStorageREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" --reset-controller ${RAID_CONTROLLER}
}

echo "List all virtual disks"
get_all_vdisks

# echo "Delete all virtual disks"
#delete_all_vdisks

# Reset controller will wipe all vdisk, take ~3min
reset_controller

# Create a RAID 0 virtual disk for the OS using the SSDs
python CreateVirtualDiskREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" \
    --create ${RAID_CONTROLLER} \
    --raid-level 0 \
    --disks $(filter_disks "SSD") \
    --name OS

# alternative way to generate the disk list
# generate_pdisk_list_from_index 0 1
# generate_pdisk_list_from_index {2..9}

# Set the OS virtual disk as the boot disk
set_boot_vdisk "$(get_all_vdisks | head -1)"

# Create a RAID 50 virtual disk for the storage
python CreateVirtualDiskREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" \
    --create ${RAID_CONTROLLER} \
    --raid-level 50 \
    --disks $(filter_disks "HDD") \
    --name STORAGE

get_all_vdisks
