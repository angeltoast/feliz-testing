#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 14th October 2017

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful, but
#      WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#            General Public License for more details.

# A copy of the GNU General Public License is available from the Feliz2
#        page at http://sourceforge.net/projects/feliz2/files
#        or https://github.com/angeltoast/feliz2, or write to:
#                 The Free Software Foundation, Inc.
#                  51 Franklin Street, Fifth Floor
#                    Boston, MA 02110-1301 USA

# In this module - settings for partitioning:
# ------------------------    ------------------------
# Functions           Line    Functions           Line
# ------------------------    ------------------------
# CheckParts            41    EditLabel           362
# BuildLists           117    AllocateRoot        399
# Partitioning         163    CheckPartition      450
# ChooseDevice         199    AllocateSwap        462   
# partition_maker      248    NoPartitions        519
# autopart             290    SetSwapFile         536
# ChoosePartitions     335    MorePartitions      556
# select_filesystem    350    MakePartition       593
#                             PartitionMenu       648
# ------------------------    ------------------------

function CheckParts()   # Called by feliz.sh
{ # Test for existing partitions

  # Partitioning menu options="leave cfdisk guided auto"
  Translate "Choose from existing partitions"
  LongPart1="$Result"
  Translate "Open cfdisk so I can partition manually"
  LongPart2="$Result"
  Translate "Guided manual partitioning tool"
  LongPart3="$Result"
  Translate "Allow feliz to partition the whole device"
  LongPart4="$Result"
  Title="Partitioning"

  ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1) # List of all partitions on all connected devices
  PARTITIONS=$(echo $ShowPartitions | wc -w)

  if [ $PARTITIONS -eq 0 ]; then          # If no partitions exist, offer options
    while [ $PARTITIONS -eq 0 ]
    do
      PrintOne "If you are uncertain about partitioning, you should read the Arch Wiki"
      PrintMany "There are no partitions on the device, and at least"
      if [ ${UEFI} -eq 1 ]; then          # Installing in UEFI environment
        PrintMany "two partitions are needed - one for EFI /boot, and"
        PrintMany "one partition is needed for the root directory"
        PrintMany "There is a guided manual partitioning option"
        PrintMany "or you can exit now to use an external tool"
      else                                # Installing in BIOS environment
        PrintMany "one partition is needed for the root directory"
      fi
      Message="${Message}\n"
      PrintMany "If you choose to do nothing now, the script will"
      PrintMany "terminate to allow you to partition in some other way"
 
      dialog --backtitle "$Backtitle" --title " $Title " --nocancel --menu "$Message" 24 70 4 \
        1 "$LongPart2" \
        2 "$LongPart3" \
        3   "$LongPart4" 2>output.file
      retval=$?
      if [ $retval -ne 0 ]; then return; fi
      Result=$(cat output.file)
      Result=$((Result+1))                # Because this menu excludes option 1
      Partitioning                        # Partitioning options
      
      if [ "$Result" = "$_Exit" ]; then   # Terminate
        dialog --backtitle "$Backtitle" --infobox "Exiting to allow you to partition the device" 6 30
        shutdown -h now
      fi
      # Check that partitions have been created
      ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1)
      PARTITIONS=$(echo $ShowPartitions | wc -w)
    done
    BuildLists                          # Generate list of partitions and matching array
  else                                  # There are existing partitions on the device
    BuildLists                          # Generate list of partitions and matching array
    Translate "Here is a list of available partitions"
    Message="\n               ${Result}:\n"
    
    for part in ${PartitionList}
    do
      Message="${Message}\n        $part ${PartitionArray[${part}]}"
    done

    dialog --backtitle "$Backtitle" --title " $Title " --nocancel --menu "$Message" 24 78 4 \
      1 "$LongPart1" \
      2 "$LongPart2" \
      3 "$LongPart3" \
      4 "$LongPart4" 2>output.file
    retval=$?

    if [ $retval -ne 0 ]; then return; fi
    Result=$(cat output.file)

    Partitioning        # Action user selection
  fi
}

