#!/bin/bash

# The Feliz installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 14th October 2017

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
# TestUEFI            41     EasyRecalc          262     WipeDevice         601
# AllocateAll        708     EasyBoot            278     GuidedMBR          608
# AllocateEFI         97     EasyRoot            309     GuidedRoot         652
# EasyEFI            136     EasySwap            354     GuidedSwap         701
# EasyDevice         178     EasyHome            422     GuidedHome         771
# EasyDiskSize       215     ActionEasyPart      469     ActionGuided       819
# -----------------------    ------------------------    -----------------------

function TestUEFI() # Called at launch of Feliz script, before all other actions
{ # Change foreground colour to black temporarily to hide error messages
  tput setf 0
  dmesg | grep -q "efi: EFI"          # Test for EFI (-q tells grep to be quiet)
  if [ $? -eq 0 ]; then               # check exit code; 0 = EFI, else BIOS
    UEFI=1                            # Set variable UEFI ON
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2> feliz.log
  else
    UEFI=0                            # Set variable UEFI OFF
  fi
 tput sgr0                            # Reset colour
}

function AllocateEFI() # Called at start of AllocateRoot, before allocating root partition
{  # Uses list of available partitions in PartitionList created in f-part1.sh/BuildPartitionLists

	Remaining=""
	local Counter=0
  Partition=""
	PartitionType=""

	Translate "Here are the partitions that are available"
  Title="$Result"
	PrintOne "First you should select one to use for EFI /boot"
	PrintMany "This must be of type vfat, and may be about 512MiB"
  PartitionMenu
  if [ $retval -ne 0 ]; then return; fi
  PassPart="/dev/${Result}" # eg: sda1
  SetLabel "/dev/${Result}"
	EFIPartition="/dev/${Result}"
  PartitionList=$(echo "$PartitionList" | sed "s/$Result //")  # Remove selected item

  Parted "set 1 boot on"    # Make /root Bootable
}

function EasyEFI()
{ # Main EFIfunction - Inform user of purpose, call each step

  EasyDevice                # Get details of device to use
  EasyDiskSize              # Get available space in MiB

  PrintOne "Here you can set the size and format of the partitions"
  PrintMany "you wish to create. When ready, Feliz will wipe the disk"
  PrintMany "and create a new partition table with your settings"
  Message="${Message}\n"
  PrintMany "We begin with the"
  Message="$Message $_BootPartition"

  EasyBoot                  # Create /boot partition
  EasyRecalc "$BootSize"    # Recalculate remaining space
  EasyRoot                  # Create /root partition
  EasyRecalc "$RootSize"    # Recalculate remaining space after adding /root
  if [ ${FreeSpace} -gt 0 ]; then
    EasySwap
  else

    PrintOne "There is no space for a /swap partition, but you can"
    PrintMany "assign a swap-file. It is advised to allow some swap"
    PrintMany "Do you wish to allocate a swapfile?"

    dialog --backtitle "$Backtitle" --title " $Title " --yesno "\n$Message" 10 55 2>output.file
    retval=$?
    if [ $retval -eq 0 ]; then
      print_heading
      echo
      SetSwapFile           # Note: Global variable SwapFile is set by SetSwapFile
    fi                      # (SwapFile is created during installation by MountPartitions)
  fi
  
  if [ $SwapSize ]; then
    EasyRecalc "$SwapSize"  # Recalculate remaining space after adding /swap
  fi
  
  if [ ${FreeSpace} -gt 2 ]; then
    EasyHome
  fi
  ActionEasyPart            # Perform formatting and partitioning
}

function EasyDevice()
{ # EFI - User chooses device to use for auto partition from all connected devices
  DiskDetails=$(lsblk -l | grep 'disk' | cut -d' ' -f1)     # eg: sda sdb
  UseDisk=$DiskDetails                                      # If more than one, $UseDisk will be first
  local Counter=$(echo "$DiskDetails" | wc -w)
  if [ $Counter -gt 1 ]   # If there are multiple devices
  then                    # ask user which to use
    UseDisk=""            # Reset for user choice
    while [ -z $UseDisk ]
    do
      PrintOne "There are"
      Message="$Message $Counter"
      Translate "devices available"
      Message="$Message $Result"
      PrintMany "Which do you wish to use for this installation?"

      Counter=0
      for i in $DiskDetails
      do
        Counter=$((Counter+1))
        PrintOne "" "$Counter) $i"
      done

      Translate "Please enter the number of your selection"
      Title="$Result"
      echo $DiskDetails > checklist.file

      Checklist 12 60 "--nocancel" "--radiolist"
      UseDisk="${Result}"
    done
  fi
  GrubDevice="/dev/${UseDisk}"  # Full path of selected device
}

