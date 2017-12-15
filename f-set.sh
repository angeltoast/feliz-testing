#!/bin/bash

# The Feliz2 installation scripts for Arch Linux
# Developed by Elizabeth Mills  liz@feliz.one
# With grateful acknowlegements to Helmuthdu, Carl Duff and Dylan Schacht
# Revision date: 14th October 2017

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
# --------------------------  ---------------------------
# Function             Line   Function               Line
# --------------------------  ---------------------------
# checklist_dialog       44   set_hostname            566
# menu_dialog            83   type_of_installation    585
# number_menu_dialog    126   pick_category           624
# localisation_settings 173   choose_extras           681
# desktop_settings      189   display_extras          740
# set_timezone          200   choose_display_manager  798
# set_subzone           252   select_grub_device      822
# america               296   enter_grub_path         850
# america_subgroups     347   select_kernel           874
# setlocale             419   choose_mirrors          898
# edit_locale           443   confirm_virtualbox      973
# get_keymap            439   abandon
# search_keyboards      501   final_check             992
# set_username          547   manual_settings        1122
# -------------------------   ---------------------------

function checklist_dialog() # Calling function prepares checklist.file 
{ # Display a Dialog checklist from checklist.file
  # $1 and $2 are dialog box size
  # $3 is checklist/radiolist switch
  if [ $3 ]; then 
    Type=1  # Radiolist
  else
    Type=2  # Checklist
  fi
  
  # 1) Prepare list for display
    local -a ItemList=()                              # Array will hold entire checklist
    local Items=0
    local Counter=0
    while read -r Item                                  # Read items from the existing list
    do                                                  # and copy each one to the variable
      Counter=$((Counter+1)) 
      Items=$((Items+1))
      ItemList[${Items}]="${Item}"
      Items=$((Items+1))
      ItemList[${Items}]="${Item}" 
      Items=$((Items+1))
      ItemList[${Items}]="off"                          # with added off switch and newline
    done < checklist.file
    Items=$Counter

  # 2) Display the list for user-selection
    case $Type in
    1) dialog --backtitle "$Backtitle" --title " $Title " --no-tags --radiolist \
      "${Message}" $1 $2 ${Items} "${ItemList[@]}" 2>output.file
    ;;
    *) dialog --backtitle "$Backtitle" --title " $Title " --no-tags --separate-output --checklist \
      "${Message}" $1 $2 ${Items} "${ItemList[@]}" 2>output.file
    esac
    retval=$?
    Result=$(cat output.file)                           # Return values to calling function
    rm checklist.file
}

function menu_dialog()
{ # Display a simple menu from $menu_dialogVariable and return selection as $Result
  # $1 and $2 are dialog box size;
  # $3 is optional: can be the text for --cancel-label
    
  if [ $3 ]; then
    cancel="$3"
  else
    cancel="Cancel"
  fi
  
  # Prepare array for display
  declare -a ItemList=()                                    # Array will hold entire list
  Items=0
  for Item in $menu_dialogVariable                                 # Read items from the variable
  do 
    Items=$((Items+1))
    ItemList[${Items}]="${Item}"                            # and copy each one to the array
    Items=$((Items+1))
    ItemList[${Items}]="-"                                  # Second element is required
  done
   
  # Display the list for user-selection
  dialog --backtitle "$Backtitle" --title " $Title " --cancel-label "$cancel" --menu \
      "$Message" \
      $1 $2 ${Items} "${ItemList[@]}" 2>output.file
  retval=$?
  Result=$(cat output.file)
}

function number_menu_dialog()
{ # Similar to menu_dialog. Display a menu from $menu_dialogVariable and return selection as $Result
  # The only difference is that this menu displays numbered items
  # $1 and $2 are dialog box size;
  # $3 is optional: can be the text for --cancel-label
    
  if [ $3 ]; then
    cancel="$3"
  else
    cancel="Cancel"
  fi
  
  # Prepare array for display
  declare -a ItemList=()                                    # Array will hold entire list
  Items=0
  Counter=1
  for Item in $menu_dialogVariable                                 # Read items from the variable
  do 
    Items=$((Items+1))
    ItemList[${Items}]="${Counter}"                         # and copy each one to the array
    Counter=$((Counter+1))
    Items=$((Items+1))
    ItemList[${Items}]="${Item}"                            # Second element is required
  done
   
  # Display the list for user-selection
  dialog --backtitle "$Backtitle" --title " $Title " --cancel-label "$cancel" --menu \
      "$Message" \
      $1 $2 ${Items} "${ItemList[@]}" 2>output.file
  retval=$?
  Result=$(cat output.file)
}

