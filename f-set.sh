#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 5th December 2017

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation - either version 2 of the License, or
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

# In this module: functions for setting variables used during installation
# --------------------   -----------------------
# Function        Line   Function           Line
# --------------------   -----------------------
# Checklist         43   Options             604
# Menu              80   PickLuxuries        647
# NumberMenu       124   ShoppingList        695
# SetTimeZone      170   select_from         755
# SetSubZone       224   ChooseDM            810
# America          268   SetGrubDevice       860
# DoCities         319   EnterGrubPath       893
# setlocale        342   SetKernel           921
# Mano             417   ChooseMirrors       941
# getkeymap        437   ConfirmVbox        1007
# SearchKeyboards  499    --- Review stage --- 
# Username         556   FinalCheck         1030
# SetHostname      580   ManualSettings     1162
# --------------------   -----------------------

function Checklist()
{ # New function to display a Dialog checklist from checklist.file
  # $1 and $2 are dialog box size; $3 is optional "--nocancel" $4 is checklist/radiolist switch
  if [ $3 ] && [ $3 = "--nocancel" ]; then 
    cancel="$3"
  else
    cancel=""
  fi
  if [ $4 ]; then 
    Type="$4"
  else
    Type="--checklist"
  fi
  
  # 1) Prepare list for display
    declare -a ItemList=()                                    # Array will hold entire checklist
    Items=0
    Counter=1
    while read -r Item                                        # Read items from the existing list
    do                                                        # and copy each one to the variable
      Items=$((Items+1))
      ItemList[${Items}]="${Counter}"
      Counter=$((Counter+1)) 
      Items=$((Items+1))
      ItemList[${Items}]="${Item}" 
      Items=$((Items+1))
      ItemList[${Items}]="off"                            # with added off switch and newline
    done < checklist.file
    Items=$((Items/3))

  # 2) Display the list for user-selection
    dialog --backtitle "$_Backtitle" --title " $Title " "$cancel" --no-tags "$Type" \
      "     Space to select/deselect.\n       < OK > when ready. " $1 $2 ${Items} "${ItemList[@]}" 2>output.file
    retval=$?
    Result=$(cat output.file)
}

function ChooseMirrors()
{ # User selects one or more countries with Arch Linux mirrors
    _Backtitle="https://wiki.archlinux.org/index.php/Mirrors"
    # Prepare files of official Arch Linux mirrors
    # 1) Download latest list of Arch Mirrors to temporary file
    curl -s https://www.archlinux.org/mirrorlist/all/http/ > archmirrors.list
    if [ $? -ne 0 ]; then
      PrintOne "Unable to fetch list of mirrors from Arch Linux"
      PrintMany "Using the list supplied with the Arch iso"
      not_found 6 30
      cp /etc/pacman.d/mirrorlist > archmirrors.list
    fi
    # 2) Get line number of first country
    FirstLine=$(grep -n "Australia" archmirrors.list | head -n 1 | cut -d':' -f1)
    # 3) Remove header and save in new file
    tail -n +${FirstLine} archmirrors.list > allmirrors.list
    # 4) Delete temporary file
    rm archmirrors.list
    # 5) Create countries.list from allmirrors.list, using '##' to identify
    #                        then removing the '##' and leading spaces
    #                                       and finally save to new file for later reference
    grep "## " allmirrors.list | tr -d "##" | sed "s/^[ \t]*//" > countries.list
    # Shorten Bosnia and Herzegovina to BosniaHerzegov
    sed -i 's/Bosnia and Herzegovina/BosniaHerzegov/g' countries.list
}

function Menu()
{ # Display a simple menu from $MenuVariable and return selection as $Result
  # $1 and $2 are dialog box size;
  # $3 is optional: can be "--nocancel" or the text for --cancel-label
    
  if [ $3 ] && [ $3 = "--nocancel" ]; then 
    nocancel=1
  elif [ $3 ]; then
    nocancel=0
    cancel="$3"
  else
    nocancel=0
    cancel="Cancel"
  fi
  
  # Prepare array for display
  declare -a ItemList=()                                    # Array will hold entire list
  Items=0
  for Item in $MenuVariable                                 # Read items from the variable
  do 
    Items=$((Items+1))
    ItemList[${Items}]="${Item}"                            # and copy each one to the array
    Items=$((Items+1))
    ItemList[${Items}]="-"                                  # Second element is required
  done
   
  # Display the list for user-selection (two options: cancel or nocancel)
  case "$nocancel" in
  1) # The nocancel option
    dialog --backtitle "$_Backtitle" --title " $Title " --nocancel --menu \
      "$Message" \
      $1 $2 ${Items} "${ItemList[@]}" 2>output.file
    retval=$?
  ;;
  *) # The cancel-label option 
    dialog --backtitle "$_Backtitle" --title " $Title " --cancel-label "$cancel" --menu \
      "$Message" \
      $1 $2 ${Items} "${ItemList[@]}" 2>output.file
    retval=$?
  esac
  Result=$(cat output.file)
}

