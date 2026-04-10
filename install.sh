#! /bin/bash

function isPresent { command -v "$1" &> /dev/null && echo 1; }
source /etc/os-release

clear
echo
echo "Please wait, examining your system and network configuration..."
echo

ARCH=$(uname -m)
PM_COMMAND=pacman
PM_INSTALL="-S --noconfirm"
PM_UPDATE="-Syu --noconfirm"
# WGET_IS_PRESENT="$(isPresent wget)"
WANTED_PACKAGES="git curl unzip nvim most ghostty code discord"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
ENDCOLOR="\e[0m"
ITALICYELLOW="\e[3;33m"

## Check if Script is Run as Root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}You must be a root user to run this script, please run \"sudo su\" then try again.${ENDCOLOR}"
  exit 1
fi

## Checks for wget
# if [[ $WGET_IS_PRESENT -ne 1 ]]; then
#   echo -e "${RED}Wget is not installed and required for this script to run. Please install wget then try again${ENDCOLOR}"
#   exit 1
# fi

function checkUpdates 
{
  echo
  echo -e "${YELLOW}Checking for and installing updates...${ENDCOLOR}"
  echo
  $PM_COMMAND $PM_UPDATE
}

## Installs packages defined in WANTED_PACKAGES list.
function installPackages
{
  echo
  echo -e "${YELLOW}Installing packages ....${ENDCOLOR}"
  echo -e "${YELLOW}Selected Packages: $WANTED_PACKAGES ${ENDCOLOR}"
  echo
  $PM_COMMAND $PM_INSTALL $WANTED_PACKAGES  
}

if [ -n "$*" ]; then
  for ARG in $@
  do
    if ! type "$ARG" &> /dev/null; then
      echo -e "${RED}No such function $ARG ${ENDCOLOR}"
      exit 1
    fi
  done
  
  for ARG_RUN in $@
  do
    $ARG_RUN
  done
  echo
  echo
  echo -e "${GREEN}Done${ENDCOLOR}"
  exit
fi

##############
## ENTRY POINT
##############

echo -e "----------------------------"
echo -e "    ${BLUE}Installation Summary${ENDCOLOR}    "
echo -e "----------------------------"
echo
echo -e "Packages to Install:"
echo -e $WANTED_PACKAGES
echo 
echo -e "${YELLOW}Ready to install, Press ENTER to continue or CTRL+C to cancel.${ENDCOLOR}"
read -r 
echo
echo -e "${YELLOW}Installing please wait ...${ENDCOLOR}"

installPackages

echo -e "${GREEN}Installation complete.${ENDCOLOR}"

exit 0