function localisation_settings()              # Locale, keyboard & hostname
{
  localisation=1
  until [ $localisation -eq 0 ]               # Each function must return 0 before next function can be called
  do
    setlocale                                 # CountryLocale eg: en_GB.UTF-8
    if [ $? -ne 0 ]; then continue; fi
    get_keymap                                 # Select keyboard layout eg: uk
    if [ $? -ne 0 ]; then continue; fi
    set_hostname
    localisation=$?
  done
  return $localisation 
}

function desktop_settings()
{
  environment=1
  until [ $environment -eq 0 ]                # Each function must return 0 before next function can be called
  do
    DesktopEnvironment=""
    type_of_installation                      # Basic or Full - use chooses Build, FeliOB or Basic
    environment=$?
  done
  return $environment 
}

function set_timezone()
{
  SUBZONE=""
  while true
  do
    message_first_line "To set the system clock, please first"
    message_subsequent "choose the World Zone of your location"
    timedatectl list-timezones | cut -d'/' -f1 | uniq > zones.file # Ten world zones
  
    declare -a ItemList=()                                    # Array will hold entire menu list
    Items=0
    Counter=1
    while read -r Item                                        # Read items from the zones file
    do                                                        # for display in menu
      translate "$Item"
      Item="$Result"
      Items=$((Items+1))
      ItemList[${Items}]="${Counter}"                         # First column is the item number
      Counter=$((Counter+1)) 
      Items=$((Items+1))
      ItemList[${Items}]="${Item}"                            # Second column is the item
    done < zones.file
  
    dialog --backtitle "$Backtitle" --no-cancel --menu \
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
    set_subzone                          # Call subzone function
    if [ "$SUBZONE" != "" ]; then       # If non-empty, Check "${ZONE}/$SUBZONE" against 
                                        # "timedatectl list-timezones"
      timedatectl list-timezones | grep "${ZONE}/$SUBZONE" > /dev/null
      if [ $? -eq 0 ]; then return; fi    # If "${ZONE}/$SUBZONE" found, return to caller
    fi
  done
}

function set_subzone() # Called from set_timezone
{  # Use ZONE set in set_timezone to prepare list of available subzones
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
    "america") america
      return
    esac
  
    # User-selection of subzone starts here:
    menu_dialogVariable=$(timedatectl list-timezones | grep ${ZONE}/ | cut -d'/' -f2)
  
    translate "Now select your location in"
    if [ $Ocean = 1 ]; then
      Title="$Result the $NativeZONE Ocean"
    else
      Title="  $Result $NativeZONE"
    fi
    Cancel="Back"
    Message=""
    
    menu_dialog  20 40 # Function (arguments are dialog size) displays a menu and return selection as $Result
    if [ $retval -eq 0 ]; then
      SUBZONE="$Result"
    else
      SUBZONE=""
    fi
    return
  done
}

function america() # Called from set_subzone
{ # Necessary because some zones in the americas have a middle zone (eg: america/Argentina/Buenes_Aries)
  
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
  translate "Are you in any of these States?"
  Title="$Result"
  translate "None_of_these"
  Cancel="$Result"
  menu_dialogVariable="$SubList"
  Message=" "
  
  menu_dialog  15 40 # (arguments are dialog size) displays a menu and returns $retval and $Result
  
  if [ $retval -eq 1 ]; then              # "None of These" - check normal subzones
    translate "Now select your location in"
    Title="$Result $NativeZONE"
    menu_dialogVariable=$(timedatectl list-timezones | grep ${ZONE}/ | grep -v 'Argentina\|Indiana\|Kentucky\|North_Dakota' | cut -d'/' -f2)  # Prepare variable
    Cancel="Back"
    Message=" "
    
    menu_dialog  25 50 # Display menu (arguments are dialog size) and return selection as $Result
    if [ $retval -eq 0 ]; then    
      SUBZONE="$Result"
      america_subgroups
    else
      SUBZONE=""
    fi
  else                                    # This is for 2-part zones
    SubGroup=$Result                      # Save subgroup for next function
    ZONE="${ZONE}/$SubGroup"              # Add subgroup to ZONE
    america_subgroups                              # City function for subgroups
  fi
}