function NumberMenu()
{ # Similar to Menu. Display a menu from $MenuVariable and return selection as $Result
  # The only difference is that this menu displays numbered items
  # $1 and $2 are dialog box size;
  # $3 is optional: can be "--nocancel" or the text for --cancel-label
    
  if [ $3 ] && [ $3 = "--nocancel" ]; then 
    nocancel=1
  elif [ $3 ]; then
    nocancel=0
    cancel="$3"
  else
    nocancel=0
    cancel="Cancel"
  fi
  
  # Prepare array for display
  declare -a ItemList=()                                    # Array will hold entire list
  Items=0
  Counter=1
  for Item in $MenuVariable                                 # Read items from the variable
  do 
    Items=$((Items+1))
    ItemList[${Items}]="${Counter}"                         # and copy each one to the array
    Counter=$((Counter+1))
    Items=$((Items+1))
    ItemList[${Items}]="${Item}"                            # Second element is required
  done
   
  # Display the list for user-selection (two options: cancel or nocancel)
  case "$nocancel" in
  1) # The nocancel option
    dialog --backtitle "$_Backtitle" --title " $Title " --nocancel --menu \
      "$Message" \
      $1 $2 ${Items} "${ItemList[@]}" 2>output.file
    retval=$?
  ;;
  *) # The cancel-label option 
    dialog --backtitle "$_Backtitle" --title " $Title " --cancel-label "$cancel" --menu \
      "$Message" \
      $1 $2 ${Items} "${ItemList[@]}" 2>output.file
    retval=$?
  esac
  Result=$(cat output.file)
}

function SetTimeZone()
{
  SUBZONE=""
  while true
  do
    PrintOne "To set the system clock, please first"
    PrintMany "choose the World Zone of your location"
    timedatectl list-timezones | cut -d'/' -f1 | uniq > zones.file # Ten world zones
  
    declare -a ItemList=()                                    # Array will hold entire menu list
    Items=0
    Counter=1
    while read -r Item                                        # Read items from the zones file
    do                                                        # for display in menu
      Translate "$Item"
      Item="$Result"
      Items=$((Items+1))
      ItemList[${Items}]="${Counter}"                         # First column is the item number
      Counter=$((Counter+1)) 
      Items=$((Items+1))
      ItemList[${Items}]="${Item}"                            # Second column is the item
    done < zones.file
  
    dialog --backtitle "$_Backtitle" --no-cancel --menu \
        "\n      $Message\n" 20 50 $Counter "${ItemList[@]}" 2>output.file
        
    retval=$?
    Response=$(cat output.file)
    Result="$(head -n ${Response} zones.file | tail -n 1)"  # Read item from target language file
    NativeZONE="$Result"                                    # Save ZONE in user's language, for display  
  
    # Now translate the result back to English
    if [ $LanguageFile = "English.lan" ]; then              # It's already in English
      ZONE="$Result" 
    else
      # Get line number of "$Result" in $LanguageFile
      #                      exact match only | restrict to first find | display only number
      RecordNumber=$(grep -n "^${Result}$" "${LanguageFile}" | head -n 1 | cut -d':' -f1)
      # Find that line in English.lan
      ZONE="$(head -n ${RecordNumber} English.lan | tail -n 1)" # Read item from English language file
    fi
    
    # We now have a zone! eg: Europe
    SetSubZone                          # Call subzone function
    if [ "$SUBZONE" != "" ]; then       # If non-empty, Check "${ZONE}/$SUBZONE" against 
                                        # "timedatectl list-timezones"
      timedatectl list-timezones | grep "${ZONE}/$SUBZONE" > /dev/null
      if [ $? -eq 0 ]; then return; fi    # If "${ZONE}/$SUBZONE" found, return to caller
    fi
  done
}

function SetSubZone() # Called from SetTimeZone
{  # Use ZONE set in SetTimeZone to prepare list of available subzones
  while true
  do
    SubZones=$(timedatectl list-timezones | grep ${ZONE}/ | sed 's/^.*\///')
    Ocean=0
    SUBZONE=""
  
    case $ZONE in
    "Arctic") SUBZONE="Longyearbyen"
      return
    ;;
    "Atlantic") Ocean=1
    ;;
    "Indian") Ocean=1
    ;;
    "Pacific") Ocean=1
    ;;
    "America") America
      return
    esac
  
    # User-selection of subzone starts here:
    MenuVariable=$(timedatectl list-timezones | grep ${ZONE}/ | cut -d'/' -f2)
  
    Translate "Now select your location in"
    if [ $Ocean = 1 ]; then
      Title="$Result the $NativeZONE Ocean"
    else
      Title="  $Result $NativeZONE"
    fi
    Cancel="Back"
    Message=""
    
    Menu  24 40 # Function (arguments are dialog size) displays a menu and return selection as $Result
    if [ $retval -eq 0 ]; then
      SUBZONE="$Result"
    else
      SUBZONE=""
    fi
    return
  done
}