function EasyDiskSize()
{ # Establish size of device in MiB and inform user
  DiskSize=$(lsblk -l | grep "${UseDisk}\ " | awk '{print $4}') # 1) Get disk size eg: 465.8G
  Unit=${DiskSize: -1}                                          # 2) Save last character (eg: G)
  # Remove last character for calculations
  Chars=${#DiskSize}              # Count characters in variable
  Available=${DiskSize:0:Chars-1} # Separate the value from the unit
  # Must be integer, so remove any decimal point and any character following
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
  # Warn user if space is limited
  if [ ${FreeSpace} -lt 2048 ]; then      # If less than 2GiB
    PrintOne "Your device has only"
    Message="$Message ${FreeSpace}MiB:"
    PrintOne "This is not enough for an installation"
    Translate "Exit"
    dialog --backtitle "$Backtitle" --infobox "$Message" 10 60
    exit
  elif [ ${FreeSpace} -lt 4096 ]; then    # If less than 4GiB
    PrintOne "Your device has only"
    Message="$Message ${FreeSpace}MiB:"
    PrintMany "This is just enough for a basic"
    PrintMany "installation, but you should choose light applications only"
    PrintMany "and you may run out of space during installation or at some later time"
    dialog --backtitle "$Backtitle" --infobox "$Message" 10 60
  elif [ ${FreeSpace} -lt 8192 ]; then    # If less than 8GiB
    PrintOne "Your device has"
    Messgae="$Message ${FreeSpace}MiB:"
    PrintMany "This is enough for"
    PrintMany "installation, but you should choose light applications only"
    dialog --backtitle "$Backtitle" --infobox "$Message" 10 60
  fi
}

function EasyRecalc()
{  # EFI - Calculate remaining disk space
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

function EasyBoot()
{ # EFI - Set variable: BootSize
  BootSize=""
  while [ ${BootSize} = "" ]
  do
    FreeGigs=$((FreeSpace/1024))
    PrintOne "You have"
    Message="$Message ${FreeGigs}GiB"
    Translate "available on the chosen device"
    Message="$Message ${Result}\n"
    PrintMany "All we need to set here is the size of your /boot partition"
    PrintMany "It should be no less than 512MiB and need be no larger than 1GiB"

    InputBox 12 70
    RESPONSE="${Result^^}"
    # Check that entry includes 'M or G'
    CheckInput=${RESPONSE: -1}
    echo
    if [ ${CheckInput} != "M" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      PrintOne "You must include M, G or %"
      dialog --backtitle "$Backtitle" --infobox "$Message" 10 60
      BootSize=""
    else
      BootSize="${RESPONSE}"
    fi
  done
}

function EasyRoot()
{ # EFI - Set variables: RootSize, RootType
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${RootSize} = "" ]
  do
    # Clear display, show /boot and available space
    Message="$_BootPartition: ${BootSize}\n"
    PrintMany "You now have"
    Message="$Message ${FreeGigs}GiB"
    Translate "available on the chosen device"
    Message="$Message ${Result}\n"
    PrintMany "A partition is needed for /root"
    PrintMany "You can use all the remaining space on the device, if you wish"
    PrintMany "although you may want to leave room for a /swap partition"
    PrintMany "and perhaps also a /home partition"
    PrintMany "The /root partition should not be less than 8GiB"
    PrintMany "ideally more, up to 20GiB"
    AllocateAll       # Adds extra lines to $Message about 100%
    InputBox 30 70
    RESPONSE="${Result^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    echo
    if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      PrintOne "You must include M, G or %"
      RootSize=""
    else
      RootSize=$RESPONSE
      Partition="/root"
      select_filesystem
      RootType=${PartitionType}
    fi
  done
}

EasySwap() { # EFI - Set variable: SwapSize
  # Clear display, show /boot and /root
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${RootSize} = "" ]
  do
    # Clear display, show /boot and available space
    Message="$_BootPartition: ${BootSize}"
    Message="${Message}\n$_RootPartition: ${RootType} : ${RootSize}\n"
    PrintOne "You now have"
    Message="$Message ${FreeGigs}GiB"
    Translate "available on the chosen device"
    Message="$Message ${Result}\n"

    if [ ${FreeSpace} -gt 10 ]; then
      PrintOne "There is space for a"
      Message="$Message $_SwapPartition"
      PrintMany "Swap can be anything from 512MiB upwards but"
      PrintMany "it is not necessary to exceed 4GiB"
      PrintMany "You may want to leave room for a /home partition"
    elif [ ${FreeSpace} -gt 5 ]; then
      PrintOne "There is space for a"
      Message="$Message $_SwapPartition"
      PrintMany "Swap can be anything from 512MiB upwards but"
      PrintMany "it is not necessary to exceed 4GiB"
      PrintMany "You may want to leave room for a /home partition"
    else
      PrintOne "There is just space for a"
      Message="$Message $_SwapPartition"
      PrintMany "Swap can be anything from 512MiB upwards but"
      PrintMany "it is not necessary to exceed 4GiB"
    fi
    AllocateAll

    InputBox 30 70
    RESPONSE="${Result^^}"
    case ${RESPONSE} in
    '' | 0) PrintOne "Do you wish to allocate a swapfile?"
      Buttons "Yes/No" "$_Yes $_No" "$_Instructions"
      echo
      if [ $Response -eq 1 ]; then
        SetSwapFile
      fi
      return
    ;;
    *) # Check that entry includes 'G or %'
      CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        PrintOne "You must include M, G or %"
        RootSize=""
      else
        SwapSize=$RESPONSE
      fi
    esac
  done
  # If no space remains, offer swapfile, else create swap partition
}

