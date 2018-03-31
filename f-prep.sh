#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 30th March 2018

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.

# This program is distributed in the hope that it will be useful, but
#      WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#            General Public License for more details.

# A copy of the GNU General Public License is available from the Feliz2
#        page at http://sourceforge.net/projects/feliz2/files
#        or https://github.com/angeltoast/feliz2, or write to:
# The Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# In this module - functions for guided creation of a GPT or EFI partition table
#                  and functions for autopartitioning
# -----------------------      -----------------------      ----------------------
# SHARED Functions   Line      BIOS Functions     Line      EFI Functions     Line 
# -----------------------      -----------------------      ----------------------
# auto_warning         38      guided_MBR          271      guided_EFI         577
# prepare_partitions   54                                   guided_EFI_boot    620
# autopart             96      guided_MBR_root     313      guided_EFI_root    651
# select_filesystem   140      guided_MBR_swap     355      guided_EFI_swap    693
# allocate_all        163      guided_MBR_home     422      guided_EFI_home    760
# guided_device       171      action_MBR          467      action_EFI         807
# guided_disk_size    208
# guided_recalc       255
# -----------------------      -----------------------      ----------------------

function auto_warning
{
  message_first_line "This will erase any data on"
  Message="$Message" "${UseDisk}"
  message_subsequent "Are you sure you wish to continue?"
  dialog --backtitle "$Backtitle" --title " $title " \
    --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 9 50
  retval=$?
}

function autopart   # Consolidated fully automatic partitioning for BIOS or EFI environment
{                   # Called by f-part.sh/check_parts (after auto_warning)
  GrubDevice="/dev/${UseDisk}"
  Home="N"                                          # No /home partition at this point
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}' | sed "s/G\|M\|K//g") # Get disk size
  tput setf 0                                       # Change foreground colour to black to hide error message
  clear

read -p "f-prep $LINENO"

  # Create a new partition table
  if [ ${UEFI} -eq 1 ]; then                        # Installing in UEFI environment
    sgdisk --zap-all ${GrubDevice} &>> feliz.log    # Remove all existing filesystems
    wipefs -a ${GrubDevice} &>> feliz.log           # from the drive
    Parted "mklabel gpt"                            # Create new filesystem
    Parted "mkpart primary fat32 1MiB 513MiB"       # EFI boot partition
   # Parted "set 1 boot on"     # This is done in prepare_partitions
    StartPoint="513MiB"                             # For next partition
  else                                              # Installing in BIOS environment
    dd if=/dev/zero of=${GrubDevice} bs=512 count=1 # Remove any existing partition table
    Parted "mklabel msdos"                          # Create new filesystem
    StartPoint="1MiB"                               # For next partition
  fi

read -p "f-prep $LINENO"

  # Decide partition sizes
  if [ $DiskSize -ge 40 ]; then                     # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-4))                     # /root 15 GiB, /swap 4GiB, /home from 18GiB
    prepare_partitions "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 30 ]; then                   # ------ /root /home /swap partitions ------
    HomeSize=$((DiskSize-15-3))                     # /root 15 GiB, /swap 3GiB, /home 12 to 22GiB
    prepare_partitions "${StartPoint}" "15GiB" "${HomeSize}GiB" "100%"
  elif [ $DiskSize -ge 18 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-2))                        # /root 16 to 28GiB, /swap 2GiB
    prepare_partitions "${StartPoint}" "${RootSize}GiB" "" "100%"
  elif [ $DiskSize -gt 10 ]; then                   # ------ /root & /swap partitions only ------
    RootSize=$((DiskSize-1))                        # /root 9 to 17GiB, /swap 1GiB
    prepare_partitions "${StartPoint}" "${RootSize}GiB" "" "100%"
  else                                              # ------ Swap file and /root partition only -----
    prepare_partitions "${StartPoint}" "100%" "" ""
    SwapFile="2G"                                   # Swap file
    SwapPartition=""                                # Clear swap partition variable
  fi
  partprobe 2>> feliz.log                           # Inform kernel of changes to partitions
  tput sgr0                                         # Reset colour
  AutoPart="AUTO"                                   # Set auto-partition flag

