#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 1st April 2018

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
#                  and partitions, and functions for autopartitioning
# -----------------------    ------------------------    -----------------------
# SHARED Functions   Line    SHARED Functions    Line    MBR/EFI Functions  Line 
# -----------------------    ------------------------    -----------------------
# auto_warning         35    guided_recalc        158    guided_MBR          356
# autopart             45    guided_root          175    guided_EFI          378
# prepare_partitions   90    guided_swap          217    guided_EFI_boot     401
# select_filesystem   132    guided_home          296    action_guided       438
# allocate_all        151    start_guided_message 343    display_results     572
# -----------------------    ------------------------    -----------------------

function auto_warning
{
  message_first_line "This will erase any data on"
  Message="$Message ${UseDisk}"
  message_subsequent "Are you sure you wish to continue?"
  dialog --backtitle "$Backtitle" --title " Auto-partition " \
    --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 9 50
  retval=$?
}

function autopart   # Consolidated fully automatic partitioning for BIOS or EFI environment
{                   # Called by f-part.sh/check_parts (after auto_warning)

  prepare_device                                    # Create partition table and device variables
  RootType="ext4"                                   # Default for auto
  HomeType="ext4"                                   # Default for auto

  # Decide partition sizes based on device size
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
  display_results
}

function prepare_device # Called by autopart and guided_ functions
{
  GrubDevice="/dev/${UseDisk}"
  Home="N"                                          # No /home partition at this point
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}' | sed "s/G\|M\|K//g") # Get disk size
  FreeSpace="$DiskSize" !!!!Add this to new function  # For guided partitioning
  tput setf 0                                       # Change foreground colour to black to hide error message
  clear

  # Create a new partition table
  if [ ${UEFI} -eq 1 ]; then                        # Installing in UEFI environment
    parted_script "mklabel gpt"                       # Create new filesystem
    parted_script "mkpart primary fat32 1MiB 513MiB"  # EFI boot partition
    StartPoint="513MiB"                             # For next partition
  else                                              # Installing in BIOS environment
    parted_script "mklabel msdos"                   # Create new filesystem
    StartPoint="1MiB"                               # For next partition
  fi
}

function prepare_partitions # Called from autopart for either EFI or BIOS system
{ # Uses gnu parted to create partitions 
  # Receives up to 4 arguments
  #   $1 is the starting point of the first partition
  #   $2 is size of root partition
  #   $3 if passed is size of home partition
  #   $4 if passed is size of swap partition
  # Note:
  # An appropriate partition table has already been created in autopart()
  # If EFI the /boot partition has also been created at /dev/sda1 and set as bootable
  # and the startpoint (passed as $1) has been set to follow /boot
                    
  local StartPoint=$1                               # Local variable 

  # Set the device to be used to 'set x boot on'    # $MountDevice is numerical - eg: 1 in sda1
  MountDevice=1                                     # Start with first partition = [sda]1
                                                    # Make /boot at startpoint
  parted_script "mkpart primary ext4 ${StartPoint} ${2}"   # eg: parted /dev/sda mkpart primary ext4 1MiB 12GiB
  parted_script "set ${MountDevice} boot on"               # eg: parted /dev/sda set 1 boot on
  if [ $UEFI -eq 1 ]; then                          # Reset if installing in EFI environment
    MountDevice=2                                   # Next partition after /boot = [sda]2
  fi
  RootPartition="${GrubDevice}${MountDevice}"       # eg: /dev/sda1
  mkfs."{RootType}" "${RootPartition}" &>> feliz.log   # eg: mkfs.ext4 /dev/sda1
  StartPoint=$2                                     # Increment startpoint for /home or /swap
  MountDevice=$((MountDevice+1))                    # Advance partition numbering for next step

  if [ -n "$3" ]; then
    parted_script "mkpart primary ext4 ${StartPoint} ${3}" # eg: parted /dev/sda mkpart primary ext4 12GiB 19GiB
    AddPartList[0]="${GrubDevice}${MountDevice}"    # eg: /dev/sda3  | add to
    AddPartMount[0]="/home"                         # Mountpoint     | array of
    AddPartType[0]="$HomeType"                      # Filesystem     | additional partitions
    Home="Y"
    mkfs."$HomeType" "${GrubDevice}${MountDevice}" &>> feliz.log  # eg: mkfs.ext4 /dev/sda3
    StartPoint=$3                                   # Reset startpoint for /swap
    MountDevice=$((MountDevice+1))                  # Advance partition numbering
  fi

  if [ -n "$4" ]; then
    parted_script "mkpart primary linux-swap ${StartPoint} ${4}" # eg: parted /dev/sda mkpart primary linux-swap 31GiB 100%
    SwapPartition="${GrubDevice}${MountDevice}"
    mkswap "$SwapPartition"
    MakeSwap="Y"
  fi
}

