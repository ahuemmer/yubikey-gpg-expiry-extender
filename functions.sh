#!/bin/bash

#Bash colors and formatting...
bold="\e[1m"
green="\e[32m"
red="\e[31m"
grey="\e[2m"
reset="\e[0m"

#Other vars
cmdPreview=false

die() {
  echo -e "${red}$*${reset}" 1>&2; 
  exit 1;
}

ok() {
  echo -e "${green}OK${reset}"
}

confirm() {
  local question=$1
  local additionalInfo=
  shift
  if [[ ${cmdPreview} ]]; then 
    if [[ $# -eq 1 ]]; then
      additionalInfo="(Command: ${grey}$1${reset})"
    elif [[ $# -gt 1 ]]; then
      additionalInfo="\n(Commands:\n"
      for cmd in "$@"; do
        additionalInfo="${additionalInfo}   ${grey}${cmd}${reset}\n"
      done
      additionalInfo="${additionalInfo})"
    fi
    question="${question} ${additionalInfo}"
  fi
  
  echo -en ${question}
  read -p " (Hit Enter to continue or Ctrl+C to abort.)"
  [[ $? -eq 0 ]] || die " Aborting"
}