read -p "f-prep $LINENO"

}

prepare_partitions() { # Called from autopart() for both EFI and BIOS systems
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

allocate_all() {
  Echo
  PrintOne "Please enter the desired size"
  Translate "or, to allocate all the remaining space, enter"
  PrintOne "$Result: " "100%"
  Echo
}

guided_device() { # EFI - Get details of device to use from all connected devices
  DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)     # eg: sda
  UseDisk=$DiskDetails                                      # If more than one, $UseDisk will be first
  local Counter=0
  CountDisks=0
  for i in $DiskDetails   # Count lines in $DiskDetails
  do
    Counter=$((Counter+1))
    Drives[$Counter]=$i
  done
  if [ $Counter -gt 1 ]   # If there are multiple devices
  then                    # ask user which to use
    UseDisk=""            # Reset for user choice
    while [ -z $UseDisk ]
    do
      print_heading
      Translate "There are"
      _P1="$Result $Counter"
      Translate "devices available"
      PrintOne "$_P1" "$Result"
      PrintOne "Which do you wish to use for this installation?"
      Echo
      Counter=0
      for i in $DiskDetails
      do
        Counter=$((Counter+1))
        PrintOne "" "$Counter) $i"
      done
      Echo
      Translate "Please enter the number of your selection"
      TPread "${Result}: "
      UseDisk="${Drives[$Response]}"
    done
  fi
  GrubDevice="/dev/${UseDisk}"  # Full path of selected device
}

guided_disk_size() { # Establish size of device in MiB
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}') # 1) Get disk size eg: 465.8G
  Unit=${DiskSize: -1}                                          # 2) Save last character (eg: G)
  # 3) Remove last character for calculations
  Chars=${#DiskSize}              # Count characters in variable
  Available=${DiskSize:0:Chars-1} # Separate the value from the unit
  # 4) Must be integer, so remove any decimal point and any character following
  Available=${Available%.*}
  if [ $Unit = "G" ]; then
    FreeSpace=$((Available*1024))
    Unit="M"
  elif [ $Unit = "T" ]; then
    FreeSpace=$((Available*1024*1024))
    Unit="M"
  else
    FreeSpace=$Available
  fi
  # 5) Warn user if space is limited
  if [ ${FreeSpace} -lt 2048 ]; then      # If less than 2GiB
    Translate "Your device has only"
    _P1="$Result ${FreeSpace}MiB:"
    Translate "This is not enough for an installation"
    PrintOne "$_P1" "$Result"
    PrintOne "Press any key"
    Translate "Exit"
    read -pn1 "$Result"
    exit
  elif [ ${FreeSpace} -lt 4096 ]; then    # If less than 4GiB
    Translate "Your device has only"
    _P1="$Result ${FreeSpace}MiB:"
    Translate "This is just enough for a basic"
    PrintOne "$_P1" "$Result"
    PrintOne "installation, but you should choose light applications only"
    PrintOne "and you may run out of space during installation or at some later time"
    Translate "Please press Enter to continue"
    TPread "${Result}"
  elif [ ${FreeSpace} -lt 8192 ]; then    # If less than 8GiB
    Translate "Your device has"
    _P1="$Result ${FreeSpace}MiB:"
    Translate "This is enough for"
    PrintOne "$_P1" "$Result"
    PrintOne "installation, but you should choose light applications only"
    Translate "Please press Enter to continue"
    TPread "${Result}"
  fi
}

EasyRecalc() {                          # Calculate remaining disk space
  local Passed=$1
  case ${Passed: -1} in
    "%") Calculator=$FreeSpace          # Allow for 100%
    ;;
    "G") Chars=${#Passed}               # Count characters in variable
        Passed=${Passed:0:Chars-1}      # Passed variable stripped of unit
        Calculator=$((Passed*1024))
    ;;
    *) Chars=${#Passed}                 # Count characters in variable
        Calculator=${Passed:0:Chars-1}  # Passed variable stripped of unit
  esac
  # Recalculate available space
  FreeSpace=$((FreeSpace-Calculator))
}