function America() # Called from SetSubZone
{ # Necessary because some zones in the Americas have a middle zone (eg: America/Argentina/Buenes_Aries)
  
  SUBZONE=""      # Make sure this variable is empty
  SubList=""      # Start an empty list
  Previous=""     # Prepare to save previous record
  local Toggle="First"
  for i in $(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $2}')
  do
    if [ $Previous ] && [ $i = $Previous ] && [ $Toggle = "First" ]; then # First reccurance
      SubList="$SubList $i"
      Toggle="Second"
    elif [ $Previous ] && [ $i != $Previous ] && [ $Toggle = "Second" ]; then # 1st occ after prev group
      Toggle="First"
      Previous=$i
    else                                                                  # Subsequent occurances
      Previous=$i
    fi
  done
  
  SubGroup=""
  Translate "Are you in any of these States?"
  Title="$Result"
  Translate "None_of_these"
  Cancel="$Result"
  MenuVariable="$SubList"
  Message=" "
  
  Menu  15 40 # (arguments are dialog size) displays a menu and returns $retval and $Result
  
  if [ $retval -eq 1 ]; then              # "None of These" - check normal subzones
    Translate "Now select your location in"
    Title="$Result $NativeZONE"
    MenuVariable=$(timedatectl list-timezones | grep ${ZONE}/ | grep -v 'Argentina\|Indiana\|Kentucky\|North_Dakota' | cut -d'/' -f2)  # Prepare variable
    Cancel="Back"
    Message=" "
    
    Menu  25 50 # Display menu (arguments are dialog size) and return selection as $Result
    if [ $retval -eq 0 ]; then    
      SUBZONE="$Result"
      DoCities
    else
      SUBZONE=""
    fi
  else                                    # This is for 2-part zones
    SubGroup=$Result                      # Save subgroup for next function
    ZONE="${ZONE}/$SubGroup"              # Add subgroup to ZONE
    DoCities                              # City function for subgroups
  fi
}

function DoCities()  # Called from America
{ # Specifically for America, which has subgroups
  # This function receives either 1-part or 2-part ZONE from America
  case $SubGroup in
  "") # No subgroup selected. Here we are working on the second field - cities without a subgroup
      MenuVariable=$(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $2}')
  ;;
  *) # Here we are working on the third field - cities within the chosen subgroup
      MenuVariable=$(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $3}')
   esac
  Translate "Please select a city from this list"
  Title="$Result"
  Cancel="Back"
  Message=" "
  
  Menu  25 44 # New function (arguments are dialog size) to display a menu and return $Result
  if [ $retval -eq 0 ]; then
    SUBZONE="$Result"
  else
    SUBZONE=""
  fi
}

