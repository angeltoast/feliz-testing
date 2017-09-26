#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills
# Revision date: 8th July 2017

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
# -----------------------      ------------------------
# Functions          Line       Functions           Line
# -----------------------      ------------------------
# CheckParts           40       AllocateRoot        460
# BuildPartitionLists 130       CheckPartition      519
# Partitioning        225       AllocateSwap        527
# MakePartitionList   259       NoPartitions        610
# ChooseDevice        272       SetSwapFile         625
# AutoWarning         317
# partition_maker     350       MorePartitions      653
# autopart            380       MakePartition       708
# select_filesystem   420       UpdateArray         767
# EditLabel           437       SetLabel            792
# -----------------------      ------------------------

CheckParts() {  # Test for existing partitions
  ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1)
  local Counter=0
  for i in $ShowPartitions
  do
    Counter=$((Counter+1))
  done
  PARTITIONS=${Counter}
  if [ $PARTITIONS -eq 0 ]; then          # If no partitions exist, offer options
    print_heading
    while [ $PARTITIONS -eq 0 ]
    do
      OptionsLimit=3                      # This variable limits the options displayed in Partitioning()
      Echo
      PrintOne "If you are uncertain about partitioning, you should read the Arch Wiki"
      Echo
      PrintOne "There are no partitions on the device, and at least"
      if [ ${UEFI} -eq 1 ]; then          # Installing in UEFI environment
        PrintOne "two partitions are needed - one for EFI /boot, and"
        PrintOne "one partition is needed for the root directory"
        PrintOne "There is a guided manual partitioning option"
        PrintOne "or you can exit now to use an external tool"
      else                                # Installing in BIOS environment
        PrintOne "one partition is needed for the root directory"
      fi
      PrintOne "If you choose to do nothing now, the script will"
      PrintOne "terminate to allow you to partition in some other way"
      Echo
      if [ ${UEFI} -eq 1 ]; then
        PartitioningEFI                   # Partitioning options for EFI
      else
        Partitioning                      # Partitioning options for BIOS
      fi
      if [ "$Result" = "$_Exit" ]; then   # Terminate
        print_heading
        Echo
        PrintOne "Exiting to allow you to partition the device"
        Echo
        Restart
      fi
      # Check that partitions have been created
      ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1)
      Counter=0
      for i in $ShowPartitions
      do
        Counter=$((Counter+1))
      done
      PARTITIONS=${Counter}
    done
    BuildPartitionLists                 # Generate an array of partitions - this is a first call
  else                                  # There are existing partitions on the device
    OptionsLimit=4                      # This variable is set to 3 if there are no partitions
    print_heading
    PrintOne "Here is a list of available partitions"
    BuildPartitionLists                 # Generate an array of partitions - this is a first call
    Counter=0
    for part in ${PartitionList}
    do
      if [ $Counter = 0 ]; then
        PrintOne "" "${PartitionArray[$Counter]}"
      else
        PrintMany "" "${PartitionArray[$Counter]}"
      fi
      Counter=$((Counter+1))
    done
    Echo
    if [ ${UEFI} -eq 1 ]; then          # Installing in UEFI environment
      PartitioningEFI                   # UEFI partitioning options
    else                                # Installing in BIOS environment
      Partitioning                      # BIOS partitioning options
    fi
    MakePartitionList                   # Regenerate the array of partitions
  fi
}