function EasyHome()
{ # EFI - Set variables: HomeSize, HomeType
  HomeSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${HomeSize} = "" ]
  do
    # Clear display, show /boot and available space

    Message="${_BootPartition}: ${BootSize}"
    Message="${Message}\n$_RootPartition: ${RootType} : ${RootSize}"
    Message="${Message}\n$_SwapPartition: ${SwapSize}\n"

    PrintMany "You now have"
    Message="$Message ${FreeGigs}GiB"
    Translate "available on the chosen device"
    Message="$Message $Result"

    PrintMany "There is space for a"
    Message="$Messahe $_HomePartition"
    PrintMany "You can use all the remaining space on the device, if you wish"
    Translate "Please enter the desired size"
    Title="$Result"

    InputBox 30 75
    RESPONSE="${Result^^}"
    echo
    case ${RESPONSE} in
      "" | 0) HomeSize=""
      ;;
      *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
        if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
          PrintOne "You must include M, G or %"
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

function last_chance()
{
  PrintMany "That's all the preparation done"
  PrintMany "Feliz will now create a new partition table"
  PrintMany "and set up the partitions you have defined"
  Message="$Message\n"
  PrintMany "This will erase any data on"
  Message="$Message ${UseDisk}"
  PrintMany "Are you sure you wish to continue?"

  dialog --backtitle "$Backtitle" --yesno "$Message" 30 75
}