function setlocale()
{ CountryLocale=""
  while [ -z "$CountryLocale" ]
  do
    _Backtitle="https://wiki.archlinux.org/index.php/Time#Time_zone"
    
    SetTimeZone # First get a validated ZONE/SUBZONE
    
    _Backtitle="https://wiki.archlinux.org/index.php/Locale"
    ZoneID="${ZONE}/${SUBZONE}"   # Use a copy (eg: Europe/London) to find in cities.list
                                  # (field 2 in cities.list is the country code (eg: GB)
    SEARCHTERM=$(grep "$ZoneID" cities.list | cut -d':' -f2)
    SEARCHTERM=${SEARCHTERM// }             # Ensure no leading spaces
    SEARCHTERM=${SEARCHTERM%% }             # Ensure no trailing spaces
    # Find all matching entries in locale.gen - This will be a table of valid locales in the form: en_GB.UTF-8
    EXTSEARCHTERM="${SEARCHTERM}.UTF-8"
    
    if [ $(grep "^NAME" /etc/*-release | cut -d'"' -f2 | cut -d' ' -f1) = "Debian" ]; then
      # In case testing in Debian
      LocaleList=$(grep "${EXTSEARCHTERM}" /etc/locale.gen | cut -d'#' -f2 | cut -d' ' -f2 | grep -v '^UTF')
    else
      # Normal Arch setting
      LocaleList=$(grep "${EXTSEARCHTERM}" /etc/locale.gen | cut -d'#' -f2 | cut -d' ' -f1)
    fi
    
    HowMany=$(echo $LocaleList | wc -w)     # Count them
    Rows=$(tput lines)                      # to ensure menu doesn't over-run
    Rows=$((Rows-4))                        # Available (printable) rows
    choosefrom="" 
    for l in ${LocaleList[@]}               # Convert to space-separated list
    do
      choosefrom="$choosefrom $l"           # Add each item to file for handling
    done
    if [ -z "${choosefrom}" ]; then         # If none found, start again
      not_found 10 30 "Locale not found"
      Result=""
    else
      Translate "Choose the main locale for your system"
      Title="$Result"
      Translate "Choose one or Exit to retry"
      Message="$Result"
      MenuVariable="$choosefrom Edit_locale.gen"                    # Add manual edit option to menu
      Cancel="Exit"
  
      Menu  25 44 # New function (arguments are dialog size) to display a menu and return $Result
      Response="$retval"
  
      if [ $Response -eq 1 ]; then                                  # If user chooses <Exit>
        CountryLocale=""                                            # Start again
        continue
      elif [ "$Result" == "Edit_locale.gen" ]; then                 # User chooses manual edit
        Mano                                                        # Use Nano to edit locale.gen
        retval=$?
        if [ $retval -eq 0 ]; then  # If Nano was used, get list of uncommented entries
          grep -v '#' /etc/locale.gen | grep ' ' | cut -d' ' -f1 > checklist.file 
          HowMany=$(wc -l checklist.file | cut -d' ' -f1)           # Count them
          case ${HowMany} in
          0) continue                                               # No uncommented lines found, so restart
          ;;
          1) Result="$(cat checklist.file)"                         # One uncommented line found, so set it as locale
          ;;
          *) Translate "Choose the main locale for your system"     # If many uncommented lines found
            Message="$Result"
            Checklist 10 40 "--nocancel" "--radiolist"              # Ask user to pick one as main locale
          esac
        else                                                        # Nano was not used
          continue                                                  # Start again
        fi
      fi
    fi
    CountryLocale="$Result"                                         # Save selection eg: en_GB.UTF-8
    CountryCode=${CountryLocale:3:2}                                # eg: GB
  done
}

Mano() {  # Use Nano to edit locale.gen
  while true
  do
    Translate "Start Nano so you can manually uncomment locales?" # New text for line 201 English.lan
    Message="$Result"
    Title=""
    dialog --backtitle "$_Backtitle" --title " $Title " --yesno "\n$Message" 6 55 2>output.file
    retval=$?
    case $retval in
      0) nano /etc/locale.gen
        return 0
        ;;
      1) return 1
        ;;
      *) not_found 10 50 "Error reported at function $FUNCNAME line $LINENO in $SOURCE0 called from $SOURCE1"
        return 2
    esac
  done
}

function getkeymap()
{ _Backtitle="https://wiki.archlinux.org/index.php/Keyboard_configuration_in_console"
  country="${CountryLocale,,}"                                          # From SetLocale - eg: en_gb.utf-8
  case ${country:3:2} in                                                # eg: gb
  "gb") Term="uk"
  ;;
  *) Term="${country:3:2}"
  esac
  
  ListKbs=$(grep ${Term} keymaps.list)
  Found=$(grep -c ${Term} keymaps.list)  # Count records
  if [ ! $Found ]; then
    Found=0
  fi
  
  Countrykbd=""
  while [ -z "$Countrykbd" ]
  do
    case $Found in
    0)  # If the search found no matches
      Translate "Sorry, no keyboards found based on your location"
      read_timed "$Result" 2
      SearchKeyboards
    ;;
    1)  # If the search found one match
      Translate "Only one keyboard found based on your location"
      Message="$Result"
      Translate "Do you wish to accept this? Select No to search for alternatives"
      Message="${Message}\n${Result}"
      
      dialog --backtitle "$_Backtitle" --yesno "\n$Message" 10 55 2>output.file
      
      retval=$?
      Result="$(cat output.file)"
      
      case ${retval} in
        0) Countrykbd="${Result}"
        ;;
        1) SearchKeyboards
        ;;
        *) exit
      esac
      loadkeys ${Countrykbd} 2>> feliz.log
    ;;
    *) # If the search found multiple matches
      MenuVariable="$ListKbs"
      Translate "Please choose one"
      Title="$Result"

      Menu 12 40 "--nocancel"
      case ${retval} in
        0) Countrykbd="${Result}"
        ;;
        1) SearchKeyboards
        ;;
        *) exit
      esac
      loadkeys ${Countrykbd} 2>> feliz.log
    esac
  done
}

function SearchKeyboards()
{ # Called by getkeymap when all other options failed 
  Countrykbd=""
  while [ -z "$Countrykbd" ]
  do
    Translate "If you know the code for your keyboard layout, please enter"
    Message="$Result"
    Translate "it now. If not, try entering a two-letter abbreviation"
    Message="${Message}\n${Result}"
    Translate "for your country or language and a list will be displayed"
    Message="${Message}\n${Result}"
    Translate "Alternatively, enter ' ' to start again"
    Message="${Message}\n${Result}\n"
    Translate "eg: 'dvorak' or 'us'"
    Message="${Message}\n${Result}\n"
    
    dialog --inputbox "$Message" 14 70 2>output.file
    retval=$?
    Result="$(cat output.file)"
    if [ $retval -eq 1 ] || [ $Result = "" ]; then
      Countrykbd=""
      return
    fi
    local Term="${Result,,}"
    ListKbs=$(grep ${Term} keymaps.list)
    if [ -n "${ListKbs}" ]; then  # If a match or matches found
      MenuVariable="$ListKbs"
      Translate "Select your keyboard, or Exit to try again"
      Message="$Result"
      Translate "Please choose one"
      Title="$Result"

      Menu 15 40
      if [ ${retval} -eq 1 ]; then    # Try again
        Countrykbd=""
        continue
      else
        ListKbs=$(grep ${Result} keymaps.list)    # Check if valid
        if [ -n "${ListKbs}" ]; then  # If a match or matches found
          Countrykbd="${Result}"
        else
          Translate "No keyboards found containing"
          not_found 8 40 "${Result}\n '$Term'"
          continue
        fi
      fi
      loadkeys ${Countrykbd} 2>> feliz.log
    else
      Translate "No keyboards found containing"
      not_found 8 40 "${Result}\n '$Term'"
      continue
    fi
  done
}

function UserName()
{ _Backtitle="https://wiki.archlinux.org/index.php/Users_and_groups"

  Translate "Enter a name for the primary user of the new system"
  Message="$Result"
  Translate "If you don't create a username here, a default user"
  Message="${Message}\n${Result}"
  Translate "called 'archie' will be set up"
  Message="${Message}\n${Result}\n"
  Translate "User Name"
  Title="${Result}"
  
  dialog --title " $Title " --inputbox "$Message" 12 70 2>output.file
  retval=$?
  Result="$(cat output.file)"

  if [ -z $Result ]; then
    UserName="archie"
  else
    Entered=${Result,,}
    UserName=${Entered}
  fi
}

function SetHostname()
{
  _Backtitle="https://wiki.archlinux.org/index.php/Network_configuration#Set_the_hostname"
  Translate "A hostname is needed. This will be a unique name to identify"
  Message="$Result"
  Translate "your device on a network. If you do not enter one, the"
  Message="${Message}\n${Result}"
  Translate "default hostname of 'arch-linux' will be used"
  Message="${Message}\n${Result}\n"
  Translate "Enter a hostname for your computer"
  Title="${Result}: "

  dialog --title " $Title " --inputbox "$Message" 12 70 2>output.file
  retval=$?
  Result="$(cat output.file)"

  if [ -z $Result ]; then
    HostName="arch-linux"
  else
    Entered=${Result,,}
    HostName=${Entered}
  fi
}

function Options() # User chooses between FelizOB, self-build or basic
{ _Backtitle="https://wiki.archlinux.org/index.php/List_of_applications"
  Translate "Feliz now offers you a choice. You can ..."
  Message="${Result}"
  Translate "Build your own system, by picking the"
  Message="${Message}\n\n1) ${Result}"
  Translate "software you wish to install"
  Message="${Message}\n${Result}\n\n               ... ${_or} ...\n"
  Translate "You can choose the new FelizOB desktop, a"
  Message="${Message}\n2) ${Result}"
  Translate "complete lightweight system built on Openbox"
  Message="${Message}\n${Result}\n\n               ... ${_or} ...\n"
  Translate "Just install a basic Arch Linux"
  Message="${Message}\n3) ${Result}\n"
  
  Translate "Build_My_Own"
  BMO="$Result"
  Translate "FelizOB_desktop"
  FOB="$Result"
  Translate "Basic_Arch_Linux"
  BAL="$Result"
  
  dialog --backtitle "$_Backtitle" --title " Options " --nocancel --menu "$Message" \
      24 50 3 \
      1 "$BMO" \
      2 "$FOB" \
      3  "$BAL" 2>output.file
  retval=$?
  Result=$(cat output.file)

  case $Result in
    1) PickLuxuries
    ;;
    2) DesktopEnvironment="FelizOB"
      Scope="Full"
    ;;
    *) Scope="Basic"
  esac
}

function PickLuxuries()  # Menu of categories of selected items from the Arch repos
{ Translate "Added so far"
  AddedSoFar="$Result"
  # Translate the categories
  TransCatList=""
  for category in $CategoriesList
  do
    Translate "$category"
    TransCatList="$TransCatList $Result"
  done
  # Display categories, adding more items until user exits by <Done>
  LuxuriesList=""
  while true
  do
    # Prepare information messages
    if [ -z "$LuxuriesList" ]; then
      Translate "Now you have the option to add extras, such as a web browser"
      Message="$Result"
      Translate "desktop environment, etc, from the following categories"
      Message="\n${Message}\n${Result}"
    fi
    # Display categories as numbered list
    Title="Arch Linux"
    MenuVariable="${TransCatList}"
    NumberMenu  24 70 "Done"              # Displays numbered menu
    # Process exit variables
    if [ $retval -ne 0 ]; then
      if [ -n "${LuxuriesList}" ]; then
        Scope="Full"
      else
        Scope="Basic"
      fi
      return
    else
      Category=$Result
      ShoppingList                        # Function to add items to LuxuriesList
      if [ -n "$LuxuriesList" ]; then
        Translate "Added so far"
        Message="$Result: ${LuxuriesList}\n"
        Translate "You can now choose from any of the other lists"
        Message="${Message}\n${Result},"
        Translate "or choose Exit to finish this part of the setup"
        Message="${Message} ${Result}\n"
      fi
    fi
  done
}

function ShoppingList() # Called by PickLuxuries after a category has been chosen.
{ # Prepares to call 'select_from' function with copy data
  Translate "Added so far"
  Message="$Result: ${LuxuriesList}\n"
  Translate "You can add more items, or select items to delete"
  Message="${Message}\n${Result}"
  Title="${Categories[$Category]}" # $Category is number of item in CategoriesList
  
  local Counter=1
  MaxLen=0
  case $Category in
   1) # Create a copy of the list of items in the category
      Copycat="${Accessories}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongAccs"
    ;;
   2) # Create a copy of the list of items in the category
      Copycat="${Desktops}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongDesk"
    ;;
   3) # Create a copy of the list of items in the category
      Copycat="${Graphical}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongGraph"
    ;;
   4) # Create a copy of the list of items in the category
      Copycat="${Internet}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongNet"
     ;;
   5) # Create a copy of the list of items in the category
      Copycat="${Multimedia}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongMulti"
    ;;
   6) # Create a copy of the list of items in the category
      Copycat="${Office}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongOffice"
    ;;
   7) # Create a copy of the list of items in the category
      Copycat="${Programming}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongProg"
    ;;
   8) # Create a copy of the list of items in the category
      Copycat="${WindowManagers}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongWMs"
    ;;
   9) # Create a copy of the list of items in the category
      Copycat="${Taskbars}"
      # Pass the name of the relevant array to the translate_category function
      select_from "LongBars"
    ;;
    *) return
  esac
}

function select_from() # Called by ShoppingList
{ # Translates descriptions of items in the selected category
  # Then displays them for user to select multiple items
  # Note1: The name of the array to be processed has been passed as $1
  # Note2: A copy of the list of items in the category has been created
  # by the calling function as 'Copycat'
  
  # Get the array passed by name ...
    local name=$1[@]
    local CopyArray=("${!name}")    # eg: LongAccs or LongDesk, etc
  # Prepare temporary array for translated item descriptions
    declare -a TempArray=()
  # Translate all elements
    OptionsCounter=0
    for Option in "${CopyArray[@]}"
    do
      (( OptionsCounter+=1 ))
      Translate "$Option"
      CopyArray[${OptionsCounter}]="$Result"    # Replace element with translation
    done
    # Then build the temporary array for the checklist dialog
    Counter=0
    for i in ${Copycat}
    do
      (( Counter+=1 ))
      TempArray[${Counter}]="$i"
      (( Counter+=1 ))
      TempArray[${Counter}]="${CopyArray[${Counter}/2]}"
      (( Counter+=1 ))
      TempArray[${Counter}]="OFF"
      for a in ${LuxuriesList}                  # Check against LuxuriesList - if on list, mark ON
      do
        if [ "$a" = "$i" ]; then
          TempArray[${Counter}]="ON"
        fi
      done
    done
    # Remove all items in this group from LuxuriesList (selected items will be added back)
    if [ -n "$LuxuriesList" ]; then
      for i in ${Copycat}
      do
        LuxuriesList=$(echo "$LuxuriesList" | sed "s/$i//")
      done
    fi
    # Display the contents of the temporary array in a Dialog menu
    Items=$(( Counter/3 ))
    dialog --backtitle "$_Backtitle" --title " $Title " --nocancel --checklist \
      "$Message" 20 79 $Items "${TempArray[@]}" 2>output.file
    retval=$?
    Result=$(cat output.file)
    # Add selected items to LuxuriesList
    LuxuriesList="$LuxuriesList $Result"
    LuxuriesList=$( echo $LuxuriesList | sed "s/^ *//")        # Remove any leading spaces caused by deletions
}

function ChooseDM()
{ # Choose a display manager
  while true
  do
    _Backtitle="https://wiki.archlinux.org/index.php/Display_manager"
    case "$DisplayManager" in
    "") # Only offered if no other display manager has been set
      Counter=0
      Translate "Display Manager"
      Title="$Result"
      PrintOne "A display manager provides a graphical login screen"
      PrintMany "If in doubt, choose"
      Message="$Message LightDM"
      PrintMany "If you do not install a display manager, you will have"
      PrintMany "to launch your desktop environment manually"
      
      dialog --backtitle "$_Backtitle" --title " $Title " --menu "\n$Message" 20 60 6 \
        "GDM" "-" \
        "LightDM" "-" \
        "LXDM" "-" \
        "sddm" "-" \
        "SLIM" "-" \
        "XDM" "-" 2> output.file
      retval=$?
      if [ $retval -ne 0 ]; then return; fi
      DisplayManager="$(cat output.file)"
      return
    ;;
    *) # Warn that DM already set, and offer option to change it
      Translate "Display manager is already set as"
      Message="$Result : ${DisplayManager}"
      PrintMany "Only one display manager can be active"
      PrintMany "Do you wish to change it?"
      
      dialog --backtitle "$_Backtitle" --yesno "$Message" 10 50
      retval=$?
      if [ $retval -eq 0 ]; then      # User wishes to change DM
        DisplayManager=""             # Clear DM variable before restarting
      else
        return
      fi
    esac
  done
}

function SetGrubDevice()
{ # Set path for grub to be installed
  GrubDevice=""
  while [ -z $GrubDevice ]
  do
    DevicesList="$(lsblk -d | awk '{print "/dev/" $1}' | grep 'sd\|hd\|vd')"  # Preceed field 1 with '/dev/'
    _Backtitle="https://wiki.archlinux.org/index.php/GRUB"
    # Add an option to enter grub device manually
    Translate "Enter_Manually"
    Enter_Manually="$Result"
    MenuVariable="$DevicesList $Result"
    Title="Grub"
    GrubDevice=""
    local Counter=0
    PrintOne "Select the device where Grub is to be installed"
    PrintMany "Note that if you do not select a device, Grub"
    PrintMany "will not be installed, and you will have to make"
    PrintMany "alternative arrangements for booting your new system"

    Menu  20 60 # (arguments are dialog size) displays a menu and returns $retval and $Result
    if [ $Result = "$Enter_Manually" ]; then				# Call function to type in a path
      EnterGrubPath
      GrubDevice="$Result"
    else
      GrubDevice="$Result"
    fi
  done
}

function EnterGrubPath() # Manual input
{ GrubDevice=""
  while [ -z "$GrubDevice" ]
  do
    PrintOne "You have chosen to manually enter the path for Grub"
    PrintMany "This should be in the form /dev/sdx or similar"
    PrintMany "Only enter a device, do not include a partition number"
    PrintMany "If in doubt, consult https://wiki.archlinux.org/index.php/GRUB"
    
    InputBox 15 60    # Text input dialog
    if [ $retval -eq 0 ]; then return; fi
    Entered=${Result,,}
    # test input
    CheckGrubEntry="${Entered:0:5}"
    if [ -z $Entered ]; then
      return
    elif [ $CheckGrubEntry != "/dev/" ]; then
      not_found "$Entered is not in the correct format"
    else
      GrubDevice="${Entered}"
    fi
  done
}

function SetKernel()
{ _Backtitle="https://wiki.archlinux.org/index.php/Kernels"

  Translate " Choose your kernel "
  Title="$Result"
  Translate "The Long-Term-Support kernel offers stabilty"
  LTS="$Result"
  Translate "The Latest kernel has all the new features"
  Latest="$Result"
  Translate "If in doubt, choose"
  Default="${Result} LTS"

  dialog --backtitle "$_Backtitle" --title "$Title" --nocancel \
        --radiolist "\n  $Default" 10 70 2 \
        "1" "$LTS" ON \
        "2" "$Latest" off 2>output.file
  Response=$(cat output.file)
  Kernel=${Response} # Set the Kernel variable (1 = LTS; 2 = Latest)
}

function ChooseMirrors() # User selects one or more countries with Arch Linux mirrors
{ _Backtitle="https://wiki.archlinux.org/index.php/Mirrors"
  
  # 1) Prepare files of official Arch Linux mirrors
    # Download latest list of Arch Mirrors to temporary file
    curl -s https://www.archlinux.org/mirrorlist/all/http/ > archmirrors.list
    if [ $? -ne 0 ]; then
      Translate "Unable to fetch list of mirrors from Arch Linux"
      Message="$Result"
      Translate "Using the list supplied with the Arch iso"
      Message="${Message}\n${Result}"
      dialog --backtitle "$_Backtitle" \
       --msgbox "\n${Message}\n" 8 75
      cp /etc/pacman.d/mirrorlist > archmirrors.list
    fi

    # Get line number of first country
    FirstLine=$(grep -n "Australia" archmirrors.list | head -n 1 | cut -d':' -f1)
    
    # Remove header and save in new file
    tail -n +${FirstLine} archmirrors.list > allmirrors.list
    
    # Delete temporary file
    rm archmirrors.list
    
    # Create list of countries from allmirrors.list, using '##' to identify
    #                        then removing the '##' and leading spaces
    #                                       and finally save to new file for later reference
    grep "## " allmirrors.list | tr -d "##" | sed "s/^[ \t]*//" > checklist.file

  # 2) Display instructions
    print_heading
    Echo
    Translate "Next we will select mirrors for downloading your system."
    Message="$Result"
    Translate "You will be able to choose from a list of countries which"
    Message="${Message}\n${Result}"
    Translate "have Arch Linux mirrors. It is possible to select more than"
    Message="${Message}\n${Result}"
    Translate "one, but adding too many will slow down your installation"
    Message="${Message}\n${Result}\n"
    dialog --backtitle "$_Backtitle" \
         --msgbox "\n${Message}\n" 10 75

    # 3) User-selection of countries starts here:
    Translate "Please choose a country"
    Title="$Result"
    
    Checklist 25 70 "--nocancel" "--checklist"
  
    if [ $retval -eq 0 ] && [ "$Result" != "" ]; then
      break
    else
      read -p "You must select at leat one. Please press [ Enter ]"
    fi
 
  # 6) Add to array for use during installation
    Counter=1
    for Item in $(cat output.file)                            # Read items from the output.file
    do                                                        # and copy each one to the variable
      Result="$(head -n ${Item} checklist.file | tail -n 1)"  # Read item from countries file
      CountryLong[${Counter}]="$Result"                       # CountryLong is declared in f-vars.sh
      Counter=$((Counter+1))
    done
}

function ConfirmVbox()
{ _Backtitle="https://wiki.archlinux.org/index.php/VirtualBox"

  PrintOne  "It appears that feliz is running in Virtualbox"
  PrintMany  "If it is, feliz can install Virtualbox guest"
  PrintMany  "utilities and make appropriate settings for you"
  Translate "Install Virtualbox guest utilities?"
  Title="$Result"
    
  dialog --backtitle "$_Backtitle" --title " $Title " --yesno "\n$Message" 10 55 2>output.file
  retval=$?

  if [ $retval -eq 0 ]  # Yes
  then
    IsInVbox="VirtualBox"
  else                  # No
    IsInVbox=""
  fi
}

function FinalCheck()
{ # Display all user settings before starting installation
  while true
  do
    print_heading
    FinalOne "These are the settings you have entered."
    FinalOne "Please check them before Feliz begins the installation"
    Echo
    Translate "Zone/subZone will be"
    FinalMany "1) $Result" "$ZONE/$SUBZONE"
    Translate "Locale will be set to"
    FinalMany "2) $Result" "$CountryLocale"
    Translate "Keyboard is"
    FinalMany "3) $Result" "$Countrykbd"
    case ${IsInVbox} in
      "VirtualBox") Translate "virtualbox guest modules"
      FinalMany "4)" "$Result: $_Yes"
      ;;
      *) Translate "virtualbox guest modules"
      FinalMany "4)" "$Result: $_No"
    esac
    if [ -z "$DisplayManager" ]; then
      Translate "No Display Manager selected"
      FinalMany "5)" "$Result"
    else
      Translate "Display Manager"
      FinalMany "5) $Result" " = $DisplayManager"
    fi
    Translate "Root and user settings"
    FinalMany "6) $Result" "..."
    Translate "Hostname"
    FinalMany "      $Result" "= '$HostName'"
    Translate "User Name"
    FinalMany "      $Result" "= '$UserName'"
    Translate "The following extras have been selected"
    FinalMany "7) $Result" "..."
    SaveStartPoint="$EMPTY" # Save cursor start point
    if [ $Scope = "Basic" ]; then
      FinalOne "$_None" ""
    elif [ $DesktopEnvironment ] && [ $DesktopEnvironment = "FelizOB" ]; then
      FinalOne "FelizOB" ""
    elif [ -z "$LuxuriesList" ]; then
      FinalOne "$_None" ""
    else
      Translate="N"
      FinalOne "${LuxuriesList}" ""
      Translate="Y"
    fi
    EMPTY="$SaveStartPoint" # Reset cursor start point
    # 8) Kernel
    Translate "Kernel"
    if [ $Kernel -eq 1 ]; then
      FinalMany "8) $Result" "= 'LTS'"
    else
      FinalMany "8) $Result" "= 'Latest'"
    fi
    # 9) Grub
    Translate "Grub will be installed on"
    FinalMany "9) $Result" "= '$GrubDevice'"
    # 10) Partitions 
    Translate "The following partitions have been selected"
    FinalMany "10) $Result" "..."
    Translate="N"
    FinalOne "${RootPartition} /root ${RootType}"
    FinalMany "${SwapPartition} /swap"
    if [ -n "${AddPartList}" ]; then
      local Counter=0
      for Part in ${AddPartList}                    # Iterate through the list of extra partitions
      do                                            # Display each partition, mountpoint & format type
        if [ $Counter -ge 1 ]; then                 # Only display the first one
          FinalMany "Too many to display all"
          break
        fi
        FinalMany "${Part} ${AddPartMount[${Counter}]} ${AddPartType[${Counter}]}"
        Counter=$((Counter+1))
      done
    fi
    Translate="Y"
    Response=20
    Echo
    FinalOne "Press Enter to install with these settings, or"
    Translate "Enter number for data to change"
    # Prompt user for a number
    local T_COLS=$(tput cols)
    local lov=${#Result}
    stpt=0
    if [ ${lov} -lt ${T_COLS} ]; then
      stpt=$(( (T_COLS - lov) / 2 ))
    elif [ ${lov} -gt ${T_COLS} ]; then
      stpt=0
    else
      stpt=$(( (T_COLS - 10) / 2 ))
    fi
    EMPTY="$(printf '%*s' $stpt)"
    read -p "$EMPTY $1" retval

    Change=$retval
    case $Change in
      1) SetTimeZone
      ;;
      2) setlocale
      ;;
      3) getkeymap
      ;;
      4) ConfirmVbox
      ;;
      5) DisplayManager=""
        ChooseDM
      ;;
      6) ManualSettings
      ;;
      7) PickLuxuries
      ;;
      8) SetKernel
      ;;
      9) if [ $GrubDevice != "EFI" ]; then  # Can't be changed if EFI
          SetGrubDevice
        fi
      ;;
      10) AddPartList=""   # Empty the lists of extra partitions
        AddPartMount=""
        AddPartType=""
        CheckParts         # Restart partitioning
        ChoosePartitions
      ;;
      *) break
    esac
  done
}