function BuildLists() # Called by CheckParts to generate details of existing partitions
{ # 1) Produces a list of partition IDs, from which items are removed as allocated to root, etc.
  #    This is the 'master' list, and the two associative arrays are keyed to this.
  # 2) Saves any existing labels on any partitions into an associative array, Labelled[]
  # 3) Assembles information about all partitions in another associative array, PartitionArray

  # 1) Make a simple list variable of all partitions up to sd*99
                                         # | includes keyword " TYPE=" | select 1st field | ignore /dev/
    PartitionList=$(sudo blkid /dev/sd* | grep /dev/sd.[0-9] | grep ' TYPE=' | cut -d':' -f1 | cut -d'/' -f3) # eg: sdb1
    
  # 2) List IDs of all partitions with "LABEL=" | select 1st field (eg: sdb1) | remove colon | remove /dev/
    ListLabelledIDs=$(sudo blkid /dev/sd* | grep /dev/sd.[0-9] | grep LABEL= | cut -d':' -f1 | cut -d'/' -f3)
    # If at least one labelled partition found, add a matching record to associative array Labelled[]
    for item in $ListLabelledIDs
    do      
      Labelled[$item]=$(sudo blkid /dev/sd* | grep /dev/$item | sed -n -e 's/^.*LABEL=//p' | cut -d'"' -f2)
    done

  # 3) Add records to the other associative array, PartitionArray, corresponding to PartitionList
    for part in ${PartitionList}
    do
      # Get size and mountpoint of that partition
      SizeMount=$(lsblk -l | grep "${part} " | awk '{print $4 " " $7}')      # eg: 7.5G [SWAP]
      # And the filesystem:        | just the text after TYPE= | select first text inside double quotations
      Type=$(sudo blkid /dev/$part | sed -n -e 's/^.*TYPE=//p' | cut -d'"' -f2) # eg: ext4
      PartitionArray[$part]="$SizeMount $Type" # ... and save them to the associative array
    done
    # Add label and bootable flag to PartitionArray
    for part in ${PartitionList}
    do
      # Test if flagged as bootable
      Test=$(sfdisk -l 2>/dev/null | grep /dev | grep "$part" | grep '*')
      if [ -n "$Test" ]; then
        Bootable="Bootable"
      else
        Bootable=""
      fi
      # Read the current record for this partition in the array
      Temp="${PartitionArray[${part}]}"
      # ... and add the new data
      PartitionArray[${part}]="$Temp ${Labelled[$part]} ${Bootable}" 
      # eg: PartitionArray[sdb1] = "912M /media/elizabeth/Lubuntu dos Lubuntu 17.04 amd64"
      #               | partition | size | -- mountpoint -- | filesystem | ------ label ------- |
    done
}

function Partitioning()  # Called by CheckParts after user selects an action.
{ # Directs response to selected option
  case $Result in
    1) echo "Manual partition allocation" >> feliz.log  # Existing Partitions option
    ;;
    2) cfdisk 2>> feliz.log
      tput setf 0               # Change foreground colour to black temporarily to hide error message
      clear
      partprobe 2>> feliz.log   # Inform kernel of changes to partitions
      tput sgr0                 # Reset colour
      return                    # Restart partitioning
    ;;
    3) if [ ${UEFI} -eq 1 ]; then
        print_heading
        echo
        EasyEFI                 # New guided manual partitioning functions
        tput setf 0             # Change foreground colour to black temporarily to hide error message
        clear
        partprobe 2>> feliz.log #Inform kernel of changes to partitions
        tput sgr0               # Reset colour
        ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1)
      else
        GuidedMBR
        tput setf 0             # Change foreground colour to black temporarily to hide error message
        clear
        partprobe 2>> feliz.log # Inform kernel of changes to partitions
        tput sgr0               # Reset colour
      fi
    ;;
    4) ChooseDevice
    ;;
    *) not_found 10 50 "Error reported at function $FUNCNAME line $LINENO in $SOURCE0 called from $SOURCE1"

  esac
}