GuidedMBR() { # Main MBR function - Inform user of purpose, call each step
  guided_device                  # Get details of device to use
  guided_disk_size                # Get available space in MiB
  
  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  message_subsequent "This facility is restricted to creating /root, /swap and /home"
  message_subsequent "\nAre you sure you wish to continue?"

  dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 6 55 2>output.file
  if [ $? -eq 1 ]; then return 1; fi  # If 'No' then return to caller
  
  guided_MBR_root                     # Create /root partition
  
  guided_recalc"$RootSize"            # Recalculate remaining space after adding /root
  if [ ${FreeSpace} -gt 0 ]; then
    guided_MBR_swap
  else
    message_first_line "There is no space for a /swap partition, but you can"
    message_subsequent "assign a swap-file. It is advised to allow some swap\n"
    message_subsequent "Do you wish to allocate a swapfile?"

    dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 6 55 2>output.file
      
    if [ $? -eq 1 ]; then
      SetSwapFile # Note: Global variable SwapFile is set by SetSwapFile
                  # and SwapFile is created during installation by MountPartitions
    fi
  fi
  if [ $SwapSize ]; then
    guided_recalc"$SwapSize"  # Recalculate remaining space after adding /swap
  fi
  if [ ${FreeSpace} -gt 2 ]; then
    guided_MBR_home
  fi
  # Perform formatting and partitioning
  action_MBR
}

guided_MBR_root() { # BIOS - Set variables: RootSize, RootType
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /boot and available space
    message_first_line "We begin with the $_RootPartition"
    message_subsequent "You have"
    Message="$Message ${FreeGigs}GiB"
    message_subsequent "available on the chosen device"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "although you may want to leave room for a /swap partition"
    message_subsequent "and perhaps also a /home partition"
    message_subsequent "The /root partition should not be less than 8GiB"
    message_subsequent "ideally more, up to 20GiB"
    allocate_all      # Adds extra text to Message

    dialog --backtitle "$Backtitle" --ok-label "$Ok" --inputbox "$Message\n[eg: 12G or 100%]" 6 30 2>output.file
    Response=$(cat output.file)
    RESPONSE="${Response^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    Echo
    if [ -z ${CheckInput} ]; then
      continue
    elif [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      dialog --ok-label "$Ok" --msgbox "You must include M, G or %" 6 30
      RootSize=""
      continue
    else
      RootSize=$RESPONSE
      Partition="/root"

      dialog --ok-label "$Ok" --msgbox "${RootSize} allocated to /root" 6 30

      select_filesystem
      RootType=${PartitionType}
      break
    fi
  done
}

guided_MBR_swap() { # BIOS - Set variable: SwapSize
  # Clear display, show /boot and /root
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /root and available space
    print_heading
    PrintOne "$_RootPartition" ": ${RootType} : ${RootSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1" "$Result"
    Echo
    if [ ${FreeSpace} -gt 10 ]; then
      Translate "There is space for a"
      PrintOne "$Result" " $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You may want to leave room for a /home partition"
    elif [ ${FreeSpace} -gt 5 ]; then
      Translate "There is space for a"
      PrintOne "$Result" " $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You can use all the remaining space on the device, if you wish"
      PrintOne "You may want to leave room for a /home partition"
    else
      Translate "There is just space for a"
      PrintOne "$Result" " $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You can use all the remaining space on the device, if you wish"
    fi
    allocate_all
    Translate "Size"
    TPread "$Result [eg: 2G ... 100% ... 0]: "
    RESPONSE="${Response^^}"
    Echo
    case ${RESPONSE} in
      '' | 0) Echo
          PrintOne "Do you wish to allocate a swapfile?"
          Echo
        Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
        Echo
        if [ $Response -eq 1 ]; then
          print_heading
          SetSwapFile
        fi
        break
      ;;
      *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
          RootSize=""
          continue
        else
          SwapSize=$RESPONSE
          break
        fi
    esac
  done
  # If no space remains, offer swapfile, else create swap partition
}