function ManualSettings()
{
  while true
  do
    Translate "Hostname"
    Hname="$Result"

    Translate "User Name"
    Uname="$Result"
    
    dialog --backtitle "$_Backtile" --title " $Uname & $Hname " --cancel-label "Done" \
	  --menu "\nChoose an item" 10 40 2 \
      "$Uname"  "$UserName" \
      "$Hname" 	"$HostName"   2> output.file
    retvar=$?
    if [ $retvar -ne 0 ]; then return; fi
    Result="$(cat output.file)"

    case $Result in
      "$Uname") Translate "Enter new username (currently"
          Message="$Result ${UserName})"
          Title="$Uname"
          InputBox 10 30
          if [ $retvar -ne 0 ]; then return; fi
          if [ -z $Result ]; then
           Result="$UserName"
          fi
          UserName=${Result,,}
          UserName=${UserName// }             # Ensure no spaces
          UserName=${UserName%% }
        ;;
      "$Hname") Translate "Enter new hostname (currently"
          Message="$Result ${HostName})"
          Title="$Uname"
          InputBox 10 30
          if [ $retvar -ne 0 ]; then return; fi
          if [ -z $Result ]; then
           Result="$HostName"
          fi
          HostName=${Result,,}
          HostName=${HostName// }             # Ensure no spaces
          HostName=${HostName%% }
        ;;
      *) return 0
    esac
  done
}