BuildPartitionLists() { # First called by CheckParts to generate details of existing partitions for display
                        # Then to prepare partition arrays for selection for root, swap and others
  # 1) Prepare two arrays from attached devices using blkid (installed with Feliz)
    # First an array of all partitions up to sd*99
    #                           |includes TYPE | select 1st field | ignore /dev/
    ListTypeIDs=$(blkid /dev/sd* | grep ' TYPE' | cut -d':' -f1 | cut -d'/' -f3) #2>/dev/null
    # Then a matching array of types
    #                          |includes TYPE |  select last field   | remove TYPE & quotes
    ListTypes=$(blkid /dev/sd* | grep ' TYPE' | awk '{print $(NF-1)}' | cut -d'"' -f2) #2>/dev/null
    # Add records from those two indexed arrays into the associative array
    local Counter=0
    for i in ${ListTypeIDs}
    do
      x=0
      for l in ${ListTypes}
      do
        if [ $x -eq $Counter ]; then
          FileSystem[$i]=$l # ... get the matching type
          break
        fi
        x=$((x+1))
      done
      Counter=$((Counter+1))
    done
  # 2) Find all up to sd*99 with LABEL | select 1st field | remove /dev/ | remove colon
  ListLabelledIDs=$(blkid /dev/sd* | grep LABEL | cut -d':' -f1 | cut -d'/' -f3)
  # If at least one labelled partition found, get a matching list of labels (remove quotes)
  if [ -n "$ListLabelledIDs" ]; then
    ListLabelledLabels=$(blkid /dev/sd* | grep LABEL | cut -d':' -f2 | cut -d'"' -f2)
  fi
  # Add records from those two indexed arrays into associative array
  Counter=0
  for i in ${ListLabelledIDs}
  do
    x=0
    for l in ${ListLabelledLabels}
    do
      if [ $x -eq $Counter ]; then
        Labelled[$i]=$l # ... get the matching label
        break
      fi
      x=$((x+1))
    done
    Counter=$((Counter+1))
  done
  local HowManyLabelled="${#Labelled[@]}"
  # 3) Find any partitions flagged as bootable
  ListAll=$(sfdisk -l 2>/dev/null | grep /dev | grep '*' | cut -d' ' -f1 | cut -d'/' -f3)
  declare -a Flagged
  Counter=0
  for i in $ListAll
  do
    Flagged[${Counter}]="$i"
    Counter=$((Counter+1))
  done
  local HowManyFlagged="${#Flagged[@]}"
  # 4) Prepare list of short identifiers (sda1 sda2 ...)
  PartitionList=""
  ShowPartitions=$(lsblk -l | grep 'part' | cut -d' ' -f1)
  # 5) Run through short identifiers, checking the three arrays for a match
  Counter=0 # For count of partitions
  Label=""
  for part in ${ShowPartitions}
  do
  # First test Flagged
    local x=0
    until [ ${x} -eq ${HowManyFlagged} ]
    do
      if [ $part = "${Flagged[$x]}" ]; then
        Bootable="(Bootable)"
        break
      else
        Bootable=""
      fi
      x=$((x+1))
    done
    # Next test Labelled
    ThisPart=${Labelled[${part}]} # Find the record in Labelled that matches the current iteration
    if [ -n "${ThisPart}" ]; then
      Label="${ThisPart}"
    fi
    # Finally get the filesystem type
    ThisPart=${FileSystem[${part}]} # Find the record in FileSystem that matches the current iteration
    #          | add space after $part to maintain proper sort order | use fields 1, 4 & 7
    LongID=$(lsblk -l | grep "${part} " | awk '{print $1 " " $4 " " $7}')
    PartitionArray[${Counter}]="$LongID $ThisPart ${Label} ${Bootable}"
    Label=""
    # Save the short ID for later functions
    PartitionList="${PartitionList} ${part}"
    (( Counter+=1 ))
  done
  PARTITIONS=${Counter}
}

Partitioning() {
  local Proceed=""
  AutoPart=0 # Set flag to 'off' by default
  while [ -z $Proceed ]
  do
    OptionsList=""
    local Counter=1
    for Option in "${LongPart[@]}"
    do
      if [ $Counter -eq 1 ] && [ $OptionsLimit -eq 3 ]; then # 'Existing Partitions' option ignored if no partitions exist
        Counter=2
        continue
      fi
      Translate "$Option"
      LongOption[${Counter}]="$Result"
      OptionsList="$OptionsList $(echo $PartitioningOptions | cut -d' ' -f${Counter})"
      Counter=$((Counter+1))
    done
    listgen2 "$OptionsList" "$_Quit" "$_Ok $_Exit" "LongOption"
    if [ $OptionsLimit -eq 3 ]; then # 'Existing Partitions' option is to be ignored if no partitions exist
      Proceed=$((Response+1))
    else
      Proceed=$Response
    fi
    Echo
    case $Proceed in
      1) echo "Manual partition allocation" >> feliz.log  # Existing Partitions option
      ;;
      2) cfdisk 2>> feliz.log
        tput setf 0             # Change foreground colour to black temporarily to hide error message
        clear
        partprobe 2>> feliz.log # Inform kernel of changes to partitions
        tput sgr0               # Reset colour
        CheckParts              # Restart partitioning
      ;;
      3) GuidedMBR
      ;;
      4) ChooseDevice
      ;;
      *) not_found
        Proceed=""
        print_heading
    esac
  done
}