guided_MBR_home() { # BIOS - Set variables: HomeSize, HomeType
  FreeGigs=$((FreeSpace/1024))
  while :
  do
    # Clear display, show /root, /swap and available space
    print_heading
    PrintOne "$_RootPartition" ": ${RootType} : ${RootSize}"
    PrintOne "$_SwapPartition" ": ${SwapSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1" "$Result"
    Echo
    Translate "There is space for a"
    PrintOne "$Result" "$_HomePartition"
    PrintOne "You can use all the remaining space on the device, if you wish"
    allocate_all
    Translate "Size"
    TPread "${Result} [eg: 100% or 0]: "
    RESPONSE="${Response^^}"
    Echo
    case ${RESPONSE} in
      "" | 0) break
      ;;
      *) # Check that entry includes 'G or %'
          CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
          HomeSize=""
          continue
        else
          HomeSize=$RESPONSE
          Partition="/home"
          print_heading
          Translate "of remaining space allocated to"
          PrintOne "${HomeSize}" "$Result $_HomePartition"
          select_filesystem
          HomeType=${PartitionType}
          break
        fi
    esac
  done
}

action_MBR() { # Final BIOS step - Uses the variables set above to create partition table & all partitions
  while :
  do
    # Get user approval
    print_heading
    if [ -n "${RootSize}" ]; then
      PrintOne "$_RootPartition " ": ${RootType} : ${RootSize}"
    fi
    if [ -n "${SwapSize}" ]; then
      PrintOne "$_SwapPartition " ": ${SwapSize}"
    elif [ -n "${SwapFile}" ]; then
      PrintOne "$_SwapFile " ": ${SwapFile}"
    fi
    if [ -n "${HomeSize}" ]; then
      PrintOne "$_HomePartition :" "${HomeType} : ${HomeSize}"
    fi
    Echo
    PrintOne "That's all the preparation done"
    PrintOne "Feliz will now create a new partition table"
    PrintOne "and set up the partitions you have defined"
    Echo
    Translate "This will erase any data on"
    PrintOne "$Result " "${UseDisk}"
    PrintOne "Are you sure you wish to continue?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
    case $Response in
      "1" | "Y" | "y") Parted "mklabel msdos"  # Create mbr partition table
        break
       ;;
      "2" | "N" | "n") UseDisk=""
        CheckParts                    # Go right back to start
        ;;
        *) not_found
    esac
  done

