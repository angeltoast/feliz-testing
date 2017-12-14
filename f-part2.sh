#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 12th December 2017

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

# Variables for UEFI Architecture
UEFI=0            # 1 = UEFI; 0 = BIOS
EFIPartition=""   # "/dev/sda1"
UEFI_MOUNT=""    	# UEFI mountpoint
DualBoot="N"      # For formatting EFI partition

# In this module - functions for guided creation of a GPT or EFI partition table:
# -----------------------    ------------------------    -----------------------
# EFI Functions      Line    EFI Functions       Line    BIOS Functions     Line
# -----------------------    ------------------------    -----------------------
# test_uefi           41     guided_EFI           187    guided_MBR         232
# allocate_uefi       55     guided_EFI_Boot      227    
# enter_size          77     guided_EFI_Root      255    guided_MBR_root    565
# select_device       84     guided_EFI_Swap      292    guided_MBR_swap    608
# get_device_size    118     guided_EFI_Home      352    guided_MBR_home    671
# recalculate_space  170     last_chance          399
#                            action_EFI           412    action_MBR         716
# -----------------------    ------------------------    -----------------------

function test_uefi() # Called at launch of Feliz script, before all other actions
{ 
  tput setf 0 # Change foreground colour to black temporarily to hide system messages
  dmesg | grep -q "efi: EFI"          # Test for EFI (-q tells grep to be quiet)
  if [ $? -eq 0 ]
  then                                # check exit code; 0 = EFI, else BIOS
    UEFI=1                            # Set variable UEFI ON and mount the device
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2> feliz.log
  else
    UEFI=0                            # Set variable UEFI OFF
  fi
 tput sgr0                            # Reset colour
}

function allocate_uefi() # Called at start of allocate_root, as first step of EFI partitioning
{ # before allocating root partition. Uses list of available partitions in
  # PartitionList created in f-part1.sh/BuildPartitionLists
	Remaining=""
	local Counter=0
  Partition=""
	PartitionType=""

	translate "Here are the partitions that are available"
  Title="$Result"
	message_first_line "First you should select one to use for EFI /boot"
	message_subsequent "This must be of type vfat, and may be about 512MiB"
  display_partitions
  if [ $retval -ne 0 ]; then return; fi
  PassPart="/dev/${Result}" # eg: sda1
  SetLabel "/dev/${Result}"
	EFIPartition="/dev/${Result}"
  PartitionList=$(echo "$PartitionList" | sed "s/$Result //")  # Remove selected item

}

function enter_size()  # Called by guided_EFI_Root, guided_EFI_Swap, guided_EFI_Home
{                     # guided_MBR_root, guided_MBR_swap, guided_MBR_home
  message_subsequent "Please enter the desired size"
  message_subsequent "or, to allocate all the remaining space, enter"
  Message="$Message 100%"
}

function select_device() # Called by feliz.sh
{ # User chooses device to use for auto partition from all connected devices
  DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)     # eg: sda sdb
  UseDisk=$DiskDetails                                      # If more than one, $UseDisk will be first
  local Counter=$(echo "$DiskDetails" | wc -w)
  if [ $Counter -gt 1 ]   # If there are multiple devices
  then                    # ask user which to use
    UseDisk=""            # Reset for user choice
    while [ "$UseDisk" = "" ]
    do
      message_first_line "There are"
      Message="$Message $Counter"
      translate "devices available"
      Message="$Message $Result"
      message_subsequent "Which do you wish to use for this installation?"

      Counter=0
      for i in $DiskDetails
      do
        Counter=$((Counter+1))
        message_first_line "" "$Counter) $i"
      done

      translate "Please enter the number of your selection"
      Title="$Result"
      echo $DiskDetails > checklist.file

      checklist_dialog 12 60 "--nocancel" "--radiolist"
      UseDisk="${Result}"
    done
  fi
  GrubDevice="/dev/${UseDisk}"  # Full path of selected device
}