function select_filesystem # User chooses filesystem from list in global variable ${TypeList}
{
  local Counter=0
  message_first_line "Please select the file system for"
  Message="$Message ${Partition}"
  message_subsequent "It is not recommended to mix the btrfs file-system with others"
  message_subsequent "or choose Exit to leave it as it is"
  menu_dialog_variable="${TypeList}"

  menu_dialog 12 55 "$_Exit"
  
  if [ $retval -ne 0 ]; then
    PartitionType=""
    return 1
  else
    PartitionType="$Result"
  fi
}

function allocate_all
{
  message_subsequent "Please enter the desired size"
  message_subsequent "or, to allocate all the remaining space, enter"
  Message="${Message}: 100%"
}

function guided_recalc                  # Calculate remaining disk space
{
  local Passed=$1
  Chars=${#Passed}                      # Count characters in variable
  
  if [ ${Passed: -1} = "%" ]; then      # Allow for percentage
    Passed=${Passed:0:Chars-1}          # Passed variable stripped of unit
    Value=$((FreeSpace*100/Passed))     # Convert percentage to value
    Calculator=$Value
  elif [ ${Passed: -1} = "G" ]; then
    Passed=${Passed:0:Chars-1}          # Passed variable stripped of unit
    Calculator=$((Passed*1024))
  elif [ ${Passed: -3} = "GiB" ]; then  
    Passed=${Passed:0:Chars-3}          # Passed variable stripped of unit
    Calculator=$((Passed*1024))
  elif [ ${Passed: -1} = "M" ]; then
    Calculator=${Passed:0:Chars-1}      # (M or MiB) Passed variable stripped of unit
  elif [ ${Passed: -3} = "MiB" ]; then
    Calculator=${Passed:0:Chars-3}      # (M or MiB) Passed variable stripped of unit
  else
    read -p "Error in free-space calculator at line $LINENO"
  fi

  # Recalculate available space
  FreeSpace=$((FreeSpace-Calculator))
}

function guided_root # MBR & EFI Set variables: RootSize, RootType
{
  FreeGigs=$((FreeSpace/1024))
  while true
  do
    # Clear display, show /boot and available space
    if [ $UEFI -eq 1 ]; then
      message_first_line "$_BootPartition : ${BootSize}"
      message_subsequent "You now have"
    else
      message_first_line "You have"
    fi
    Message="$Message ${FreeGigs}GiB"
    Message="$Message available on the chosen device"
    message_subsequent "A partition is needed for /root"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "although you may want to leave room for a /swap partition"
    message_subsequent "and perhaps also a /home partition"
    message_subsequent "The /root partition should not be less than 8GiB"
    message_subsequent "ideally more, up to 20GiB"
    allocate_all
    translate "Size"
    message_subsequent "${Result} [eg: 12G or 100%] ... "

    dialog --backtitle "$Backtitle" --ok-label "$Ok" --inputbox "$Message" 16 70 2>output.file
    retval=$?
    if [ $retval -ne 0 ]; then return 1; fi
    Result="$(cat output.file)"
    RESPONSE="${Result^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}

    if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
      dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\nYou must include M, G or %\n" 6 50
      RootSize=""
      continue
    else
      if [ "$CheckInput" != "%" ]; then
        RootSize="$RESPONSE"
      else
        RootSize="${RESPONSE}iB"
      fi
      Partition="/root"
      select_filesystem
      RootType=${PartitionType}
      break
    fi
  done
}

function guided_swap # MBR & EFI Set variable: SwapSize
{
  # Show /boot and /root
  FreeGigs=$((FreeSpace/1024))
  while true
  do
    if [ ${FreeSpace} -gt 0 ]; then
      # show /root and available space
      message_first_line "$_RootPartition : ${RootType} : ${RootSize}"
      message_subsequent "You now have"
      Message="$Message ${FreeGigs}GiB"
      Message="$Message available on the chosen device"
  
      if [ ${FreeSpace} -gt 10 ]; then
        message_subsequent "There is space for a"
        Message="$Message $_SwapPartition"
        message_subsequent "Swap can be anything from 512MiB upwards but"
        message_subsequent "it is not necessary to exceed 4GiB"
        message_subsequent "You may want to leave room for a /home partition"
      elif [ ${FreeSpace} -gt 5 ]; then
        message_subsequent "There is space for a"
        Message="$Message $_SwapPartition"
        message_subsequent "Swap can be anything from 512MiB upwards but"
        message_subsequent "it is not necessary to exceed 4GiB"
        message_subsequent "You can use all the remaining space on the device, if you wish"
        message_subsequent "You may want to leave room for a /home partition"
      else
        message_subsequent "There is just space for a"
        Message="$Message $_SwapPartition"
        message_subsequent "Swap can be anything from 512MiB upwards but"
        message_subsequent "it is not necessary to exceed 4GiB"
        message_subsequent "You can use all the remaining space on the device, if you wish"
      fi
      allocate_all
      translate "Size"
      message_subsequent "$Result [eg: 2G ... 100% ... 0] ... "
  
      dialog --backtitle "$Backtitle" --ok-label "$Ok" --inputbox "$Message" 16 70 2>output.file
      retval=$?
      Result="$(cat output.file)"
      RESPONSE="${Result^^}"
      case ${RESPONSE} in
        '' | 0) Echo
            message_first_line "Do you wish to allocate a swapfile?"
          dialog --backtitle "$Backtitle" --title " $title " \
              --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 7 60
          if [ $? -eq 0 ]; then
            print_heading
            SetSwapFile
          fi
          break
        ;;
        *) # Check that entry includes 'G or %'
          CheckInput=${RESPONSE: -1}
          if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
            dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\nYou must include M, G or %\n" 6 50
            SwapSize=""
            continue
          else
            if [ "$CheckInput" != "%" ]; then
              SwapSize="$RESPONSE"
            else
              SwapSize="${RESPONSE}iB"
            fi
            break
          fi
      esac
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
      break
    fi
  done
}