function america_subgroups()  # Called from america
{ # Specifically for america, which has subgroups
  # This function receives either 1-part or 2-part ZONE from america
  case $SubGroup in
  "") # No subgroup selected. Here we are working on the second field - cities without a subgroup
      menu_dialogVariable=$(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $2}')
  ;;
  *) # Here we are working on the third field - cities within the chosen subgroup
      menu_dialogVariable=$(timedatectl list-timezones | grep "$ZONE/" | awk 'BEGIN { FS = "/"; OFS = "/" } {print $3}')
   esac
  translate "Please select a city from this list"
  Title="$Result"
  Cancel="Back"
  Message=" "
  
  menu_dialog  25 44 # New function (arguments are dialog size) to display a menu and return $Result
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
    set_timezone # First get a validated ZONE/SUBZONE
    retval=$?
    if [ $retval -ne 0 ]; then continue; fi
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
      Title="Locale"
      message_first_line "Choose the main locale for your system"
      message_subsequent "Choose one or Exit to retry"
      menu_dialogVariable="$choosefrom Edit_locale.gen"                    # Add manual edit option to menu
      Cancel="Exit"
  
      menu_dialog 17 50 # Arguments are dialog size. To display a menu and return $Result & $retval
      Response="$retval"
  
      if [ $Response -eq 1 ]; then                                  # If user chooses <Exit>
        CountryLocale=""                                            # Start again
        continue
      elif [ "$Result" == "Edit_locale.gen" ]; then                 # User chooses manual edit
        edit_locale                                                        # Use Nano to edit locale.gen
        retval=$?
        if [ $retval -eq 0 ]; then  # If Nano was used, get list of uncommented entries
          grep -v '#' /etc/locale.gen | grep ' ' | cut -d' ' -f1 > checklist.file 
          HowMany=$(wc -l checklist.file | cut -d' ' -f1)           # Count them
          case ${HowMany} in
          0) continue                                               # No uncommented lines found, so restart
          ;;
          1) Result="$(cat checklist.file)"                         # One uncommented line found, so set it as locale
          ;;
          *) translate "Choose the main locale for your system"     # If many uncommented lines found
            Message="$Result"
            checklist_dialog 10 40 "--radiolist"                    # Ask user to pick one as main locale
          esac
        else                                                        # Nano was not used
          continue                                                  # Start again
        fi
      fi
    fi
    CountryLocale="$Result"                                         # Save selection eg: en_GB.UTF-8
    CountryCode=${CountryLocale:3:2}                                # eg: GB
  done
  return 0
}

edit_locale() {  # Use Nano to edit locale.gen
  while true
  do
    translate "Start Nano so you can manually uncomment locales?" # New text for line 201 English.lan
    Message="$Result"
    Title=""
    dialog --backtitle "$Backtitle" --title " $Title " --yesno "\n$Message" 6 55 2>output.file
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

function get_keymap() # Display list of locale-appropriate keyboards for user to choose
{ 
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

  Title="$(echo $Result | cut -d' ' -f1)"
  Countrykbd=""
  while [ -z "$Countrykbd" ]
  do
    case $Found in
    0)  # If the search found no matches
      message_first_line "Sorry, no keyboards found based on your location"
      translate "Keyboard is"
      dialog --backtitle "$Backtitle" --msgbox "$Message"
      search_keyboards
    ;;
    1)  # If the search found one match
      message_first_line "Only one keyboard found based on your location"
      message_subsequent "Do you wish to accept this? Select No to search for alternatives"
      
      dialog --backtitle "$Backtitle" --yesno "\n$Message" 10 55 2>output.file
      retval=$?
      Result="$(cat output.file)"
      case ${retval} in
        0) Countrykbd="${Result}"
        ;;
        1) search_keyboards                   # User can enter search criteria to find a keyboard layout 
        ;;
        *) return 1
      esac
      loadkeys ${Countrykbd} 2>> feliz.log
    ;;
    *) # If the search found multiple matches
      Title="Keyboards"
      message_first_line "Select your keyboard, or Exit to try again"
      menu_dialogVariable="$ListKbs"
      message_first_line "Please choose one"
      translate "None_of_these"
      menu_dialog 15 40 "$Result"
      case ${retval} in
        0) Countrykbd="${Result}"
        ;;
        1) search_keyboards                   # User can enter search criteria to find a keyboard layout
        ;;
        *) return 1
      esac
      loadkeys ${Countrykbd} 2>> feliz.log
    esac
  done
  return 0
}