function get_device_size() # Called by feliz.sh
{
  # Establish size of device in MiB and inform user
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}') # 1) Get disk size eg: 465.8G
  Unit=${DiskSize: -1}                                          # 2) Save last character (eg: G)
  
  # Remove last character for calculations
  Chars=${#DiskSize}              # Count characters in variable
  Available=${DiskSize:0:Chars-1} # Separate the value from the unit
  
  # Must be integer, so remove any decimal point and any character following
  Available=${Available%.*}
  
  if [ $Unit = "G" ]
  then
    FreeSpace=$((Available*1024))
    Unit="M"
  elif [ $Unit = "T" ]
  then
    FreeSpace=$((Available*1024*1024))
    Unit="M"
  else
    FreeSpace=$Available
  fi
  
  # Warn user if space is limited
  if [ ${FreeSpace} -lt 2048 ]
  then      # If less than 2GiB
    message_first_line "Your device has only"
    Message="$Message ${FreeSpace}MiB:"
    message_first_line "This is not enough for an installation"
    translate "Exit"
    dialog --backtitle "$Backtitle" --infobox "$Message" 10 60
    exit
  elif [ ${FreeSpace} -lt 4096 ]
  then    # If less than 4GiB
    message_first_line "Your device has only"
    Message="$Message ${FreeSpace}MiB:"
    message_subsequent "This is just enough for a basic"
    message_subsequent "installation, but you should choose light applications only"
    message_subsequent "and you may run out of space during installation or at some later time"
    dialog --backtitle "$Backtitle" --infobox "$Message" 10 60
  elif [ ${FreeSpace} -lt 8192 ]
  then    # If less than 8GiB
    message_first_line "Your device has"
    Messgae="$Message ${FreeSpace}MiB:"
    message_subsequent "This is enough for"
    message_subsequent "installation, but you should choose light applications only"
    dialog --backtitle "$Backtitle" --infobox "$Message" 10 60
  fi
}