function guided_home # MBR & EFI Set variables: HomeSize, HomeType
{
  FreeGigs=$((FreeSpace/1024))
  while true
  do
    # Show /root, /swap and available space
    message_first_line "$_RootPartition : ${RootType} : ${RootSize}"
    message_subsequent "$_SwapPartition" ": ${SwapSize}"
    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    Message="$Message available on the chosen device"
    
    message_subsequent "There is space for a"
    Message="$Message $_HomePartition"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    allocate_all
    translate "Size"
    message_subsequent "${Result} [eg: 100% or 0] ... "
    
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --inputbox "$Message" 16 70 2>output.file
    retval=$?
    Result="$(cat output.file)"
    RESPONSE="${Result^^}"

    case ${RESPONSE} in
      "" | 0) break
      ;;
      *) # Check that entry includes 'G or %'
          CheckInput=${RESPONSE: -1}
        if [ "$CheckInput" != "%" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
          dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\nYou must include M, G or %\n" 8 75
          HomeSize=""
          continue
        else
          if [ "$CheckInput" != "%" ]; then
            HomeSize="$RESPONSE"
          else
            HomeSize="${RESPONSE}iB"
          fi
          Partition="/home"
          translate "of remaining space allocated to"
          Message="$HomeSize $Result"
          dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n$Result\n" 8 75
          PrintOne "${HomeSize}" "$Result $_HomePartition"
          select_filesystem
          HomeType=${PartitionType}
          break
        fi
    esac
  done
}

function start_guided_message
{
  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  message_subsequent "$limitations"
  message_subsequent "\nDo you wish to continue?"

  dialog --backtitle "$Backtitle" --title " $title " \
      --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 12 60
  retval=$?
}

function guided_MBR # Main MBR function - Inform user of purpose, call each step
{
  limitations="This facility will create /root, /swap and /home"

  start_guided_message
  if [ $retval -ne 0 ]; then return 1; fi   # If 'No' then return to caller

  prepare_device                            # Create partition table and device size variables

  guided_root                               # Create /root partition ($RootSize & $RootType)
  guided_recalc "$RootSize"                 # Recalculate remaining space after adding /root

  guided_swap                               # $SwapSize
  if [ -n "$SwapSize" ]; then
    guided_recalc "$SwapSize"               # Recalculate remaining space after adding /swap
  fi
  
  if [ ${FreeSpace} -gt 2 ]; then
    guided_home                             # Create /home partition ($HomeSize & $HomeType
  fi
  
  # Perform partitioning
  prepare_partitions "${StartPoint}" "${RootSize}" "${HomeSize}" "${SwapSize}" # partition sizes may include MiB GiB or %
}