MakePartitionList() {
  # Call BuildPartitionLists function to generate an array of partitions
  # This is not a first call, so first empty the existing array
  local x=0
  local HowMany="${#PartitionArray[@]}"
  until [ ${x} -eq ${HowMany} ]
  do
    unset PartitionArray[$x]
    x=$((x+1))
  done
  BuildPartitionLists # Then rebuild
}

ChooseDevice() {
  # Called from Partitioning or PartitioningEFI
  AutoPart=0
  until [ ${AutoPart} -gt 0 ]
  do
    DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)
    # Count lines. If more than one disk, ask user which to use
    local Counter=0
    CountDisks=0
    for i in $DiskDetails
    do
      Counter=$((Counter+1))
      Drives[$Counter]=$i
    done
    if [ $Counter -gt 1 ]
    then
      UseDisk="" # Reset for user choice
      while [ -z $UseDisk ]
      do
        print_heading
        PrintOne "These are the available devices"
        PrintOne "Which do you wish to use for this installation?"
        PrintOne "(Remember, this is auto-partition, and any data"
        PrintOne "on the chosen device will be destroyed)"
        Echo
        listgen1 "$DiskDetails" "" "[ $_Ok ]"
        UseDisk="${Result}"
        AutoWarning
      done
    else
      UseDisk=$DiskDetails
      AutoWarning
    fi
  done
}

AutoWarning() {
  while :
  do
    print_heading
    Echo
    Translate "This will erase any data on"
    PrintOne "$Result" "${UseDisk}"
    PrintOne "Are you sure you wish to continue?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
    case $Response in
      "1" | "Y" | "y") autopart   # Consolidated auto-partitioning function
        break
        ;;
      "2" | "N" | "n") UseDisk=""
        break 2
        ;;
      *) not_found
    esac
  done
}

partition_maker() { # Called from autopart()

# Change to: $1 = StartPoint; $2 = Root (set boot on for BIOS); $3 (if exists) = Home ; $4 (if exists) = Swap

  local StartPoint=$1

  # Set the device to be used to 'set x boot on'
  if [ ${UEFI} -eq 1 ]; then                        # Installing in EFI environment
    MountDevice=2                                   # Next partition after /boot = [sda]2
  else
    MountDevice=1                                   # In BIOS = first partition = [sda]1
  fi

  Parted "mkpart primary ext4 ${StartPoint} ${2}"   # /root
  Parted "set ${MountDevice} boot on"               # Bootable
  RootPartition="${GrubDevice}${MountDevice}"       # Save
  RootType="ext4"
  StartPoint=$2                                     # Reset startpoint for /home or /swap
  MountDevice=$((MountDevice+1))                    # Advance partition numbering

  if [ $3 ]; then
    Parted "mkpart primary ext4 ${StartPoint} ${3}" # /home
    AddPartList[0]="${GrubDevice}${MountDevice}"    # /dev/sda3      | add to
    AddPartMount[0]="/home"                         # Mountpoint     | array of
    AddPartType[0]="ext4"                           # Filesystem     | additional partitions
    Home="Y"
    StartPoint=$3                                   # Reset startpoint for /swap
    MountDevice=$((MountDevice+1))                  # Advance partition numbering
  fi

  if [ $4 ]; then
    Parted "mkpart primary linux-swap ${StartPoint} ${4}" # /swap
    SwapPartition="${GrubDevice}${MountDevice}"
    MakeSwap="Y"
  fi
}

autopart() { # Consolidated partitioning for BIOS or EFI environment
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
    Parted "mkpart ESP fat32 1MiB 513MiB"           # EFI boot partition
    Parted "set 1 boot on"
    StartPoint="513MiB"                             # For next partition
  else                                              # Installing in BIOS environment
    dd if=/dev/zero of=${GrubDevice} bs=512 count=1 # Remove any existing partition table
    Parted "mklabel msdos"                          # Create new filesystem
    StartPoint="1MiB"                               # For next partition
  fi

  # Decide partition sizes
  if [ $DiskSize -ge 40 ]; then                     # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-19-4))
    partition_maker "${StartPoint}" "19GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 30 ]; then                   # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-3))
    partition_maker "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 18 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-2))
    partition_maker "${StartPoint}" "${RootSize}GiB" "" "100%"
  elif [ $DiskSize -gt 10 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-1))
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