function recalculate_space() # Called by guided_MBR & guided_EFI
{  # Calculate remaining disk space
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

function guided_EFI()  # Called by f-part1.sh/partitioning_options as the first step
{ #  in EFI guided partitioning option - Inform user of purpose, call each step

  select_device                # Get details of device to use
  get_device_size                 # Get available space in MiB

  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  Message="${Message}\n"
  message_subsequent "Are you sure you wish to continue?"
  dialog --backtitle "$Backtitle" --yesno "$Message" 15 70
  if [ $? -ne 0 ]; then return 1; fi   # Go right back to start
  
  message_first_line "We begin with the"
  Message="$Message $_BootPartition"

  guided_EFI_Boot                  # Create /boot partition
  recalculate_space "$BootSize"    # Recalculate remaining space
  guided_EFI_Root                  # Create /root partition
  recalculate_space "$RootSize"    # Recalculate remaining space after adding /root
  if [ ${FreeSpace} -gt 0 ]
  then
    guided_EFI_Swap
  else
    message_first_line "There is no space for a /swap partition, but you can"
    message_subsequent "assign a swap-file. It is advised to allow some swap"
    message_subsequent "Do you wish to allocate a swapfile?"

    dialog --backtitle "$Backtitle" --title " $Title " --yesno "\n$Message" 10 55 2>output.file
    if [ $? -ne 0 ]; then return 1; fi
    set_swap_file           # Note: Global variable SwapFile is set by set_swap_file
                          # (SwapFile will be created during installation by mount_partitions)
  fi
  
  if [ $SwapSize ]; then recalculate_space "$SwapSize"; fi  # Recalculate remaining space after adding /swap
  
  if [ ${FreeSpace} -gt 2 ]; then guided_EFI_Home; fi
  
  # action_EFI  # Perform formatting and partitioning #### THIS SHOULD NOT HAPPEN UNTIL INSTALLATION PHASE !!!!!!!!! ###
}

function guided_MBR()  # Called by f-part1.sh/partitioning_options as the first step in the 
{ # guided BIOS partitioning option - Inform user of purpose, call each step
  message_first_line "Here you can set the size and format of the partitions"
  message_subsequent "you wish to create. When ready, Feliz will wipe the disk"
  message_subsequent "and create a new partition table with your settings"
  message_subsequent "This facility is restricted to creating /root, /swap and /home"
  Message="${Message}\n"
  message_subsequent "Are you sure you wish to continue?"

  dialog --backtitle "$Backtitle" --yesno "$Message" 15 70
  if [ $? -ne 0 ]; then return 1; fi

  guided_MBR_root                             # Create /root partition
  if [ $? -ne 0 ]; then return 1; fi

  recalculate_space "$RootSize"                      # Recalculate remaining space after adding /root
  if [ ${FreeSpace} -gt 0 ]
  then 
    guided_MBR_swap
  else
    message_first_line "There is no space for a /swap partition, but you can"
    message_subsequent "assign a swap-file. It is advised to allow some swap"
    Message="${Message}\n"
    message_subsequent "Do you wish to allocate a swapfile?"
    dialog --backtitle "$Backtitle" --yesno "$Message" 15 70
    if [ $? -ne 0 ]; then return 1; fi
    set_swap_file # Note: Global variable SwapFile is set by set_swap_file
                # and SwapFile is created during installation by mount_partitions
  fi
  
  if [ $SwapSize ]; then recalculate_space "$SwapSize"; fi  # Recalculate remaining space after adding /swap

  if [ ${FreeSpace} -gt 2 ]; then guided_MBR_home; fi
  
  # Perform formatting and partitioning
  # action_MBR  ######## DO NOT CALL THIS UNTIL INSTALLATION PHASE !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! ##############
}

function guided_EFI_Boot() # Called by guided_EFI
{ # EFI - User sets variable: BootSize
  BootSize=""
  while [ ${BootSize} = "" ]
  do
    FreeGigs=$((FreeSpace/1024))
    message_first_line "You have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    message_subsequent "All we need to set here is the size of your /boot partition"
    message_subsequent "It should be no less than 512MiB and need be no larger than 1GiB"

    dialog_inputbox 12 70
    RESPONSE="${Result^^}"
    # Check that entry includes 'M or G'
    CheckInput=${RESPONSE: -1}
    echo
    if [ ${CheckInput} != "M" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      message_first_line "You must include M, G or %"
      dialog --backtitle "$Backtitle" --infobox "$Message" 10 60
      BootSize=""
    else
      BootSize="${RESPONSE}"
    fi
  done
}

function guided_EFI_Root() # Celled by guided_EFI
{ # EFI - User sets variables: RootSize, RootType
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${RootSize} = "" ]
  do
    # Clear display, show /boot and available space
    Message="$_BootPartition: ${BootSize}\n"
    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    Title="/root"
    message_subsequent "A partition is needed for /root"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "although you may want to leave room for a /swap partition"
    message_subsequent "and perhaps also a /home partition"
    message_subsequent "The /root partition should not be less than 8GiB"
    message_subsequent "ideally more, up to 20GiB"
    enter_size       # Adds extra lines to $Message about 100%
    dialog_inputbox 30 70
    RESPONSE="${Result^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    echo
    if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      message_first_line "You must include M, G or %"
      RootSize=""
    else
      RootSize=$RESPONSE
      Partition="/root"
      select_filesystem
      RootType=${PartitionType}
    fi
  done
}

function guided_EFI_Swap() # Called by guided_EFI
{ # EFI - User sets variable: SwapSize
  # Clear display, show /boot and /root
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${RootSize} = "" ]
  do
    Title="/swap"
    # Clear display, show /boot and available space
    Message="$_BootPartition: ${BootSize}"
    Message="${Message}\n$_RootPartition: ${RootType} : ${RootSize}\n"
    message_first_line "You now have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"

    if [ ${FreeSpace} -gt 10 ]; then
      message_first_line "There is space for a"
      Message="$Message $_SwapPartition"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You may want to leave room for a /home partition"
    elif [ ${FreeSpace} -gt 5 ]; then
      message_first_line "There is space for a"
      Message="$Message $_SwapPartition"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You may want to leave room for a /home partition"
    else
      message_first_line "There is just space for a"
      Message="$Message $_SwapPartition"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
    fi
    enter_size

    dialog_inputbox 30 70
    RESPONSE="${Result^^}"
    case ${RESPONSE} in
    '' | 0) message_first_line "Do you wish to allocate a swapfile?"
      Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
      echo
      if [ $Response -eq 1 ]; then
        set_swap_file
      fi
      return
    ;;
    *) # Check that entry includes 'G or %'
      CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        message_first_line "You must include M, G or %"
        RootSize=""
      else
        SwapSize=$RESPONSE
      fi
    esac
  done
  # If no space remains, offer swapfile, else create swap partition
}

function guided_EFI_Home() # Called by guided_EFI
{ # EFI - Set variables: HomeSize, HomeType
  HomeSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${HomeSize} = "" ]
  do
    # Clear display, show /boot and available space

    Message="${_BootPartition}: ${BootSize}"
    Message="${Message}\n$_RootPartition: ${RootType} : ${RootSize}"
    Message="${Message}\n$_SwapPartition: ${SwapSize}\n"

    Title="/home"

    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message $Result"

    message_subsequent "There is space for a"
    Message="$Message $_HomePartition"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    enter_size

    dialog_inputbox 30 75
    RESPONSE="${Result^^}"
    echo
    case ${RESPONSE} in
      "" | 0) HomeSize=""
      ;;
      *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          message_first_line "You must include M, G or %"
          HomeSize=""
        else
          HomeSize=$RESPONSE
          Partition="/home"
          print_heading
          select_filesystem
          HomeType=${PartitionType}
        fi
    esac
  done
}