function guided_EFI # Main EFIfunction - Inform user of purpose, call each step
{
  limitations="This facility will create /boot /root, /swap and /home"
  
  start_guided_message
  if [ $retval -ne 0 ]; then return 1; fi   # If 'No' then return to caller

  prepare_device                            # Create partition table and device size variables

  guided_EFI_boot                           # Create /boot partition
  guided_recalc "$BootSize"                 # Recalculate remaining space
  
  guided_root                               # Create /root partition
  guided_recalc "$RootSize"                 # Recalculate remaining space after adding /root

  guided_swap
  if [ -n "$SwapSize" ]; then
    guided_recalc "$SwapSize"               # Recalculate remaining space after adding /swap
  fi
  
  if [ ${FreeSpace} -gt 2 ]; then
    guided_home
  fi
  
  # Perform partitioning - Note that /boot has already been created in prepare_device and $startpoint advanced
  prepare_partitions "${StartPoint}" "${RootSize}" "${HomeSize}" "${SwapSize}" # partition sizes may include MiB GiB or %
}

function guided_EFI_boot      # EFI - Set variable: BootSize
{
  while true
  do
    message_first_line "We begin with the"
    Message="$Message $_BootPartition"

    FreeGigs=$((FreeSpace/1024))
    message_subsequent "You have"
    Message="$Message ${FreeGigs}GiB"
    message_subsequent "available on the chosen device"
    message_subsequent "All we need to set here is the size of your /boot partition"
    message_subsequent "It should be no less than 512MiB and need be no larger than 1GiB"

    translate "Size"
    message_subsequent "${Result} [eg: 100% or 0] ... "
    
    dialog --backtitle "$Backtitle" --ok-label "$Ok" --inputbox "$Message" 14 70 2>output.file
    retval=$?
    Result="$(cat output.file)"
    RESPONSE="${Result^^}"
    # Check that entry includes 'M or G'
    CheckInput=${RESPONSE: -1}
    Echo
    if [ "$CheckInput" != "M" ] && [ "$CheckInput" != "G" ] && [ "$CheckInput" != "M" ]; then
      print_heading
      PrintOne "You must include M, G or %"
      Echo
      BootSize=""
      continue
    else
      if [ "$CheckInput" != "%" ]; then
        BootSize="$RESPONSE"
      else
        BootSize="${RESPONSE}iB"
      fi
      break
    fi
  done
}

