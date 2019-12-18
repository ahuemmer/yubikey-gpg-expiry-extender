#!/bin/bash

#Bash colors and formatting...
bold="\e[1m"
green="\e[32m"
red="\e[31m"
reset="\e[0m"


die() {
  echo -e "${red}$*${reset}" 1>&2; 
  exit 1;
}

ok() {
  echo -e "${green}OK${reset}"
}

confirm() {
  read -p "$* (Hit Enter to continue or Ctrl+C to abort.)"
  [[ $? -eq 0 ]] || die " Aborting"
}