function last_chance()  # Called by action_EFI & action_MBR
{
  message_first_line "That's all the preparation done"
  message_subsequent "Feliz will now create a new partition table"
  message_subsequent "and set up the partitions you have defined"
  Message="$Message\n"
  message_subsequent "This will erase any data on"
  Message="$Message ${UseDisk}"
  message_subsequent "Are you sure you wish to continue?"

  dialog --backtitle "$Backtitle" --yesno "$Message" 30 75
}

function action_EFI() # Called during installation phase
{ # EFI Final step. Uses the variables set above to create GPT partition table & all partitions
  # Get user approval
  Message="${_BootPartition}: ${BootSize}"
  Message="$Message\n${_RootPartition}: ${RootType} : ${RootSize}"
  Message="$Message\n$_SwapPartition :" "${SwapSize}"
  Message="$Message\n$_HomePartition :" "${HomeType} : ${HomeSize}\n"
  last_chance
  if [ $retval -ne 0 ]
  then
    UseDisk=""
    return 1                    # Go right back to start
  fi
  # Format the drive for EFI
    tput setf 0                 # Change foreground colour to black temporarily to hide error message
    sgdisk --zap-all /dev/sda   # Remove all partitions
    wipefs -a /dev/sda          # Remove filesystem
    tput sgr0                   # Reset colour
    parted_script "mklabel gpt"        # Create EFI partition table
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
    parted_script "mkpart primary fat32 1MiB ${EndPoint}MiB"
    parted_script "set 1 boot on"
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
    parted_script "mkpart primary ${RootType} ${NextStart}MiB ${EndPoint}"
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
      parted_script "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
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
      parted_script "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
      HomePartition="${GrubDevice}4"    # "/dev/sda4"
      Home="Y"
      AddPartList[0]="${GrubDevice}4"   # /dev/sda4     | add to
      AddPartMount[0]="/home"           # Mountpoint    | array of
      AddPartType[0]="ext4"             # Filesystem    | additional partitions
    fi

  translate "partitioning_options of"
  Title="${Result} ${GrubDevice}"
  Message="${Message}\n${_BootPartition}: $(lsblk -l | grep "${UseDisk}1" | awk '{print $4, $1}')"
  Message="${Message}\n${_RootPartition}: $(lsblk -l | grep "${UseDisk}2" | awk '{print $4, $1}')"
  Message="${Message}\n${_SwapPartition}: $(lsblk -l | grep "${UseDisk}3" | awk '{print $4, $1}')"
  Message="${Message}\n${_HomePartition}: $(lsblk -l | grep "${UseDisk}4" | awk '{print $4, $1}')"

  dialog --backtitle "$Backtitle" --title "$Title" --yesno "$Message" 20 70
  if [ $? -ne 0 ]; then return 1; fi
  
  AutoPart="GUIDED"                     # If accepted, set flag for formatting and mounting

}

function guided_MBR_root() # Called by guided_MBR
{ # BIOS - Set variables: RootSize, RootType
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ "$RootSize" = "" ]
  do
    # Clear display, show /boot and available space
    Title="/root"
    message_first_line "We begin with the"
    Message="$Message ${_RootPartition}\n"
    message_subsequent "You have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    message_subsequent "although you may want to leave room for a /swap partition"
    message_subsequent "and perhaps also a /home partition"
    message_subsequent "The /root partition should not be less than 8GiB"
    message_subsequent "ideally more, up to 20GiB"
    enter_size
    dialog_inputbox 30 75
    if [ $? -ne 0 ]; then return 1; fi
    RESPONSE="${Result^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    if [ -z ${CheckInput} ]; then
      RootSize=""
    elif [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      message_first_line "You must include M, G or %"
      dialog --backtitle "$Backtitle" --msgbox "$Message"
      RootSize=""
    else
      RootSize=$RESPONSE
      Partition="/root"
      print_heading
      translate "allocated to /root"
      message_first_line "${RootSize}" "$Result"
      select_filesystem
      RootType=${PartitionType}
    fi
  done
}

