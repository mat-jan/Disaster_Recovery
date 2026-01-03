#!/bin/bash
# --- CONFIGURATION ---
VM_ID="ID_YOUR_MACHINE"                                
STORAGE="local-lvm"                        
NAS_MOUNT="NAS MOUNT ADRESS"            
VHDX_PATH="$NAS_MOUNT/VHDX FILE NAME.vhdx"           
# --------------------
# 1. File verification
if [ ! -s "$VHDX_PATH" ]; then
    echo "ERROR: File $VHDX_PATH does not exist. Aborting."
    exit 1
fi
# 2. Remove old disk from configuration and storage
qm set $VM_ID --delete scsi0 --force > /dev/null 2>&1
OLD_DISK=$(pvesm list $STORAGE | grep "vm-$VM_ID-disk" | awk '{print $1}')
[ ! -z "$OLD_DISK" ] && pvesm free $OLD_DISK
# 3. Import and attach new disk
IMPORT_OUT=$(qm importdisk $VM_ID "$VHDX_PATH" $STORAGE 2>&1)
NEW_DISK=$(echo "$IMPORT_OUT" | grep -o "unused[0-9]\+" | head -1)
qm set $VM_ID --scsi0 $STORAGE:$NEW_DISK > /dev/null
qm set $VM_ID --boot order=scsi0 > /dev/null
echo "SUCCESS: Machine $VM_ID updated and ready to start on Proxmox."