ChoosePartitions() {
  if [ $AutoPart -eq 0 ]; then
    BuildPartitionLists                  # Prepare table of available partitions
    AllocateRoot                         # Allow user to select root partition
    if [ -n "${PartitionList}" ]; then   # If there are unallocated partitions
      AllocateSwap                       # Display display them for user to choose swap
    else                                 # If there is no partition for swap
      NoPartitions                       # Inform user and allow swapfile
    fi
    if [ -n "${PartitionList}" ]; then   # Check contents of PartitionList again
      MorePartitions                     # Allow user to allocate any remaining partitions
    fi
  fi
}

select_filesystem() { # User chooses filesystem from list in global variable ${TypeList}
  local Counter=0
  Translate "Please select the file system for"
  PrintOne "$Result" "${Partition}"
  PrintOne "It is not recommended to mix the btrfs file-system with others"
  Echo
  Translate "or choose Exit to leave it as it is"
  listgen1 "${TypeList}" "$Result" "$_Ok $_Exit"
  if [ "$Result" = "$_Exit" ]; then
    PartitionType=""
  else
    for i in ${TypeList}
    do
      Counter=$((Counter+1))
      if [ $Counter -eq $Response ]
      then
        PartitionType=$i
        break
      fi
    done
  fi
}

EditLabel() {
  Label="${Labelled[$1]}"
  if [ -n "${Label}" ]; then
    # Inform the user and accept input
    print_heading
    Echo
    Translate "The partition you have chosen is labelled"
    PrintOne "$Result" "'${Label}'"
    Echo
    PrintOne "If you wish to keep that label, enter 1            "
    PrintMany "If you wish to delete the label, enter 2"
    PrintMany "If you wish to enter a new label, type it at the prompt"
    Echo
    Translate "Enter 1, 2 or a new label: "
    TPread "$Result" ": "
    # Save to the -A array
    case $Response in
      1) LabellingArray[$PartitionID]=$Label
      ;;
      2) LabellingArray[$PartitionID]=""
      ;;
      *) LabellingArray[$PartitionID]=$Response
    esac
  fi
}

AllocateRoot() {  # Manual allocation of an existing partition as /root
  # Display partitions for user-selection (uses list of all available partitions in PartitionList
  if [ ${UEFI} -eq 1 ]; then      # Installing in UEFI environment
    AllocateEFI                   # First allocate the /boot partition (sets boot on for EFI)
  fi
  print_heading
  Remaining=""
  local Counter=0
  Partition=""
  PartitionType=""
  PrintOne "Please select a partition to use for /root"
  Echo
  listgen2 "$PartitionList" "" "$_Ok" "PartitionArray"
  Reply=$Response
  PassPart=${Result:0:4}          # eg: sda4
  MountDevice=${PassPart:3:2}     # Save the device number for 'set x boot on'

  SetLabel "$PassPart"
  UpdateArray "$PassPart"         # Remove the selected partition from $PartitionArray[]
  Counter=0
  for i in ${PartitionList}
  do
    Counter=$((Counter+1))
    if [ $Counter -eq $Reply ]; then
      Partition="/dev/$i"
      RootPartition="${Partition}"
      # Before going to select_filesystem, check the partition
      CheckPartition
      if [ ${CurrentType} ]; then
        PrintOne "You can choose to leave it as it is, but should"
        PrintOne "understand that not reformatting the /root"
        PrintOne "partition can have unexpected consequences"
        Echo
      fi
      # Now select a filesystem
      select_filesystem
      RootType="${PartitionType}"                   # PartitionType can be empty (will not be formatted)
      Label="${Labelled[${PassPart}]}"
      if [ -n "${Label}" ]; then
        EditLabel $PassPart
      fi
    else
      Remaining="$Remaining $i"                     # Add next available partition
    fi
  done
  PartitionList=$Remaining                          # Replace original PartitionList with remaining options

  if [ ${UEFI} -eq 0 ]; then                        # Installing in BIOS environment
    Parted "set ${MountDevice} boot on"             # Make /root bootable
  fi

}

CheckPartition() {
  # Finds if there is an existing file system on the selected partition
  print_heading
  CurrentType=$(file -sL ${Partition} | grep "ext" | cut -c26-30)
  if [ ${CurrentType} ]; then
    Translate "The selected partition"
    P1="$Result"
    Translate "is currently formatted to"
    P2="$Result"
    PrintOne "$P1 ${Partition}" "$P2 ${CurrentType}"
    PrintOne "Reformatting it will remove all data currently on it"
  fi
}