function ChooseDevice()  # Called from Partitioning or PartitioningEFI
{ # Choose device for autopartition
  AutoPart=0
  until [ ${AutoPart} -gt 0 ]
  do
    DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)
    # Count lines. If more than one disk, ask user which to use
    local Counter=$(echo "$DiskDetails" | wc -w)
    MenuVariable="$DiskDetails"
    UseDisk=""
    if [ $Counter -gt 1 ]
    then
      while [ -z $UseDisk ]
      do
        Translate "These are the available devices"
        Title="$Result"
        PrintOne "Which do you wish to use for this installation?"
        PrintMany "   (Remember, this is auto-partition, and any data"
        Translate "on the chosen device will be destroyed)"
        Message="${Message}\n      ${Result}\n"
        echo
        
        Menu 15 60
        if [ $retval -ne 0 ]; then return; fi
        UseDisk="${Result}"
      done
    else
      UseDisk=$DiskDetails
    fi

      Title="Warning"
      Translate "This will erase any data on"
      Message="${Result} /dev/${UseDisk}"
      PrintMany "Are you sure you wish to continue?"
      Message="${Message}\n${Result}"
  
      dialog --backtitle "$Backtitle" --title " $Title " --yesno "\n$Message" 10 55 2>output.file
      retval=$?
      case $retval in
      0) autopart 
          ;;
      1) UseDisk=""
          ;;
      *) not_found 10 50 "Error reported at function $FUNCNAME line $LINENO in $SOURCE0 called from $SOURCE1"
      esac
    return
  done
}

partition_maker() { # Called from autopart() for both EFI and BIOS systems
                    # Receives up to 4 arguments
                    # $1 is the starting point of the first partition
                    # $2 is size of root partition
                    # $3 if passed is size of home partition
                    # $4 if passed is size of swap partition
                    # Note that an appropriate partition table has already been created in autopart()
                    #   If EFI the /boot partition has also been created at /dev/sda1 and set as bootable
                    #   and the startpoint has been set to follow /boot
                    
  local StartPoint=$1                               # Local variable 

  # Set the device to be used to 'set x boot on'    # $MountDevice is numerical - eg: 1 in sda1
  MountDevice=1                                     # Start with first partition = [sda]1
                                                    # Make /boot at startpoint
  Parted "mkpart primary ext4 ${StartPoint} ${2}"   # eg: parted /dev/sda mkpart primary ext4 1MiB 12GiB
  Parted "set ${MountDevice} boot on"               # eg: parted /dev/sda set 1 boot on
  if [ ${UEFI} -eq 1 ]; then                        # Reset if installing in EFI environment
    MountDevice=2                                   # Next partition after /boot = [sda]2
  fi
  RootPartition="${GrubDevice}${MountDevice}"       # eg: /dev/sda1
  RootType="ext4"
  StartPoint=$2                                     # Increment startpoint for /home or /swap
  MountDevice=$((MountDevice+1))                    # Advance partition numbering for next step

  if [ $3 ]; then
    Parted "mkpart primary ext4 ${StartPoint} ${3}" # eg: parted /dev/sda mkpart primary ext4 12GiB 19GiB
    AddPartList[0]="${GrubDevice}${MountDevice}"    # eg: /dev/sda3  | add to
    AddPartMount[0]="/home"                         # Mountpoint     | array of
    AddPartType[0]="ext4"                           # Filesystem     | additional partitions
    Home="Y"
    StartPoint=$3                                   # Reset startpoint for /swap
    MountDevice=$((MountDevice+1))                  # Advance partition numbering
  fi

  if [ $4 ]; then
    Parted "mkpart primary linux-swap ${StartPoint} ${4}" # eg: parted /dev/sda mkpart primary linux-swap 31GiB 100%
    SwapPartition="${GrubDevice}${MountDevice}"
    MakeSwap="Y"
  fi
}

function autopart() # Called by ChooseDevice
{ # Consolidated automatic partitioning for BIOS or EFI environment
  GrubDevice="/dev/${UseDisk}"
  Home="N"                                          # No /home partition at this point
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}' | sed "s/G\|M\|K//g") # Get disk size
  tput setf 0                                       # Change foreground colour to black to hide error message
  clear

  # Create a new partition table
  if [ ${UEFI} -eq 1 ]; then                        # Installing in UEFI environment
    sgdisk --zap-all ${GrubDevice} &>> feliz.log    # Remove all existing filesystems
    wipefs -a ${GrubDevice} &>> feliz.log           # from the drive
    Parted "mklabel gpt"                            # Create new filesystem
    Parted "mkpart primary fat32 1MiB 513MiB"       # EFI boot partition
   # Parted "set 1 boot on"     # This is done in partition_maker
    StartPoint="513MiB"                             # For next partition
  else                                              # Installing in BIOS environment
    dd if=/dev/zero of=${GrubDevice} bs=512 count=1 # Remove any existing partition table
    Parted "mklabel msdos"                          # Create new filesystem
    StartPoint="1MiB"                               # For next partition
  fi

  # Decide partition sizes
  if [ $DiskSize -ge 40 ]; then                     # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-4))                     # /root 15 GiB, /swap 4GiB, /home from 18GiB
    partition_maker "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 30 ]; then                   # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-3))                     # /root 15 GiB, /swap 3GiB, /home 12 to 22GiB
    partition_maker "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 18 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-2))                        # /root 16 to 28GiB, /swap 2GiB
    partition_maker "${StartPoint}" "${RootSize}GiB" "" "100%"
  elif [ $DiskSize -gt 10 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-1))                        # /root 9 to 17GiB, /swap 1GiB
    partition_maker "${StartPoint}" "${RootSize}GiB" "" "100%"
  else                                              # ------ Swap file and /root partition only -----
    partition_maker "${StartPoint}" "100%" "" ""
    SwapFile="2G"                                   # Swap file
    SwapPartition=""                                # Clear swap partition variable
  fi
  partprobe 2>> feliz.log                           # Inform kernel of changes to partitions
  tput sgr0                                         # Reset colour
  AutoPart=1                                        # Set auto-partition flag to 'on'
}

