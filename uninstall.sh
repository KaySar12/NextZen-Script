#!/bin/bash
#
#           NextZenOS Uninstaller Script

#   Requires: bash, mv, rm, tr, grep, sed
#
#   This script will remove NextZenOS from your system.
#
#   This only work on  Linux systems. Please
#   open an issue if you notice any bugs.
#
set -e
clear

# shellcheck disable=SC2016
echo '
 _   _ _______  _______ __________ _   _ 
| \ | | ____\ \/ /_   _|__  / ____| \ | |
|  \| |  _|  \  /  | |   / /|  _| |  \| |
| |\  | |___ /  \  | |  / /_| |___| |\  |
|_| \_|_____/_/\_\ |_| /____|_____|_| \_|                                   
   --- Power by NextZEN ---
'

###############################################################################
# Golbals                                                                     #
###############################################################################

# Not every platform has or needs sudo (https://termux.com/linux.html)
((EUID)) && sudo_cmd="sudo"

readonly NEXTZEN_SERVICES=(
    "casaos-gateway.service"
    "casaos-message-bus.service"
    "casaos-user-service.service"
    "casaos-local-storage.service"
    "casaos-app-management.service"
    "rclone.service"
    "casaos.service" # must be the last one so update from UI can work
    "devmon@devmon.service"
)

readonly NEXTZEN_PATH=/casaOS
readonly NEXTZEN_EXEC=casaos
readonly NEXTZEN_BIN=/usr/local/bin/casaos
readonly NEXTZEN_SERVICE_USR=/usr/lib/systemd/system/casaos.service
readonly NEXTZEN_SERVICE_LIB=/lib/systemd/system/casaos.service
readonly NEXTZEN_SERVICE_ETC=/etc/systemd/system/casaos.service
readonly NEXTZEN_ADDON1=/etc/udev/rules.d/11-usb-mount.rules
readonly NEXTZEN_ADDON2=/etc/systemd/system/usb-mount@.service
readonly NEXTZEN_UNINSTALL_PATH=/usr/bin/nextzenos-uninstall

# New Casa Files
readonly MANIFEST=/var/lib/casaos/manifest
readonly NEXTZEN_CONF_PATH_OLD=/etc/casaos.conf
readonly NEXTZEN_CONF_PATH=/etc/casaos
readonly NEXTZEN_RUN_PATH=/var/run/casaos
readonly NEXTZEN_USER_FILES=/var/lib/casaos
readonly NEXTZEN_LOGS_PATH=/var/log/casaos
readonly NEXTZEN_HELPER_PATH=/usr/share/casaos

readonly COLOUR_RESET='\e[0m'
readonly aCOLOUR=(
    '\e[38;5;154m' # green  	| Lines, bullets and separators
    '\e[1m'        # Bold white	| Main descriptions
    '\e[90m'       # Grey		| Credits
    '\e[91m'       # Red		| Update notifications Alert
    '\e[33m'       # Yellow		| Emphasis
)

UNINSTALL_ALL_CONTAINER=false
REMOVE_IMAGES="none"
REMOVE_APP_DATA=false

###############################################################################
# Helpers                                                                     #
###############################################################################

#######################################
# Custom printing function
# Globals:
#   None
# Arguments:
#   $1 0:OK   1:FAILED  2:INFO  3:NOTICE
#   message
# Returns:
#   None
#######################################

Show() {
    # OK
    if (($1 == 0)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[0]}  OK  $COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    # FAILED
    elif (($1 == 1)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[3]}FAILED$COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    # INFO
    elif (($1 == 2)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[0]} INFO $COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    # NOTICE
    elif (($1 == 3)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[4]}NOTICE$COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    fi
}

Warn() {
    echo -e "${aCOLOUR[3]}$1$COLOUR_RESET"
}

trap 'onCtrlC' INT
onCtrlC() {
    echo -e "${COLOUR_RESET}"
    exit 1
}

Detecting_NextzenOS() {
    if [[ ! -x "$(command -v ${NEXTZEN_EXEC})" ]]; then
        Show 2 "NextzenOS is not detected, exit the script."
        exit 1
    else
        Show 0 "This script will delete the containers you no longer use, and the NextzenOS configuration files."
    fi
}

Unistall_Container() {
    if [[ ${UNINSTALL_ALL_CONTAINER} == true && "$(${sudo_cmd} docker ps -aq)" != "" ]]; then
        Show 2 "Start deleting containers."
        ${sudo_cmd} docker stop "$(${sudo_cmd} docker ps -aq)" || Show 1 "Failed to stop containers."
        ${sudo_cmd} docker rm "$(${sudo_cmd} docker ps -aq)" || Show 1 "Failed to delete all containers."
    fi
}

Remove_Images() {
    if [[ ${REMOVE_IMAGES} == "all" && "$(${sudo_cmd} docker images -q)" != "" ]]; then
        Show 2 "Start deleting all images."
        ${sudo_cmd} docker rmi "$(${sudo_cmd} docker images -q)" || Show 1 "Failed to delete all images."
    elif [[ ${REMOVE_IMAGES} == "unuse" && "$(${sudo_cmd} docker images -q)" != "" ]]; then
        Show 2 "Start deleting unuse images."
        ${sudo_cmd} docker image prune -af || Show 1 "Failed to delete unuse images."
    fi
}