function action_guided # Final GUIDED step - creates partition table & all partitions
{
  while true
  do
    # Get user approval
    if [ $UEFI -eq 0 ]; then
      message_first_line "$_RootPartition : ${RootType} : ${RootSize}"
    else
      message_first_line "$_BootPartition $_RootPartition : ${RootType} : ${RootSize}"
    fi

    if [ -n "${SwapSize}" ]; then
      message_subsequent "$_SwapPartition : ${SwapSize}"
    elif [ -n "${SwapFile}" ]; then
      message_subsequent "$_SwapFile : ${SwapFile}"
    fi
    if [ -n "${HomeSize}" ]; then
      message_subsequent "$_HomePartition : ${HomeType} : ${HomeSize}"
    fi
    message_subsequent "That's all the preparation done"
    message_subsequent "Feliz will now create a new partition table"
    message_subsequent "and set up the partitions you have defined"
    message_subsequent "This will erase any data on"
    Message="$Message ${UseDisk}"
    message_subsequent "Are you sure you wish to continue?"

    dialog --backtitle "$Backtitle" --title " Auto-partition " \
    --yes-label "$Yes" --no-label "$No" --yesno "\n$Message" 9 50
    retval=$?

    # Create partition table
    if [ $retval -eq 0 ]; then
      if [ $UEFI -eq 0 ]; then
        parted_script "mklabel msdos" # Create mbr partition table
      else
        parted_script "mklabel gpt"   # Create gpt partition table
      fi
      break
    else
      UseDisk=""
      return 1                        # Go right back to start
    fi
  done
  
  MountDevice=1
  
  if [ $UEFI -eq 1 ]; then                # EFI only
    # Boot partition
    # --------------
      # Calculate end-point
      Unit=${BootSize: -1}                # Save last character of boot (eg: M)
      Chars=${#BootSize}                  # Count characters in boot variable
      Var=${BootSize:0:Chars-1}           # Remove unit character from boot variable
      if [ "$Unit" = "G" ]; then
        Var=$((Var*1024))                 # Convert to MiB
      fi
      EndPoint=$((Var+1))                 # Add start and finish. Result is MiBs, numerical only (has no unit)
      parted_script "mkpart primary fat32 1MiB ${EndPoint}MiB"
      parted_script "set 1 boot on"
      EFIPartition="${GrubDevice}1"       # "/dev/sda1"
      mkfs.vfat -F32 "${EFIPartition}" &>> feliz.log   # eg: mkfs.vfat -L Arch-Root /dev/sda1
      NextStart=${EndPoint}               # Save for next partition. Numerical only (has no unit)
      MountDevice=2
  fi

# Root partition
# --------------
  # Calculate end-point
  Unit=${RootSize: -1}                # Save last character of root (eg: G)
  Chars=${#RootSize}                  # Count characters in root variable
  Var=${RootSize:0:Chars-1}           # Remove unit character from root variable
  if [ "${Unit}" = "G" ]; then
    Var=$((Var*1024))                 # Convert to MiB
    EndPart=$((1+Var))                # Start at 1MiB
    EndPoint="${EndPart}MiB"          # Append unit
  elif [ "${Unit}" = "M" ]; then
    EndPart=$((1+Var))                # Start at 1MiB
    EndPoint="${EndPart}MiB"          # Append unit
  elif [ "${Unit}" = "%" ]; then
    EndPoint="${Var}%"
  fi
  parted_script "mkpart primary ext4 1MiB ${EndPoint}"
  parted_script "set 1 boot on"
  RootPartition="${GrubDevice}${MountDevice}" # "/dev/sda2"
  mkfs."${RootType}" "${RootPartition}" &>> feliz.log  # eg: mkfs.ext4 /dev/sda1
  NextStart=${EndPart}                # Save for next partition. Numerical only (has no unit)
  MountDevice=$((MountDevice+1))

# Swap partition
# --------------
  if [ -n "$SwapSize" ]; then
    # Calculate end-point
    Unit=${SwapSize: -1}              # Save last character of swap (eg: G)
    Chars=${#SwapSize}                # Count characters in swap variable
    Var=${SwapSize:0:Chars-1}         # Remove unit character from swap variable
    if [ "$Unit" = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ "$Unit" = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ "$Unit" = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    parted_script "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
    SwapPartition="${GrubDevice}${MountDevice}"    # "/dev/sda2"
    mkswap "${SwapPartition}"
    NextStart=${EndPart}              # Save for next partition. Numerical only (has no unit)
    MountDevice=$((MountDevice+1))
  fi

# Home partition
# --------------
  if [ -n "$HomeSize" ]; then
    # Calculate end-point
    Unit=${HomeSize: -1}              # Save last character of home (eg: G)
    Chars=${#HomeSize}                # Count characters in home variable
    Var=${HomeSize:0:Chars-1}         # Remove unit character from home variable
    if [ "$Unit" = "G" ]; then
      Var=$((Var*1024))               # Convert to MiB
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ "$Unit" = "M" ]; then
      EndPart=$((NextStart+Var))      # Add to previous end
      EndPoint="${EndPart}MiB"        # Append unit
    elif [ "$Unit" = "%" ]; then
      EndPoint="${Var}%"
    fi
    # Make the partition
    parted_script "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
    HomePartition="${GrubDevice}${MountDevice}"    # "/dev/sda3"
    mkfs."${HomeType}" "${HomePartition}" &>> feliz.log  # eg: mkfs.ext4 /dev/sda3
    Home="Y"
    AddPartList[0]="${HomePartition}" # /dev/sda3     | add to
    AddPartMount[0]="/home"           # Mountpoint    | array of
    AddPartType[0]="${HomeType}"      # Filesystem    | additional partitions
  fi
  AutoPart="GUIDED"
  display_results
}

function display_results
{
  device=$(lsblk -l | head -n 2)
  plist=$(lsblk -l | grep "$device")
  
  message_first_line "Partitioning of ${GrubDevice} successful"
  Message="$Message\n \n${plist}"

  dialog --backtitle "$Backtitle" --ok-label "$Ok" --msgbox "\n$Message" 14 75
}