function ChoosePartitions()  # Called by feliz.sh after CheckParts
{ # Calls AllocateRoot, AllocateSwap, NoPartitions, MorePartitions
  if [ $AutoPart -eq 0 ]; then
  
    RootPartition=""
    while [[ "$RootPartition" == "" ]]
    do
      AllocateRoot                      # User must select root partition
    done
                                        # All others are optional
    if [ -n "${PartitionList}" ]; then  # If there are unallocated partitions
      AllocateSwap                      # Display display them for user to choose swap
    else                                # If there is no partition for swap
      NoPartitions                      # Inform user and allow swapfile
    fi
    
    for i in ${PartitionList}           # Check contents of PartitionList
    do
      echo $i > output.file             # If anything found, echo to file
      break                             # Break on first find
    done
    Result="$(cat output.file)"         # Check for output
    if [ "${Result}" = "" ]; then       # If any remaining partitions
      MorePartitions                    # Allow user to allocate
      if [ $retval -ne 0 ]; then return; fi # Exit on user <cancel>
    fi
  fi
}

function select_filesystem()  # Called by AllocateRoot and MorePartitions (via MakePartition)
{ # User chooses filesystem from menu
  Translate "Please select the file system for"
  Title="$Result ${Partition}"
  PrintMany "It is not recommended to mix the btrfs file-system with others"
  MenuVariable="ext4 ext3 btrfs xfs"
  
  Menu $1 $2

  PartitionType="$Result"
}

function EditLabel() # Called by AllocateRoot, AllocateSwap & MorePartitions
{ # If a partition has a label, allow user to change or keep it
  Label="${Labelled[$1]}"
  
  if [ -n "${Label}" ]; then
    # Inform the user and accept input
    Translate "The partition you have chosen is labelled"
    Message="$Result '${Label}'"
    Translate "Keep that label"
    Keep="$Result"
    Translate "Delete the label"
    Delete="$Result"
    Translate "Enter a new label"
    Edit="$Result"

    dialog --backtitle "$Backtitle" --title " $PassPart " --menu "$Message" \
      24 50 3 \
      1 "$Keep" \
      2 "$Delete" \
      3 "$Edit" 2>output.file
    retval=$?
    if [ $retval -ne 0 ]; then return; fi
    Result="$(cat output.file)"  
    # Save to the -A array
    case $Result in
      1) Labelled[$PassPart]=$Label
      ;;
      2) Labelled[$PassPart]=""
      ;;
      3) Message="Enter a new label"                  # English.lan #87
        InputBox 10 40
        if [[ -z $Result || $retval -ne 0 ]]; then return; fi
        Labelled[$PassPart]=$Result
    esac
  fi
}