function search_keyboards() # Called by get_keymap when all other options failed 
{ # User can enter search criteria to find a keyboard layout 
  Countrykbd=""
  while [ -z "$Countrykbd" ]
  do
    message_first_line "If you know the code for your keyboard layout, please enter"
    message_subsequent "it now. If not, try entering a two-letter abbreviation"
    message_subsequent "for your country or language and a list will be displayed"
    message_subsequent "eg: 'dvorak' or 'us'"
    
    dialog --backtitle "$Backtitle" --inputbox "$Message" 14 70 2>output.file
    retval=$?
    Result="$(cat output.file)"
    if [ $retval -eq 1 ] || [ $Result = "" ]; then
      Countrykbd=""
      return 1
    fi
    local Term="${Result,,}"
    ListKbs=$(grep ${Term} keymaps.list)
    if [ -n "${ListKbs}" ]; then  # If a match or matches found
      menu_dialogVariable="$ListKbs"
      message_first_line "Please choose one"

      menu_dialog 15 40
      if [ ${retval} -eq 1 ]; then    # Try again
        Countrykbd=""
        continue
      else
        ListKbs=$(grep ${Result} keymaps.list)    # Check if valid
        if [ -n "${ListKbs}" ]; then  # If a match or matches found
          Countrykbd="${Result}"
        else
          translate "No keyboards found containing"
          not_found 8 40 "${Result}\n '$Term'"
          continue
        fi
      fi
      loadkeys ${Countrykbd} 2>> feliz.log
      return 0
    else
      translate "No keyboards found containing"
      not_found 8 40 "${Result}\n '$Term'"
    fi
  done
}

function set_username()
{ 
  message_first_line "Enter a name for the primary user of the new system"
  message_subsequent "If you don't create a username here, a default user"
  message_subsequent "called 'archie' will be set up"
  translate "User Name"
  Title="${Result}"
  
  dialog --backtitle "$Backtitle" --title " $Title " --inputbox "$Message" 12 70 2>output.file
  retval=$?
  Result="$(cat output.file)"

  if [ -z $Result ]; then
    user_name="archie"
  else
    user_name=${Result,,}
  fi
}

function set_hostname()
{
  message_first_line "A hostname is needed. This will be a unique name to identify"
  message_subsequent "your device on a network. If you do not enter one, the"
  message_subsequent "default hostname of 'arch-linux' will be used"
  translate "Enter a hostname for your computer"
  Title="${Result}: "

  dialog --backtitle "$Backtitle" --title " $Title " --inputbox "$Message" 12 70 2>output.file
  retval=$?
  Result="$(cat output.file)"

  if [ -z $Result ]; then
    HostName="arch-linux"
  else
    HostName=${Result,,}
  fi
}

function type_of_installation() # User chooses between FelizOB, self-build or basic
{ 
  message_first_line "Feliz now offers you a choice. You can ..."
  translate "Build your own system, by picking the"
  Message="${Message}\n\n1) ${Result}"
  translate "software you wish to install"
  Message="${Message}\n${Result}\n\n               ... ${_or} ...\n"
  translate "You can choose the new FelizOB desktop, a"
  Message="${Message}\n2) ${Result}"
  translate "complete lightweight system built on Openbox"
  Message="${Message}\n${Result}\n\n               ... ${_or} ...\n"
  translate "Just install a basic Arch Linux"
  Message="${Message}\n3) ${Result}\n"
  
  translate "Build_My_Own"
  BMO="$Result"
  translate "FelizOB_desktop"
  FOB="$Result"
  translate "Basic_Arch_Linux"
  BAL="$Result"
  
  dialog --backtitle "$Backtitle" --title " type_of_installation " --menu "$Message" \
      22 50 3 \
      1 "$BMO" \
      2 "$FOB" \
      3  "$BAL" 2>output.file
  retval=$?
  Result=$(cat output.file)

  case $Result in
    1) pick_category
    ;;
    2) DesktopEnvironment="FelizOB"
      Scope="Full"
    ;;
    *) Scope="Basic"
  esac
}