# Root partition
# --------------
  # Calculate end-point
  Unit=${RootSize: -1}                # Save last character of root (eg: G)
  Chars=${#RootSize}                  # Count characters in root variable
  Var=${RootSize:0:Chars-1}           # Remove unit character from root variable
  if [ ${Unit} = "G" ]; then
    Var=$((Var*1024))                 # Convert to MiB
    EndPart=$((1+Var))                # Start at 1MiB
    EndPoint="${EndPart}MiB"          # Append unit
  elif [ ${Unit} = "M" ]; then
    EndPart=$((1+Var))                # Start at 1MiB
    EndPoint="${EndPart}MiB"          # Append unit
  elif [ ${Unit} = "%" ]; then
    EndPoint="${Var}%"
  fi
  Parted "mkpart primary ext4 1MiB ${EndPoint}"
  Parted "set 1 boot on"
  RootPartition="${GrubDevice}1"      # "/dev/sda1"
  NextStart=${EndPart}                # Save for next partition. Numerical only (has no unit)

# Swap partition
# --------------
  if [ $SwapSize ]; then
    # Calculate end-point
    Unit=${SwapSize: -1}              # Save last character of swap (eg: G)
    Chars=${#SwapSize}                # Count characters in swap variable
    Var=${SwapSize:0:Chars-1}         # Remove unit character from swap variable
    if [ ${Unit} = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ ${Unit} = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ ${Unit} = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    Parted "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
    SwapPartition="${GrubDevice}2"    # "/dev/sda2"
    MakeSwap="Y"
    NextStart=${EndPart}              # Save for next partition. Numerical only (has no unit)
  fi

# Home partition
# --------------
  if [ $HomeSize ]; then
    # Calculate end-point
    Unit=${HomeSize: -1}              # Save last character of home (eg: G)
    Chars=${#HomeSize}                # Count characters in home variable
    Var=${HomeSize:0:Chars-1}         # Remove unit character from home variable
    if [ ${Unit} = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ ${Unit} = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ ${Unit} = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    Parted "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
    HomePartition="${GrubDevice}3"    # "/dev/sda3"
    Home="Y"
    AddPartList[0]="${GrubDevice}3"   # /dev/sda3     | add to
    AddPartMount[0]="/home"           # Mountpoint    | array of
    AddPartType[0]="${HomeType}"      # Filesystem    | additional partitions
  fi
  AutoPart=1 # Treat as auto-partitioned. Set flag to 'on' for mounting
}

guided_EFI() { # Main EFIfunction - Inform user of purpose, call each step
  _Backtitle="https://wiki.archlinux.org/index.php/Unified_Extensible_Firmware_Interface"
  guided_device              # Get details of device to use
  guided_disk_size            # Get available space in MiB
  print_heading
  Echo
  PrintOne "Here you can set the size and format of the partitions"
  PrintOne "you wish to create. When ready, Feliz will wipe the disk"
  PrintOne "and create a new partition table with your settings"
  Echo
  Translate "We begin with the"
  PrintOne "$Result" "$_BootPartition"
  Echo
  guided_EFI_boot                # Create /boot partition
  guided_recalc"$BootSize"  # Recalculate remaining space
  guided_EFI_root                # Create /root partition
  guided_recalc"$RootSize"  # Recalculate remaining space after adding /root
  if [ ${FreeSpace} -gt 0 ]; then
    guided_EFI_swap
  else
    Echo
    PrintOne "There is no space for a /swap partition, but you can"
    PrintOne "assign a swap-file. It is advised to allow some swap"
    PrintOne "Do you wish to allocate a swapfile?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
    Echo
    if [ $Response -eq 1 ]; then
      print_heading
      Echo
      SetSwapFile         # Note: Global variable SwapFile is set by SetSwapFile
                          # (SwapFile is created during installation by MountPartitions)
    fi
  fi
  if [ $SwapSize ]; then
    guided_recalc"$SwapSize"  # Recalculate remaining space after adding /swap
  fi
  if [ ${FreeSpace} -gt 2 ]; then
    guided_EFI_home
  fi
  action_EFI          # Perform formatting and partitioning
}

guided_EFI_boot() { # EFI - Set variable: BootSize
  LoopRepeat="Y"
  while [ ${LoopRepeat} = "Y" ]
  do
    FreeGigs=$((FreeSpace/1024))
    Translate "You have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1 " "$Result"
    PrintOne "All we need to set here is the size of your /boot partition"
    PrintOne "It should be no less than 512MiB and need be no larger than 1GiB"
    Echo
    Translate "Size"
    TPread "${Result} (M = Megabytes, G = Gigabytes) [eg: 512M or 1G]: "
    RESPONSE="${Response^^}"
    # Check that entry includes 'M or G'
    CheckInput=${RESPONSE: -1}
    Echo
    if [ ${CheckInput} != "M" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      print_heading
      PrintOne "You must include M, G or %"
      Echo
      BootSize=""
      continue
    else
      BootSize="${RESPONSE}"
      break
    fi
  done
}

guided_EFI_root() { # EFI - Set variables: RootSize, RootType
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /boot and available space
    print_heading
    PrintOne "$_BootPartition" ": ${BootSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1 " "$Result"
    Echo
    PrintOne "A partition is needed for /root"
    PrintOne "You can use all the remaining space on the device, if you wish"
    PrintOne "although you may want to leave room for a /swap partition"
    PrintOne "and perhaps also a /home partition"
    PrintOne "The /root partition should not be less than 8GiB"
    PrintOne "ideally more, up to 20GiB"
    allocate_all
    Translate "Size"
    TPread "${Result} [eg: 12G or 100%]: "
    RESPONSE="${Response^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    Echo
    if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      PrintOne "You must include M, G or %"
      RootSize=""
      continue
    else
      RootSize=$RESPONSE
      Partition="/root"
      print_heading
      select_filesystem
      RootType=${PartitionType}
      break
    fi
  done
}

guided_EFI_swap() { # EFI - Set variable: SwapSize
  # Clear display, show /boot and /root
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /boot and available space
    print_heading
    PrintOne "$_BootPartition" ": ${BootSize}"
    PrintOne "$_RootPartition" ": ${RootType} : ${RootSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1 " "$Result"
    Echo
    if [ ${FreeSpace} -gt 10 ]; then
      Translate "There is space for a"
      PrintOne "$Result $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You may want to leave room for a /home partition"
      Echo
    elif [ ${FreeSpace} -gt 5 ]; then
      Translate "There is space for a"
      PrintOne "$Result $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      PrintOne "You may want to leave room for a /home partition"
      Echo
    else
      Translate "There is just space for a"
      PrintOne "$Result $_SwapPartition"
      PrintOne "Swap can be anything from 512MiB upwards but"
      PrintOne "it is not necessary to exceed 4GiB"
      Echo
    fi
    allocate_all
    Translate "Size"
    sleep 1               # To prevent keyboard bounce
    TPread "$Result [eg: 2G or 100% or 0]: "
    RESPONSE="${Response^^}"
    Echo
    case ${RESPONSE} in
      '' | 0) PrintOne "Do you wish to allocate a swapfile?"
        Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
        Echo
        if [ $Response -eq 1 ]; then
          SetSwapFile
        fi
        break
      ;;
      *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
          RootSize=""
          continue
        else
          SwapSize=$RESPONSE
          break
        fi
    esac
  done
  # If no space remains, offer swapfile, else create swap partition
}

guided_EFI_home() { # EFI - Set variables: HomeSize, HomeType
  LoopRepeat="Y"
  FreeGigs=$((FreeSpace/1024))
  while [ ${LoopRepeat} = "Y" ]
  do
    # Clear display, show /boot and available space
    print_heading
    PrintOne "$_BootPartition" ": ${BootSize}"
    PrintOne "$_RootPartition :" " ${RootType} : ${RootSize}"
    PrintOne "$_SwapPartition :" " ${SwapSize}"
    Echo
    Translate "You now have"
    _P1="$Result ${FreeGigs}GiB"
    Translate "available on the chosen device"
    PrintOne "$_P1 " "$Result"
    Echo
    Translate "There is space for a"
    PrintOne "$Result $_HomePartition"
    PrintOne "You can use all the remaining space on the device, if you wish"
    Echo
    PrintOne "Please enter the desired size"
    Echo
    Translate "Size"
    TPread "$Result [eg: ${FreeGigs}G or 100% or 0]: "
    RESPONSE="${Response^^}"
    Echo
    case ${RESPONSE} in
      "" | 0) break
      ;;
      *) # Check that entry includes 'G or %'
          CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
          HomeSize=""
          continue
        else
          HomeSize=$RESPONSE
          Partition="/home"
          print_heading
          select_filesystem
          HomeType=${PartitionType}
          break
        fi
    esac
  done
}

action_EFI() { # EFI Final step. Uses the variables set above to create GPT partition table & all partitions
  while :
  do                                # Get user approval
    print_heading
    PrintOne "$_BootPartition:" "${BootSize}"
    PrintOne "$_RootPartition :" "${RootType} : ${RootSize}"
    PrintOne "$_SwapPartition :" "${SwapSize}"
    PrintOne "$_HomePartition :" "${HomeType} : ${HomeSize}"
    Echo
    PrintOne "That's all the preparation done"
    PrintOne "Feliz will now create a new partition table"
    PrintOne "and set up the partitions you have defined"
    Echo
    Translate "This will erase any data on"
    PrintOne "$Result " "${UseDisk}"
    PrintOne "Are you sure you wish to continue?"
    Echo
    Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
    case $Response in
      "1" | "$_Yes") WipeDevice   # Format the drive
        Parted "mklabel gpt"        # Create EFI partition table
        break
       ;;
      "2" | "$_No") UseDisk=""
        CheckParts                  # Go right back to start
        ;;
        *) not_found
    esac
  done