function ActionEasyPart()
{ # EFI Final step. Uses the variables set above to create GPT partition table & all partitions
  # Get user approval
  Message="${_BootPartition}: ${BootSize}"
  Message="$Message\n${_RootPartition}: ${RootType} : ${RootSize}"
  Message="$Message\n$_SwapPartition :" "${SwapSize}"
  Message="$Message\n$_HomePartition :" "${HomeType} : ${HomeSize}\n"
  last_chance
  case $retval in
    0) WipeDevice                   # Format the drive
      Parted "mklabel gpt"          # Create EFI partition table
      return
     ;;
    1) UseDisk=""
      CheckParts                    # Go right back to start
      ;;
      *) not_found; UseDisk=""; return
  esac

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

  Translate "Partitioning of"
  Title="${Result} ${GrubDevice}"
  Message="${Message}\n${_BootPartition}: $(lsblk -l | grep "${UseDisk}1" | awk '{print $4, $1}')"
  Message="${Message}\n${_RootPartition}: $(lsblk -l | grep "${UseDisk}2" | awk '{print $4, $1}')"
  Message="${Message}\n${_SwapPartition}: $(lsblk -l | grep "${UseDisk}3" | awk '{print $4, $1}')"
  Message="${Message}\n${_HomePartition}: $(lsblk -l | grep "${UseDisk}4" | awk '{print $4, $1}')"
  
  AutoPart=1                  # Treat as auto-partitioned. Set flag to 'on' for mounting

  dialog --backtitle "$Backtitle" --title "$Title" --yesno "$Message" 20 70
}

function WipeDevice()
{ # Format the drive for EFI
  tput setf 0                 # Change foreground colour to black temporarily to hide error message
  sgdisk --zap-all /dev/sda   # Remove all partitions
  wipefs -a /dev/sda          # Remove filesystem
  tput sgr0                   # Reset colour
}

function GuidedMBR()
{ # Main MBR function - Inform user of purpose, call each step
  PrintOne "Here you can set the size and format of the partitions"
  PrintMany "you wish to create. When ready, Feliz will wipe the disk"
  PrintMany "and create a new partition table with your settings"
  PrintMany "This facility is restricted to creating /root, /swap and /home"
  Message="${Message}\n"
  PrintMany "Are you sure you wish to continue?"
  dialog --backtitle "$Backtitle" --yesno "$Message" 15 70
  if [ $retval -eq 2 ]; then
    CheckParts                # Go right back to start
  fi
  EasyDevice                  # Get details of device to use
  EasyDiskSize                # Get available space in MiB
  GuidedRoot                  # Create /root partition
  EasyRecalc "$RootSize"      # Recalculate remaining space after adding /root
  if [ ${FreeSpace} -gt 0 ]; then
    GuidedSwap
  else
    PrintOne "There is no space for a /swap partition, but you can"
    PrintMany "assign a swap-file. It is advised to allow some swap"
    Message="${Message}\n"
    PrintMany "Do you wish to allocate a swapfile?"
    dialog --backtitle "$Backtitle" --yesno "$Message" 15 70
    if [ $retval -eq 1 ]; then
      SetSwapFile # Note: Global variable SwapFile is set by SetSwapFile
    fi            # and SwapFile is created during installation by MountPartitions
  fi
  
  if [ $SwapSize ]; then
    EasyRecalc "$SwapSize"  # Recalculate remaining space after adding /swap
  fi
  
  if [ ${FreeSpace} -gt 2 ]; then
    GuidedHome
  fi
  
  # Perform formatting and partitioning
  ActionGuided
}