function pick_category()  # menu_dialog of categories of selected items from the Arch repos
{ translate "Added so far"
  AddedSoFar="$Result"
  # translate the categories
  TransCatList=""
  for category in $CategoriesList
  do
    translate "$category"
    TransCatList="$TransCatList $Result"
  done
  # Display categories, adding more items until user exits by <Done>
  LuxuriesList=""
  while true
  do
    # Prepare information messages
    if [ -z "$LuxuriesList" ]; then
      message_first_line "Now you have the option to add extras, such as a web browser"
      Message="\n${Message}"
      message_subsequent "desktop environment, etc, from the following categories"
    fi
    # Display categories as numbered list
    Title="Arch Linux"
    menu_dialogVariable="${TransCatList}"
    number_menu_dialog  20 70 "Done"              # Displays numbered menu of categories
    # Process exit variables
    if [ $retval -ne 0 ]; then
      if [ -n "${LuxuriesList}" ]; then
        Scope="Full"
      else
        Scope="Basic"
      fi
      break
    else
      Category=$Result
      choose_extras                        # Function to add items to LuxuriesList
      if [ -n "$LuxuriesList" ]; then
        translate "Added so far"
        Message="$Result: ${LuxuriesList}\n"
        message_subsequent "You can now choose from any of the other lists"
      fi
    fi
  done

  for i in $LuxuriesList                              # Run through list
  do
    Check="$(echo $Desktops | grep $i)"               # Test if a DE
    if [ -n "$Check" ]; then                          # This is just to set a primary DE variable
      DesktopEnvironment="$i"                         # Add as DE
      if [ "$DesktopEnvironment" = "Gnome" ]; then    # Gnome installs own DM, so break after adding
        DisplayManager=""
        break
      fi
    fi
  done

}

function choose_extras() # Called by pick_category after a category has been chosen.
{ # Prepares to call 'display_extras' function with copy data
  translate "Added so far"
  Message="$Result: ${LuxuriesList}\n"
  message_subsequent "You can add more items, or select items to delete"
  Title="${Categories[$Category]}" # $Category is number of item in CategoriesList
  
  local Counter=1
  MaxLen=0
  case $Category in
   1) # Create a copy of the list of items in the category
      Copycat="${Accessories}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongAccs"
    ;;
   2) # Create a copy of the list of items in the category
      Copycat="${Desktops}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongDesk"
    ;;
   3) # Create a copy of the list of items in the category
      Copycat="${Graphical}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongGraph"
    ;;
   4) # Create a copy of the list of items in the category
      Copycat="${Internet}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongNet"
     ;;
   5) # Create a copy of the list of items in the category
      Copycat="${Multimedia}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongMulti"
    ;;
   6) # Create a copy of the list of items in the category
      Copycat="${Office}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongOffice"
    ;;
   7) # Create a copy of the list of items in the category
      Copycat="${Programming}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongProg"
    ;;
   8) # Create a copy of the list of items in the category
      Copycat="${WindowManagers}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongWMs"
    ;;
   9) # Create a copy of the list of items in the category
      Copycat="${Taskbars}"
      # Pass the name of the relevant array to the translate_category function
      display_extras "LongBars"
    ;;
    *) return
  esac
}