function AllocateRoot() # Called by ChoosePartitions
{ # Display partitions for user-selection of one as /root
  #  (uses list of all available partitions in PartitionList)

  if [ ${UEFI} -eq 1 ]; then      # Installing in UEFI environment
    AllocateEFI                   # First allocate the /boot partition (sets boot on for EFI)
  fi
  Remaining=""
  Partition=""
  PartitionType=""
  PrintOne "Please select a partition to use for /root"
  
  PartitionMenu
  if [ $retval -ne 0 ]; then 
    PartitionType=""
    return
  fi
  
  PassPart=${Result:0:4}          # eg: sda4
  MountDevice=${PassPart:3:2}     # Save the device number for 'set x boot on'
  Partition="/dev/$Result"
  RootPartition="${Partition}"

  # Before going to select_filesystem, check if there is an existing file system on the selected partition
  CheckPartition  # This sets variable CurrentType and starts the Message
  
  if [ -n ${CurrentType} ]; then
    PrintMany "You can choose to leave it as it is, but should"
    PrintMany "understand that not reformatting the /root"
    PrintMany "partition can have unexpected consequences"
  fi
  
  # Now select a filesystem
  select_filesystem  20 75      # This sets variable PartitionType
  
  if [ $retval -ne 0 ]; then    # User has cancelled the operation
    PartitionType=""            # PartitionType can be empty (will not be formatted)
  else
    PartitionType="$Result"
  fi
  
  RootType="${PartitionType}" 
  Label="${Labelled[${PassPart}]}"
  if [ -n "${Label}" ]; then
    EditLabel $PassPart
  fi

  if [ ${UEFI} -eq 0 ]; then                    # Installing in BIOS environment
    Parted "set ${MountDevice} boot on"         # Make /root bootable
  fi

  PartitionList=$(echo "$PartitionList" | sed "s/$PassPart//") # Remove the used partition from the list

}

function CheckPartition()
{ # Finds if there is an existing file system on the selected partition
  CurrentType=$(sudo blkid $Partition | sed -n -e 's/^.*TYPE=//p' | cut -d'"' -f2)

  if [ -n ${CurrentType} ]; then
    PrintOne "The selected partition"
    Translate "is currently formatted to"
    Message="$Message $Result $CurrentType"
    PrintMany "Reformatting it will remove all data currently on it"
  fi
}

function AllocateSwap()
{
  PrintOne "Select a partition for swap from the ones that"
  PrintMany "remain, or you can allocate a swap file"
  PrintMany "Warning: Btrfs does not support swap files"
  
  SwapPartition=""
  
  Translate "If you skip this step, no swap will be allocated"
  Title="$Result"

  SavePartitionList="$PartitionList"
  PartitionList="$PartitionList swapfile"
  
  SwapFile=""
  
  PartitionMenu
  if [ $retval -ne 0 ]; then return; fi
  case "$Result" in
  "swapfile") SetSwapFile
            SwapPartition=""
            return
  ;;
  *) SwapPartition="/dev/$Result"
    IsSwap=$(sudo blkid $SwapPartition | grep 'swap' | cut -d':' -f1)
    if [ -n "$IsSwap" ]; then
      Translate "is already formatted as a swap partition"
      Message="$SwapPartition $Result"
      PrintMany "Reformatting it will change the UUID, and if this swap"
      PrintMany "partition is used by another operating system, that"
      PrintMany "system will no longer be able to access the partition"
      PrintMany "Do you wish to reformat it?"
      MakeSwap="N"
      dialog --backtitle "$Backtitle" --title " $Title " --yesno "\n$Message" 13 70 2>output.file
      retval=$?
      if [ $retval -ne 0 ]; then return; fi
        MakeSwap="Y"
        Label="${Labelled[${Result}]}"
        if [ -n "${Label}" ]; then
          EditLabel "$PassPart"
        fi
    fi
    
    PartitionList="$SavePartitionList"                            # Restore PartitionList (without 'swapfile')
    
    if [ $Result != "swapfile" ]; then
      PartitionList=$(echo "$PartitionList" | sed "s/$Result//")  # Remove the used partition from the list
    fi
      
    if [ $SwapFile ]; then
      dailog --msgbox "Swap file = ${SwapFile}" 5 20
    elif [ $SwapPartition = "" ]; then
      Translate "No provision has been made for swap"
      dailog --msgbox "$Result" 6 30
    fi
  esac
}

function NoPartitions()
{ # There are no unallocated partitions
  PrintOne "There are no partitions available for swap"
  PrintMany "but you can allocate a swap file, if you wish"
  Title="Create a swap file?"

  dialog --backtitle "$Backtitle" --title " $Title " --yesno "\n$Message" 10 55 2>output.file
  retval=$?
  case $retval in
  0) SetSwapFile
    SwapPartition=""
   ;;
  *) SwapPartition=""
    SwapFile=""
  esac
}