# Boot partition
# --------------
  # Calculate end-point
  Unit=${BootSize: -1}                # Save last character of boot (eg: M)
  Chars=${#BootSize}                  # Count characters in boot variable
  Var=${BootSize:0:Chars-1}           # Remove unit character from boot variable
  if [ ${Unit} = "G" ]; then
    Var=$((Var*1024))                 # Convert to MiB
  fi
  EndPoint=$((Var+1))                 # Add start and finish. Result is MiBs, numerical only (has no unit)
  Parted "mkpart primary fat32 1MiB ${EndPoint}MiB"
  Parted "set 1 boot on"
  EFIPartition="${GrubDevice}1"       # "/dev/sda1"
  NextStart=${EndPoint}               # Save for next partition. Numerical only (has no unit)

# Root partition
# --------------
  # Calculate end-point
  Unit=${RootSize: -1}                # Save last character of root (eg: G)
  Chars=${#RootSize}                  # Count characters in root variable
  Var=${RootSize:0:Chars-1}           # Remove unit character from root variable
  if [ ${Unit} = "G" ]; then
    Var=$((Var*1024))                 # Convert to MiB
    EndPart=$((NextStart+Var))        # Add to previous end
    EndPoint="${EndPart}MiB"          # Add unit
  elif [ ${Unit} = "M" ]; then
    EndPart=$((NextStart+Var))        # Add to previous end
    EndPoint="${EndPart}MiB"          # Add unit
  elif [ ${Unit} = "%" ]; then
    EndPoint="${Var}%"
  fi
  # Make the partition
  Parted "mkpart primary ${RootType} ${NextStart}MiB ${EndPoint}"
  RootPartition="${GrubDevice}2"      # "/dev/sda2"
  NextStart=${EndPart}                # Save for next partition. Numerical only (has no unit)

# Swap partition
# --------------
  if [ $SwapSize ]; then
    # Calculate end-point
    Unit=${SwapSize: -1}              # Save last character of swap (eg: G)
    Chars=${#SwapSize}                # Count characters in swap variable
    Var=${SwapSize:0:Chars-1}         # Remove unit character from swap variable
    if [ ${Unit} = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Add unit
    elif [ ${Unit} = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Add unit
    elif [ ${Unit} = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    Parted "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
    SwapPartition="${GrubDevice}3"    # "/dev/sda3"
    MakeSwap="Y"
    NextStart=${EndPart}              # Save for next partition. Numerical only (has no unit)
  fi

# Home partition
# --------------
  if [ $HomeSize ]; then
    # Calculate end-point
    Unit=${HomeSize: -1}              # Save last character of home (eg: G)
    Chars=${#HomeSize}                # Count characters in home variable
    Var=${HomeSize:0:Chars-1}         # Remove unit character from home variable
    if [ ${Unit} = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Add unit
    elif [ ${Unit} = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Add unit
    elif [ ${Unit} = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    Parted "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
    HomePartition="${GrubDevice}4"    # "/dev/sda4"
    Home="Y"
    AddPartList[0]="${GrubDevice}4"   # /dev/sda4     | add to
    AddPartMount[0]="/home"           # Mountpoint    | array of
    AddPartType[0]="ext4"             # Filesystem    | additional partitions
  fi
  ShowPart1="$_BootPartition : $(lsblk -l | grep "${UseDisk}1" | awk '{print $4, $1}')" >/dev/null
  ShowPart2="$_RootPartition : $(lsblk -l | grep "${UseDisk}2" | awk '{print $4, $1}')" >/dev/null
  ShowPart3="$_SwapPartition : $(lsblk -l | grep "${UseDisk}3" | awk '{print $4, $1}')" >/dev/null
  ShowPart4="$_HomePartition : $(lsblk -l | grep "${UseDisk}4" | awk '{print $4, $1}')" >/dev/null
  AutoPart=1                  # Treat as auto-partitioned. Set flag to 'on' for mounting
  print_heading
  PrintOne "Partitioning of" "${GrubDevice}" "successful"
  Echo
  PrintOne "" "$ShowPart1"
  PrintMany "" "$ShowPart2"
  PrintMany "" "$ShowPart3"
  PrintMany "" "$ShowPart4"
  Echo
  Translate "Press Enter to continue"
  Buttons "Yes/No" "$_Ok" "$Result"
}