function display_extras() # Called by choose_extras
{ # translates descriptions of items in the selected category
  # Then displays them for user to select multiple items
  # Note1: The name of the array to be processed has been passed as $1
  # Note2: A copy of the list of items in the category has been created
  # by the calling function as 'Copycat'
  
  # Get the array passed by name ...
    local name=$1[@]
    local CopyArray=("${!name}")    # eg: LongAccs or LongDesk, etc
  # Prepare temporary array for translated item descriptions
    declare -a TempArray=()
  # translate all elements
    type_of_installationCounter=0
    for Option in "${CopyArray[@]}"
    do
      (( type_of_installationCounter+=1 ))
      translate "$Option"
      CopyArray[${type_of_installationCounter}]="$Result"    # Replace element with translation
    done
    # Then build the temporary array for the checklist dialog
    local Counter=0
    local CopyCounter=0
    for i in ${Copycat}
    do
      (( Counter+=1 ))
      TempArray[${Counter}]="$i"
      (( Counter+=1 ))
      (( CopyCounter+=1 ))
      TempArray[${Counter}]="${CopyArray[${CopyCounter}]}"
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
      #  LuxuriesList=$(echo "$LuxuriesList" | sed "s/$i//")
        LuxuriesList="${LuxuriesList//${i} }"
      done
    fi
    # Display the contents of the temporary array in a Dialog menu
    Items=$(( Counter/3 ))
    dialog --backtitle "$Backtitle" --title " $Title " --checklist \
      "$Message" 20 79 $Items "${TempArray[@]}" 2>output.file
    retval=$?
    Result=$(cat output.file)
    # Add selected items to LuxuriesList
    LuxuriesList="$LuxuriesList $Result"
    LuxuriesList=$( echo $LuxuriesList | sed "s/^ *//")        # Remove any leading spaces caused by deletions
}

function choose_display_manager()
{ # Choose a display manager
  Counter=0
  translate "Display Manager"
  Title="$Result"
  message_first_line "A display manager provides a graphical login screen"
  message_subsequent "If in doubt, choose"
  Message="$Message LightDM"
  message_subsequent "If you do not install a display manager, you will have"
  message_subsequent "to launch your desktop environment manually"
  
  dialog --backtitle "$Backtitle" --title " $Title " --menu "\n$Message" 20 60 6 \
    "GDM" "-" \
    "LightDM" "-" \
    "LXDM" "-" \
    "sddm" "-" \
    "SLIM" "-" \
    "XDM" "-" 2> output.file
  retval=$?
  if [ $retval -ne 0 ]; then return; fi
  DisplayManager="$(cat output.file)"
  DisplayManager="${DisplayManager,,}"
}

function select_grub_device()
{ # Set path for grub to be installed
  GrubDevice=""
  while [ -z $GrubDevice ]
  do
    DevicesList="$(lsblk -d | awk '{print "/dev/" $1}' | grep 'sd\|hd\|vd')"  # Preceed field 1 with '/dev/'
    # Add an option to enter grub device manually
    translate "Enter_Manually"
    Enter_Manually="$Result"
    menu_dialogVariable="$DevicesList $Result"
    Title="Grub"
    GrubDevice=""
    local Counter=0
    message_first_line "Select the device where Grub is to be installed"
    message_subsequent "Note that if you do not select a device, Grub"
    message_subsequent "will not be installed, and you will have to make"
    message_subsequent "alternative arrangements for booting your new system"

    menu_dialog  20 60 # (arguments are dialog size) displays a menu and returns $retval and $Result
    if [ $Result = "$Enter_Manually" ]; then				# Call function to type in a path
      enter_grub_path
      GrubDevice="$Result"
    else
      GrubDevice="$Result"
    fi
  done
}

