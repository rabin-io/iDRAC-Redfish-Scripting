#!/bin/bash -x

IDRAC_HOST=${1:?Missing host}
IDRAC_USER=root
IDRAC_PASS=calvin

# RAID controller common name, can be changed btween systems, but for now it's the same
RAID_CONTROLLER=RAID.Slot.1-1
PV_SUFFIX=Enclosure.Internal.0-1:RAID.Slot.1-1


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

get_all_vdisks
delete_all_vdisks

# Create a RAID 0 virtual disk for the OS
python CreateVirtualDiskREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" \
    --create ${RAID_CONTROLLER} \
    --raid-level 0 \
    --disks  Disk.Bay.8:${PV_SUFFIX},Disk.Bay.9:${PV_SUFFIX} \
    --name OS

# Set the OS virtual disk as the boot disk
set_boot_vdisk "$(get_all_vdisks)"

# Create a RAID 50 virtual disk for the storage
python CreateVirtualDiskREDFISH.py -ip ${IDRAC_HOST} -u "${IDRAC_USER}" -p "${IDRAC_PASS}" \
    --create ${RAID_CONTROLLER} \
    --raid-level 50 \
    --disks  Disk.Bay.0:${PV_SUFFIX},Disk.Bay.1:${PV_SUFFIX},Disk.Bay.2:${PV_SUFFIX},Disk.Bay.3:${PV_SUFFIX},Disk.Bay.4:${PV_SUFFIX},Disk.Bay.5:${PV_SUFFIX},Disk.Bay.6:${PV_SUFFIX},Disk.Bay.7:${PV_SUFFIX} \
    --name STORAGE