function guided_MBR_swap() # Called by guided_MBR
{ # BIOS - Set variable: SwapSize
  # Clear display, show /boot and /root
  FreeGigs=$((FreeSpace/1024))
  SwapSize=""
  while [ SwapSizeSize = "" ]
  do
    # Clear display, show /root and available space
    Title="/swap"
    Message="$_RootPartition: ${RootType} : ${RootSize}\n"

    message_subsequent "You now have"
    Message="$Message ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"

    if [ ${FreeSpace} -gt 10 ]; then
      message_subsequent "There is space for a"
      Message="$Message ${_SwapPartition}\n"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You may want to leave room for a /home partition"
    elif [ ${FreeSpace} -gt 5 ]; then
      message_subsequent "There is space for a"
      Message="$Message ${_SwapPartition}\n"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You can use all the remaining space on the device, if you wish"
      message_subsequent "You may want to leave room for a /home partition"
    else
      message_subsequent "There is just space for a"
      Message="$Message ${_SwapPartition}\n"
      message_subsequent "Swap can be anything from 512MiB upwards but"
      message_subsequent "it is not necessary to exceed 4GiB"
      message_subsequent "You can use all the remaining space on the device, if you wish"
    fi
    enter_size
    dialog_inputbox 30 75
    RESPONSE="${Result^^}"

    case ${RESPONSE} in
    '') message_first_line "Do you wish to allocate a swapfile?"
      dialog --backtitle "$Backtitle" --yesno "$Message" 10 50
      if [ $retval -eq 0 ]; then
        print_heading
        set_swap_file
      fi
      return
    ;;
    *) # Check that entry includes 'G or %'
      CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        message_first_line "You must include M, G or %"
        dialog --backtitle "$Backtitle" --msgbox "$Message"
        SwapSizeSize=""
      else
        SwapSize=$RESPONSE
      fi
    esac
  done
  # If no space remains, offer swapfile, else create swap partition
}

function guided_MBR_home() # Called by guided_MBR
{ # BIOS - Set variables: HomeSize, HomeType
  FreeGigs=$((FreeSpace/1024))
  HomeSize=""
  while [ HomeSize = "" ]
  do
    # Clear display, show /root, /swap and available space
    Title="/home"
    Message="$_RootPartition : ${RootType} : ${RootSize}"
    message_subsequent "$_SwapPartition : ${SwapSize}\n"

    translate "You now have"
    Message="${Message} ${FreeGigs}GiB"
    translate "available on the chosen device"
    Message="$Message ${Result}\n"

    message_subsequent "There is space for a"
    Message="${Message} $_HomePartition"
    message_subsequent "You can use all the remaining space on the device, if you wish"
    enter_size

    dialog_inputbox 12 70
    RESPONSE="${Result^^}"
    echo
    case ${RESPONSE} in
    "") return
    ;;
    *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        message_first_line "You must include M, G or %"
        dialog --backtitle "$Backtitle" --msgbox "$Message"
        HomeSize=""
      else
        HomeSize=$RESPONSE
        Partition="/home"
        translate "of remaining space allocated to"
        Message="${HomeSize}" "$Result $_HomePartition"
        select_filesystem
        HomeType=${PartitionType}
      fi
    esac
  done
}

function action_MBR() # Called by guided_MBR
{ # Final partitioning step - Uses the variables set above to create partition table & all partitions
    # Get user approval
    print_heading
    if [ -n "${RootSize}" ]; then
      message_first_line "$_RootPartition " ": ${RootType} : ${RootSize}"
    fi
    if [ -n "${SwapSize}" ]; then
      message_first_line "$_SwapPartition " ": ${SwapSize}"
    elif [ -n "${SwapFile}" ]; then
      message_first_line "$_SwapFile " ": ${SwapFile}"
    fi
    if [ -n "${HomeSize}" ]; then
      message_first_line "$_HomePartition :" "${HomeType} : ${HomeSize}"
    fi
    last_chance
    case $retval in
      0) parted_script "mklabel msdos"       # Create mbr partition table
      ;;
      *) UseDisk=""
        check_parts                    # Go right back to start
    esac

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
    parted_script "mkpart primary ext4 1MiB ${EndPoint}"
    parted_script "set 1 boot on"
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
      parted_script "mkpart primary linux-swap ${NextStart}MiB ${EndPoint}"
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
      parted_script "mkpart primary ${HomeType} ${NextStart}MiB ${EndPoint}"
      HomePartition="${GrubDevice}3"    # "/dev/sda3"
      Home="Y"
      AddPartList[0]="${GrubDevice}3"   # /dev/sda3     | add to
      AddPartMount[0]="/home"           # Mountpoint    | array of
      AddPartType[0]="${HomeType}"      # Filesystem    | additional partitions
    fi
  AutoPart="GUIDED"                     # Set flag for formatting and mounting
}