function enter_grub_path() # Manual input
{ GrubDevice=""
  while [ -z "$GrubDevice" ]
  do
    message_first_line "You have chosen to manually enter the path for Grub"
    message_subsequent "This should be in the form /dev/sdx or similar"
    message_subsequent "Only enter a device, do not include a partition number"
    message_subsequent "If in doubt, consult https://wiki.archlinux.org/index.php/GRUB"
    
    dialog_inputbox 15 60    # Text input dialog
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

function select_kernel()
{
  Kernel="0"
  until [ "$Kernel" != "0" ]
  do
    translate " Choose your kernel "
    Title="$Result"
    translate "The Long-Term-Support kernel offers stabilty"
    LTS="$Result"
    translate "The Latest kernel has all the new features"
    Latest="$Result"
    translate "If in doubt, choose"
    Default="${Result} LTS"
  
    dialog --backtitle "$Backtitle" --title "$Title" --no-tags --radiolist "\n  $Default" 10 70 2 \
      "1" "$LTS" ON \
      "2" "$Latest" off 2>output.file
    if [ $? -ne 0 ]; then Result="1"; fi
    Result=$(cat output.file)
    Kernel=${Result} # Set the Kernel variable (1 = LTS; 2 = Latest)
  done
  return 0
}

function choose_mirrors() # User selects one or more countries with Arch Linux mirrors
{
  Country=""
  while [ -z "$Country" ]
  do
    # 1) Prepare files of official Arch Linux mirrors

      # Download latest list of Arch Mirrors to temporary file
      curl -s https://www.archlinux.org/mirrorlist/all/http/ > archmirrors.list
      if [ $? -ne 0 ]; then
        message_first_line "Unable to fetch list of mirrors from Arch Linux"
        message_subsequent "Using the list supplied with the Arch iso"
        dialog --backtitle "$Backtitle" --msgbox "\n${Message}\n" 8 75
        cp /etc/pacman.d/mirrorlist > archmirrors.list
      fi
      # Get line number of first country
      FirstLine=$(grep -n "Australia" archmirrors.list | head -n 1 | cut -d':' -f1)
      # Remove text prior to FirstLine and save in new file
      tail -n +${FirstLine} archmirrors.list > allmirrors.list
      rm archmirrors.list
      # Create list of countries from allmirrors.list, using '##' to identify
      #                        then removing the '##' and leading spaces
      #                                       and finally save to new file for reference by dialog
      grep "## " allmirrors.list | tr -d "##" | sed "s/^[ \t]*//" > checklist.file
      rm allmirrors.list
      
    # 2) Display instructions and user selects from list of countries
      Title="Mirrors"
      message_first_line "Next we will select mirrors for downloading your system."
      message_subsequent "You will be able to choose from a list of countries which"
      message_subsequent "have Arch Linux mirrors."
      
      dialog --backtitle "$Backtitle" --msgbox "\n${Message}\n" 10 75
  
      message_first_line "Please choose a country"

      checklist_dialog 25 70 "radio"
      if [ "$Result" = "" ]
      then
        Result="Server = http://mirrors.evowise.com/archlinux/$repo/os/$arch"
      fi

      Country="$Result"
      if [ "$Country" = "" ]; then
        translate "Please select one."
        Title="$Result"
      else   
        # Add to array for use during installation
        Counter=0
        for Item in $(cat output.file)                            # Read items from the output.file
        do                                                        # and copy each one to the variable
          Counter=$((Counter+1))
          CountryLong[${Counter}]="$Item"                         # CountryLong is declared in f-vars.sh
        done
        if [ $Counter -lt 1 ]; then Country=""; fi
      fi
  done
}

function confirm_virtualbox()
{ 
  message_first_line  "It appears that feliz is running in Virtualbox"
  message_subsequent  "If it is, feliz can install Virtualbox guest"
  message_subsequent  "utilities and make appropriate settings for you"
  translate "Install Virtualbox guest utilities?"
  Title="$Result"
    
  dialog --backtitle "$Backtitle" --title " $Title " --yesno "\n$Message" 10 55 2>output.file
  retval=$?

  if [ $retval -eq 0 ]  # Yes
  then
    IsInVbox="VirtualBox"
  else                  # No
    IsInVbox=""
  fi
}

function abandon()
{
  message_first_line "Feliz cannot continue the installation without"
  Message="$Message $1"
  message_subsequent "Are you sure you want to cancel it?"
  dialog --backtitle "$Backtitle" --yesno "$Message" 10 60 2> output.file
  retval=$?
  Result="$(cat output.file)"
}

function final_check()
{ # Display all user settings before starting installation
  while true
  do
    clear
    echo
    print_first_line "These are the settings you have entered."
    print_first_line "Please check them before Feliz begins the installation"
    echo
    translate "Zone/subZone will be"
    print_subsequent "1) $Result" "$ZONE/$SUBZONE"
    translate "Locale will be set to"
    print_subsequent "2) $Result" "$CountryLocale"
    translate "Keyboard is"
    print_subsequent "3) $Result" "$Countrykbd"
    case ${IsInVbox} in
      "VirtualBox") translate "virtualbox guest modules"
      print_subsequent "4)" "$Result: $_Yes"
      ;;
      *) translate "virtualbox guest modules"
      print_subsequent "4)" "$Result: $_No"
    esac
    if [ -z "$DisplayManager" ]; then
      translate "No Display Manager selected"
      print_subsequent "5)" "$Result"
    else
      translate "Display Manager"
      print_subsequent "5) $Result" " = $DisplayManager"
    fi
    translate "Root and user settings"
    print_subsequent "6) $Result" "..."
    translate "Hostname"
    print_subsequent "      $Result" "= '$HostName'"
    translate "User Name"
    print_subsequent "      $Result" "= '$user_name'"
    translate "The following extras have been selected"
    print_subsequent "7) $Result" "..."
    SaveStartPoint="$EMPTY" # Save cursor start point
    if [ $Scope = "Basic" ]; then
      print_first_line "$_None" ""
    elif [ $DesktopEnvironment ] && [ $DesktopEnvironment = "FelizOB" ]; then
      print_first_line "FelizOB" ""
    elif [ -z "$LuxuriesList" ]; then
      print_first_line "$_None" ""
    else
      translate="N"
      print_first_line "${LuxuriesList}" ""
      translate="Y"
    fi
    EMPTY="$SaveStartPoint" # Reset cursor start point
    # 8) Kernel
    translate "Kernel"
    if [ $Kernel -eq 1 ]; then
      print_subsequent "8) $Result" "= 'LTS'"
    else
      print_subsequent "8) $Result" "= 'Latest'"
    fi
    # 9) Grub
    translate "Grub will be installed on"
    print_subsequent "9) $Result" "= '$GrubDevice'"
    # 10) Partitions 
    translate "The following partitions have been selected"
    print_subsequent "10) $Result" "..."
    translate="N"
    print_first_line "${RootPartition} /root ${RootType}"
    print_subsequent "${SwapPartition} /swap"
    if [ -n "${AddPartList}" ]; then
      local Counter=0
      for Part in ${AddPartList}                    # Iterate through the list of extra partitions
      do                                            # Display each partition, mountpoint & format type
        if [ $Counter -ge 1 ]; then                 # Only display the first one
          print_subsequent "Too many to display all"
          break
        fi
        print_subsequent "${Part} ${AddPartMount[${Counter}]} ${AddPartType[${Counter}]}"
        Counter=$((Counter+1))
      done
    fi
    translate="Y"
    Response=20
    print_first_line "Press Enter to install with these settings, or"
    translate "Enter number for data to change: "
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
    read -p "$EMPTY $Result" retval

    Change=$retval
    case $Change in
      1) set_timezone
      ;;
      2) setlocale
      ;;
      3) get_keymap
      ;;
      4) confirm_virtualbox
      ;;
      5) DisplayManager=""
        choose_display_manager
      ;;
      6) manual_settings
      ;;
      7) pick_category
      ;;
      8) select_kernel
      ;;
      9) if [ $GrubDevice != "EFI" ]; then  # Can't be changed if EFI
          select_grub_device
        fi
      ;;
      10) AddPartList=""   # Empty the lists of extra partitions
        AddPartMount=""
        AddPartType=""
        check_parts         # finish partitioning
        allocate_partitions
      ;;
      *) break
    esac
  done
}

function manual_settings()
{
  while true
  do
    translate "Hostname"
    Hname="$Result"

    translate "User Name"
    Uname="$Result"
    
    dialog --backtitle "$Backtitle" --title " $Uname & $Hname " --cancel-label "Done" \
	  --menu "\nChoose an item" 10 40 2 \
      "$Uname"  "$user_name" \
      "$Hname" 	"$HostName"   2> output.file
    retvar=$?
    if [ $retvar -ne 0 ]; then return; fi
    Result="$(cat output.file)"

    case $Result in
      "$Uname") translate "Enter new username (currently"
          Message="$Result ${user_name})"
          Title="$Uname"
          dialog_inputbox 10 30
          if [ $retvar -ne 0 ]; then return; fi
          if [ -z $Result ]; then
           Result="$user_name"
          fi
          user_name=${Result,,}
          user_name=${user_name// }             # Ensure no spaces
          user_name=${user_name%% }
        ;;
      "$Hname") translate "Enter new hostname (currently"
          Message="$Result ${HostName})"
          Title="$Uname"
          dialog_inputbox 10 30
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