Uninstall_NextzenOS() {

    for SERVICE in "${NEXTZEN_SERVICES[@]}"; do
        Show 2 "Stopping ${SERVICE}..."
        systemctl stop "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."
        systemctl disable "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."
    done

    # Remove Service file
    if [[ -f ${NEXTZEN_SERVICE_USR} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_SERVICE_USR}
    fi

    if [[ -f ${NEXTZEN_SERVICE_LIB} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_SERVICE_LIB}
    fi

    if [[ -f ${NEXTZEN_SERVICE_ETC} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_SERVICE_ETC}
    fi

    # Old Casa Files
    if [[ -d ${NEXTZEN_PATH} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_PATH} || Show 1 "Failed to delete NextzenOS files."
    fi

    if [[ -f ${NEXTZEN_ADDON1} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_ADDON1}
    fi

    if [[ -f ${NEXTZEN_ADDON2} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_ADDON2}
    fi

    if [[ -f ${NEXTZEN_BIN} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_BIN} || Show 1 "Failed to delete NextzenOS exec file."
    fi

    # New Casa Files

    if [[ -f ${NEXTZEN_CONF_PATH_OLD} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_CONF_PATH_OLD}
    fi

    if [[ -f ${MANIFEST} ]]; then
        ${sudo_cmd} cat ${MANIFEST} | while read -r line; do
            if [[ -f ${line} ]]; then
                ${sudo_cmd} rm -rf "${line}"
            fi
        done
    fi

    if [[ -d ${NEXTZEN_USER_FILES} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_USER_FILES}/[0-9]*
        ${sudo_cmd} rm -rf ${NEXTZEN_USER_FILES}/db
        ${sudo_cmd} rm -rf ${NEXTZEN_USER_FILES}/*.db
    fi

    ${sudo_cmd} rm -rf ${NEXTZEN_USER_FILES}/www
    ${sudo_cmd} rm -rf ${NEXTZEN_USER_FILES}/migration

    if [[ -d ${NEXTZEN_HELPER_PATH} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_HELPER_PATH}
    fi

    if [[ -d ${NEXTZEN_LOGS_PATH} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_LOGS_PATH}
    fi

    if [[ ${REMOVE_APP_DATA} = true ]]; then
        $sudo_cmd rm -fr /DATA/AppData || Show 1 "Failed to delete AppData."
    fi

    if [[ -d ${NEXTZEN_CONF_PATH} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_CONF_PATH}
    fi

    if [[ -d ${NEXTZEN_RUN_PATH} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_RUN_PATH}
    fi

    if [[ -f ${NEXTZEN_UNINSTALL_PATH} ]]; then
        ${sudo_cmd} rm -rf ${NEXTZEN_UNINSTALL_PATH}
    fi

}

# Check user
if [ "$(id -u)" -ne 0 ]; then
    Show 1 "Please execute with a root user, or use ${aCOLOUR[4]}sudo nextzenos-uninstall${COLOUR_RESET}."
    exit 1
fi

#Inputs

Detecting_NextzenOS

while true; do
    echo -n -e "         ${aCOLOUR[4]}Do you want delete all containers? Y/n :${COLOUR_RESET}"
    read -r input
    case $input in
    [yY][eE][sS] | [yY])
        UNINSTALL_ALL_CONTAINER=true
        break
        ;;
    [nN][oO] | [nN])
        UNINSTALL_ALL_CONTAINER=false
        break
        ;;
    *)
        Warn "         Invalid input..."
        ;;
    esac
done </dev/tty

if [[ ${UNINSTALL_ALL_CONTAINER} == true ]]; then
    while true; do
        echo -n -e "         ${aCOLOUR[4]}Do you want delete all images? Y/n :${COLOUR_RESET}"
        read -r input
        case $input in
        [yY][eE][sS] | [yY])
            REMOVE_IMAGES="all"
            break
            ;;
        [nN][oO] | [nN])
            REMOVE_IMAGES="none"
            break
            ;;
        *)
            Warn "         Invalid input..."
            ;;
        esac
    done </dev/tty

    while true; do
        echo -n -e "         ${aCOLOUR[4]}Do you want delete all AppData of NextzenOS? Y/n :${COLOUR_RESET}"
        read -r input
        case $input in
        [yY][eE][sS] | [yY])
            REMOVE_APP_DATA=true
            break
            ;;
        [nN][oO] | [nN])
            REMOVE_APP_DATA=false
            break
            ;;
        *)
            Warn "         Invalid input..."
            ;;
        esac
    done </dev/tty
else
    while true; do
        echo -n -e "         ${aCOLOUR[4]}Do you want to delete all images that are not used by the container? Y/n :${COLOUR_RESET}"
        read -r input
        case $input in
        [yY][eE][sS] | [yY])
            REMOVE_IMAGES="unuse"
            break
            ;;
        [nN][oO] | [nN])
            REMOVE_IMAGES="none"
            break
            ;;
        *)
            Warn "         Invalid input..."
            ;;
        esac
    done </dev/tty
fi

Unistall_Container
Remove_Images
Uninstall_NextzenOS