function GuidedRoot()
{ # BIOS - Set variables: RootSize, RootType
  RootSize=""
  FreeGigs=$((FreeSpace/1024))
  while [ ${RootSize} = "" ]
  do
    # Clear display, show /boot and available space
    PrintOne "We begin with the"
    Message="$Message ${_RootPartition}\n"
    PrintMany "You have"
    Message="$Message ${FreeGigs}GiB"
    Translate "available on the chosen device"
    Message="$Message ${Result}\n"

    PrintMany "You can use all the remaining space on the device, if you wish"
    PrintMany "although you may want to leave room for a /swap partition"
    PrintMany "and perhaps also a /home partition"
    PrintMany "The /root partition should not be less than 8GiB"
    PrintMany "ideally more, up to 20GiB"
    AllocateAll
    InputBox 30 75
    RESPONSE="${Result^^}"
    # Check that entry includes 'G or %'
    CheckInput=${RESPONSE: -1}
    echo
    if [ -z ${CheckInput} ]; then
      RootSize=""
    elif [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
      PrintOne "You must include M, G or %"
      dialog --backtitle "$Backtitle" --msgbox "$Message"
      RootSize=""
    else
      RootSize=$RESPONSE
      Partition="/root"
      print_heading
      Translate "allocated to /root"
      PrintOne "${RootSize}" "$Result"
      select_filesystem
      RootType=${PartitionType}
    fi
  done
}

function GuidedSwap()
{ # BIOS - Set variable: SwapSize
  # Clear display, show /boot and /root
  FreeGigs=$((FreeSpace/1024))
  SwapSize=""
  while [ SwapSizeSize = "" ]
  do
    # Clear display, show /root and available space

    Message="$_RootPartition: ${RootType} : ${RootSize}\n"

    PrintMany "You now have"
    Message="$Message ${FreeGigs}GiB"
    Translate "available on the chosen device"
    Message="$Message ${Result}\n"

    if [ ${FreeSpace} -gt 10 ]; then
      PrintMany "There is space for a"
      Message="$Message ${_SwapPartition}\n"
      PrintMany "Swap can be anything from 512MiB upwards but"
      PrintMany "it is not necessary to exceed 4GiB"
      PrintMany "You may want to leave room for a /home partition"
    elif [ ${FreeSpace} -gt 5 ]; then
      PrintMany "There is space for a"
      Message="$Message ${_SwapPartition}\n"
      PrintMany "Swap can be anything from 512MiB upwards but"
      PrintMany "it is not necessary to exceed 4GiB"
      PrintMany "You can use all the remaining space on the device, if you wish"
      PrintMany "You may want to leave room for a /home partition"
    else
      PrintMany "There is just space for a"
      Message="$Message ${_SwapPartition}\n"
      PrintMany "Swap can be anything from 512MiB upwards but"
      PrintMany "it is not necessary to exceed 4GiB"
      PrintMany "You can use all the remaining space on the device, if you wish"
    fi
    AllocateAll
    InputBox 30 75
    RESPONSE="${Result^^}"

    case ${RESPONSE} in
    '') PrintOne "Do you wish to allocate a swapfile?"
      dialog --backtitle "$Backtitle" --yesno "$Message" 10 50
      if [ $retval -eq 0 ]; then
        print_heading
        SetSwapFile
      fi
      return
    ;;
    *) # Check that entry includes 'G or %'
      CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        PrintOne "You must include M, G or %"
        dialog --backtitle "$Backtitle" --msgbox "$Message"
        SwapSizeSize=""
      else
        SwapSize=$RESPONSE
      fi
    esac
  done
  # If no space remains, offer swapfile, else create swap partition
}

function GuidedHome()
{ # BIOS - Set variables: HomeSize, HomeType
  FreeGigs=$((FreeSpace/1024))
  HomeSize=""
  while [ HomeSize = "" ]
  do
    # Clear display, show /root, /swap and available space

    Message="$_RootPartition : ${RootType} : ${RootSize}"
    PrintMany "$_SwapPartition : ${SwapSize}\n"

    Translate "You now have"
    Message="${Message} ${FreeGigs}GiB"
    Translate "available on the chosen device"
    Message="$Message ${Result}\n"

    PrintMany "There is space for a"
    Message="${Message} $_HomePartition"
    PrintMany "You can use all the remaining space on the device, if you wish"
    AllocateAll

    InputBox 12 70
    RESPONSE="${Result^^}"
    echo
    case ${RESPONSE} in
    "") return
    ;;
    *) # Check that entry includes 'G or %'
        CheckInput=${RESPONSE: -1}
      if [ ${CheckInput} != "%" ] && [ ${CheckInput} != "G" ] && [ ${CheckInput} != "M" ]; then
        PrintOne "You must include M, G or %"
        dialog --backtitle "$Backtitle" --msgbox "$Message"
        HomeSize=""
      else
        HomeSize=$RESPONSE
        Partition="/home"
        Translate "of remaining space allocated to"
        Message="${HomeSize}" "$Result $_HomePartition"
        select_filesystem
        HomeType=${PartitionType}
      fi
    esac
  done
}

AllocateAll() {
  PrintMany "Please enter the desired size"
  PrintMany "or, to allocate all the remaining space, enter"
  Message="$Message 100%"
}

ActionGuided() { # Final BIOS step - Uses the variables set above to create partition table & all partitions
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
    last_chance
    case $retval in
      0) Parted "mklabel msdos"       # Create mbr partition table
      ;;
      *) UseDisk=""
        CheckParts                    # Go right back to start
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