AllocateSwap() {
  print_heading
  PrintOne "Select a partition for swap from the ones that"
  PrintOne "remain, or you can allocate a swap file"
  PrintOne "Warning: Btrfs does not support swap files"
  Echo
  Remaining=""
  local Counter=0
  SwapPartition=""
  PickFrom="$PartitionList Swapfile"
  SwapFile=""
  declare -a CopyArray # For passing to listgen2
  local Counter=0
  for p in "${PartitionArray[@]}"
  do
    CopyArray[${Counter}]=${PartitionArray[$Counter]}
    Counter=$((Counter+1))
  done
  CopyArray[${Counter}]="Swapfile"
  PrintOne "If you skip this step, no swap will be allocated"
  Echo
  listgen2 "$PickFrom" "" "$_Ok $_Exit" "CopyArray"
  Reply=$Response # Number of selected item
  if [ "$Result" ] && [ "$Result" != "Swapfile" ] && [ "$Result" != "$_Exit" ]; then # Short ID of item
    PassPart=${Result:0:4}
  fi
  Echo
  Counter=0
  for i in ${PickFrom}
  do
    Counter=$((Counter+1))
    if [ $Counter -eq $Reply ]
    then
      case $i in
        "$_Exit") SwapPartition=""
              break
        ;;
        "Swapfile") Echo
            SetSwapFile
            SwapPartition=""
            break
        ;;
        *) SwapPartition="/dev/$i"
          IsSwap=$(blkid $SwapPartition | grep 'swap' | cut -d':' -f1)
          if [ -n "$IsSwap" ]; then
            print_heading
            Translate "is already formatted as a swap partition"
            PrintOne "$i " "$Result"
            PrintOne "Reformatting it will change the UUID, and if this swap"
            PrintOne "partition is used by another operating system, that"
            PrintOne "system will no longer be able to access the partition"
            PrintOne "Do you wish to reformat it?"
            Echo
            Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
            case $Response in
              "1" | "$_Yes" | "y") MakeSwap="Y"
              ;;
              "2" | "$_No" | "n") MakeSwap="N"
              ;;
              *) MakeSwap="Y"
            esac
          fi
          Label="${Labelled[${PassPart}]}"
          if [ -n "${Label}" ]; then
            EditLabel "$PassPart"
            SetLabel "$PassPart"
          fi
          UpdateArray "$PassPart" # Remove the selected partition from $PartitionArray[]
      esac
    else
      if [ $i != "$_Exit" ] && [ $i != Swapfile ]; then
        Remaining="$Remaining $i" # Add next available partition
      fi
    fi
  done
  print_heading
  if [ $SwapPartition ]; then
    Translate "Swap partition"
    read_timed "$Result = $SwapPartition" 1
  elif [ $SwapFile ]; then
    read_timed "Swap file = ${SwapFile}" 1
  else
    Translate "No provision has been made for swap"
    read_timed "$Result" 1
  fi
  Echo
  PartitionList=$Remaining  # Replace original PartitionList with remaining options
}

NoPartitions() { # There are no unallocated partitions
  print_heading
  PrintOne "There are no partitions available for swap"
  PrintOne "but you can allocate a swap file, if you wish"
  Message="Create a swap file?"
  Echo
  Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
  Echo
  case $Response in
    "1" | "$_Yes" | "y") SetSwapFile
      SwapPartition=""
     ;;
    *) SwapPartition=""
      SwapFile=""
  esac
}

SetSwapFile() {
  LoopRepeat="Y"
  while [ ${LoopRepeat} = "Y" ]
  do
    Echo
    PrintOne "Allocate the size of your swap file"
    TPread "M = Megabytes, G = Gigabytes [eg: 512M or 2G]: "
    RESPONSE="${Response^^}"
    # Check that entry includes 'M or G'
    CheckInput=$(grep "G\|M" <<< "${RESPONSE}" )
    Echo
    if [ -z ${CheckInput} ]; then
      PrintOne "You must include M or G"
      SwapFile=""
    else
      SwapFile=$RESPONSE
      print_heading
      break
    fi
  done
}