function SetSwapFile()
{
  LoopRepeat="Y"
  while [ ${LoopRepeat} = "Y" ]
  do
    PrintOne "Allocate the size of your swap file"
    InputBox "M = Megabytes, G = Gigabytes [eg: 512M or 2G]: "
    RESPONSE="${Response^^}"
    # Check that entry includes 'M or G'
    CheckInput=$(grep "G\|M" <<< "${RESPONSE}" )
    if [ -z ${CheckInput} ]; then
      PrintOne "You must include M or G"
      SwapFile=""
    else
      SwapFile=$RESPONSE
      break
    fi
  done
}

function MorePartitions()
{ # If partitions remain unallocated, user may select for /home, etc
  local Elements=$(echo "$PartitionList" | wc -w)

  while [ $Elements -gt 0 ]
  do
    PrintOne "The following partitions are available"
    PrintMany "If you wish to use one, select it from the list"

    PartitionMenu

    case $retval in
    0) PassPart=${Result:0:4}
    ;;
    *) return
    esac

    Partition="/dev/$Part"
    MakePartition # Call function to complete details
    Label="${Labelled[${PassPart}]}"
    if [ -n "${Label}" ]; then
      EditLabel $PassPart
    fi

    PartitionList=$(echo "$PartitionList" | sed "s/$PassPart//") # Remove the used partition from the list
    Elements=$(echo "$PartitionList" | wc -w)

  done
  # Ensure that if AddPartList (the defining array) is empty, all others are too
  if [ -z ${#AddPartList[@]} ]
  then
    AddPartList=""
    AddPartMount=""
    AddPartType=""
  fi
}

function MakePartition()
{ # Called by MorePartitions
  # Add the selected partition to the array for extra partitions
  # 1) Save to AddPartList (eg: /dev/sda5)
  ExtraPartitions=${#AddPartList[@]}
  AddPartList[$ExtraPartitions]="${Partition}"
  CheckPartition   # Before going to select_filesystem, check the partition
  if [ ${CurrentType} ]; then
    PrintOne "You can choose to leave it as it is, by selecting Exit, but not"
    PrintMany "reformatting an existing partition can have unexpected consequences"
  fi
  # 2) Select filesystem
  select_filesystem
  AddPartType[$ExtraPartitions]="${PartitionType}"  # Add it to AddPartType list
  # 3) Get a mountpoint
  PartMount=""
  while [ ${PartMount} = "" ]
  do
    PrintOne "Enter a mountpoint for"
    Message="$Message ${Partition}\n(eg: /home) ... "
    
    InputBox 
    
    # Check that entry includes '/'
    CheckInput=${Response:0:1}        # First character of ${Response}
    case ${CheckInput} in
      '') PrintOne "You must enter a valid mountpoint"
          PartMount=""
          ;;
      *) if [ ${CheckInput} != "/" ]; then
            PartMount="/${Response}"
        else
            PartMount="${Response}"
        fi
    esac
    # Check that the mountpoint has not already been used
    MountPointCounter=0
    if [ -z ${AddPartMount} ]; then
      LoopRepeat="N"
    else
      # Go through AddPartMount checking each item against PartMount
      for MountPoint in ${AddPartMount}
      do
        MountPointCounter=$((MountPointCounter+1))
        if [ $MountPoint = $PartMount ]; then
          dialog --backtitle "$Backtitle" --msgbox "\nMountpoint ${PartMount} has already been used.\nPlease use a different mountpoint." 6 30
        else
          PartMount=""
        fi
      done
    fi
  done
  AddPartMount[$ExtraPartitions]="${PartMount}"
}

function PartitionMenu()
{ # Uses $PartitionList & ${PartitionArray[@]} to generate a menu
  declare -a ItemList=()                                    # Array will hold entire list
  Items=0
  for Item in $PartitionList
  do 
    Items=$((Items+1))
    ItemList[${Items}]="${Item}"                         # and copy each one to the array
    Items=$((Items+1))
    if [ "$Item" = "swapfile" ]; then
      ItemList[${Items}]="Use a swap file"
    else
      ItemList[${Items}]="${PartitionArray[${Item}]}"                            # Second element is required
    fi
  done

  dialog --backtitle "$Backtitle" --title " $Title " --menu \
      "$Message" \
      20 78 ${Items} "${ItemList[@]}" 2>output.file
  retval=$?
  Result=$(cat output.file)
}