MorePartitions() {
  local Elements=0
  AddedToRemaining=0
  TempPartList=""
  for i in ${PartitionList}
  do
    Elements=$((Elements+1))   # Count elements in PartitionList
  done

  while [ $Elements -gt 0 ]
  do
    print_heading
    Remaining=""
    PrintOne "The following partitions are available"
    PrintOne "If you wish to use one, select it from the list"
    PrintOne "or choose Exit to finish partitioning"
    Echo
    listgen2 "$PartitionList" "" "$_Ok $_Exit" "PartitionArray"
    if [ $Result != "$_Exit" ]; then
      PassPart=${Result:0:4}
      SetLabel "$Result"
      UpdateArray "$PassPart" # Remove the selected partition from $PartitionArray[]
    fi
    Echo
    for Part in ${PartitionList} # Iterate through the list
    do
      Partition=""
      PartitionType=""
      if [ $Part = $Result ] && [ $Result != "$_Exit" ]; then
        Partition="/dev/$Part"
        MakePartition # Call complete details
        Label="${Labelled[${PassPart}]}"
        if [ -n "${Label}" ]; then
          EditLabel $PassPart
        fi
      elif [ "$Part" != "$_Exit" ]; then    # Part is not selected and not 'Exit'
        Remaining="$Remaining $Part"        # Add unused partition to temp list
        AddedToRemaining=$((AddedToRemaining+1))
      fi
    done
    PartitionList=$Remaining  # Replace original PartitionList with temp list
    if [ "$Result" = "$_Exit" ]; then
      Elements=0
      break
    else
      Elements=$AddedToRemaining
    fi
  done
  # Ensure that if AddPartList (the defining array) is empty, all others are too
  if [ -z ${#AddPartList[@]} ]
  then
    AddPartList=""
    AddPartMount=""
    AddPartType=""
  fi
}

MakePartition() { # Called by MorePartitions
  # Add the selected partition to the array for extra partitions
  # 1) Save to AddPartList (eg: /dev/sda5)
  ExtraPartitions=${#AddPartList[@]}
  AddPartList[$ExtraPartitions]="${Partition}"
  CheckPartition   # Before going to select_filesystem, check the partition
  if [ ${CurrentType} ]; then
    PrintOne "You can choose to leave it as it is, by selecting Exit, but not"
    PrintOne "reformatting an existing partition can have unexpected consequences"
    Echo
  fi
  # 2) Select filesystem
  select_filesystem
  AddPartType[$ExtraPartitions]="${PartitionType}"  # Add it to AddPartType list
  # 3) Get a mountpoint
  LoopRepeat="Y"
  while [ ${LoopRepeat} = "Y" ]
  do
    print_heading
    Echo
    Translate "Enter a mountpoint for"
    PrintOne "$Result " "${Partition}"
    TPread "(eg: /home) ... /"
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
          read_timed "Mountpoint ${PartMount} has already been used. Please use a different mountpoint."
        else
          LoopRepeat="N"
          break
        fi
      done
    fi
    if [ ${LoopRepeat} = "N" ]
    then
      break
    fi
  done
  AddPartMount[$ExtraPartitions]="${PartMount}"
}

UpdateArray() { # Remove the selected partition from $PartitionArray[]
  # Called by AllocateRoot, AllocateSwap and MorePartitions
  # Receives a partition ("sda9") as argument
  local PassPart="$1"
  local Counter=0
  declare -a NewArray  # Empty NewArray
  # Build NewArray excluding the partition selected in the calling function
  for p in "${PartitionArray[@]}"
  do
    First=${p:0:4}          # Characters 1 to 5 of ${p}
    if [ $First ]; then
      if [ ${PassPart} != ${First} ]; then
        NewArray[${Counter}]="$p"
        (( Counter+=1 ))
      fi
    fi
  done
  # Then copy NewArray into PartitionArray
  local Counter=0
  for p in "${NewArray[@]}"
  do
    PartitionArray[${Counter}]=${NewArray[$Counter]}
    Counter=$((Counter+1))
  done
  unset PartitionArray[$Counter] # Delete the last element
}

SetLabel() { # Called from the root, swap and extra partitions routines
# ... each passing a single argument containing the partition ID
# Build an associative array of partitions (LabellingArray[]) as
# declared in f-var with other arrays
PartitionID=$1
local HowMany="${#PartitionArray[@]}"
local x=0
until [ ${x} -eq ${HowMany} ]
do
  CompareID=$(echo ${PartitionArray[${x}]} | awk '{print $1}')
  if [ -z ${CompareID} ]; then
    x=$((x+1))
    continue
  fi
  if [ ${CompareID} = ${PartitionID} ]; then # If the partition is in the array, it has a label
    Label=${PartitionArray[${x}]} # Save the label
  fi
  x=$((x+1))
done
}
