#!/usr/bin/bash -x
#
#           NextzenOS Update Script v1.1
#   Requires: bash, mv, rm, tr, grep, sed, curl/wget, tar, smartmontools, parted, ntfs-3g, net-tools
#
#   This script update your NextZenOS.
#   Usage:
#
#   	$ wget -qO- https://dl.nextzenos.com/setup/nextzenos/${version}/update.sh| bash
#   	  or
#   	$ curl -fsSL  https://dl.nextzenos.com/setup/nextzenos/${version}/update.sh| bash
#
#   In automated environments, you may want to run as root.
#   If using curl, we recommend using the -fsSL flags.
#
#   This only work on  Linux systems. Please
#   open an issue if you notice any bugs.
#

# shellcheck disable=SC2016
echo '
 _   _ _______  _______ __________ _   _ 
| \ | | ____\ \/ /_   _|__  / ____| \ | |
|  \| |  _|  \  /  | |   / /|  _| |  \| |
| |\  | |___ /  \  | |  / /_| |___| |\  |
|_| \_|_____/_/\_\ |_| /____|_____|_| \_|                                   
   --- Power by NextZEN ---
'
export PATH=/usr/sbin:$PATH
set -e

###############################################################################
# GOLBALS                                                                     #
###############################################################################

((EUID)) && sudo_cmd="sudo"

# shellcheck source=/dev/null
source /etc/os-release

# SYSTEM REQUIREMENTS
readonly NEXTZEN_DEPANDS_PACKAGE=('wget' 'curl' 'smartmontools' 'parted' 'ntfs-3g' 'net-tools' 'udevil' 'samba' 'cifs-utils' 'mergerfs' 'unzip')
readonly NEXTZEN_DEPANDS_COMMAND=('wget' 'curl' 'smartctl' 'parted' 'ntfs-3g' 'netstat' 'udevil' 'smbd' 'mount.cifs' 'mount.mergerfs' 'unzip')

LSB_DIST=$( ([ -n "${ID_LIKE}" ] && echo "${ID_LIKE}") || ([ -n "${ID}" ] && echo "${ID}"))
readonly LSB_DIST

UNAME_M="$(uname -m)"
readonly UNAME_M

readonly NEXTZEN_UNINSTALL_URL="https://dl.nextzenos.com/setup/nextzenos/1.0/uninstall.sh"
readonly BACKUP_UNINSTALL_URL="https://raw.githubusercontent.com/KaySar12/NextZen-Script/master/uninstall.sh"
readonly NEXTZEN_UNINSTALL_PATH=/usr/bin/nextzenos-uninstall

# REQUIREMENTS CONF PATH
# Udevil
readonly UDEVIL_CONF_PATH=/etc/udevil/udevil.conf
readonly DEVMON_CONF_PATH=/etc/conf.d/devmon

# COLORS
readonly COLOUR_RESET='\e[0m'
readonly aCOLOUR=(
    '\e[38;5;154m' # green  	| Lines, bullets and separators
    '\e[1m'        # Bold white	| Main descriptions
    '\e[90m'       # Grey		| Credits
    '\e[91m'       # Red		| Update notifications Alert
    '\e[33m'       # Yellow		| Emphasis
)

# CASAOS VARIABLES
TARGET_ARCH=""
TMP_ROOT=/tmp/casaos-installer
GITHUB_DOWNLOAD_DOMAIN="https://github.com/"
NEXTZEN_DOWNLOAD_DOMAIN="https://dl.nextzenos.com/"

# PACKAGE LIST OF CASAOS
NEXTZEN_SERVICES=(
    "casaos-gateway.service"
    "casaos-message-bus.service"
    "casaos-user-service.service"
    "casaos-local-storage.service"
    "casaos-app-management.service"
    "rclone.service"
    "casaos.service" # must be the last one so update from UI can work
)

trap 'onCtrlC' INT
onCtrlC() {
    echo -e "${COLOUR_RESET}"
    exit 1
}

upgradePath="/var/log/casaos"
upgradeFile="/var/log/casaos/upgrade.log"

if [ -f "$upgradePath" ]; then
    ${sudo_cmd} rm "$upgradePath"
fi

if [ ! -d "$upgradePath" ]; then
    ${sudo_cmd} mkdir -p "$upgradePath"
fi

if [ ! -f "$upgradeFile" ]; then
    ${sudo_cmd} touch "$upgradeFile"
fi

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
        echo -e "- OK $2" | ${sudo_cmd} tee -a /var/log/casaos/upgrade.log
    # FAILED
    elif (($1 == 1)); then
        echo -e "- FAILED $2" | ${sudo_cmd} tee -a /var/log/casaos/upgrade.log
        exit 1
    # INFO
    elif (($1 == 2)); then
        echo -e "- INFO $2" | ${sudo_cmd} tee -a /var/log/casaos/upgrade.log
    # NOTICE
    elif (($1 == 3)); then
        echo -e "- NOTICE $2" | ${sudo_cmd} tee -a /var/log/casaos/upgrade.log
    fi
}

Warn() {
    echo -e "${aCOLOUR[3]}$1$COLOUR_RESET"
}

GreyStart() {
    echo -e "${aCOLOUR[2]}\c"
}

ColorReset() {
    echo -e "$COLOUR_RESET\c"
}

# Check file exists
exist_file() {
    if [ -e "$1" ]; then
        return 1
    else
        return 2
    fi
}

###############################################################################
# FUNCTIONS                                                                   #
###############################################################################

# 0 Get download url domain
# To solve the problem that Chinese users cannot access github.
Get_Download_Url_Domain() {
    # Use ipconfig.io/country and https://ifconfig.io/country_code to get the country code
    REGION=$(${sudo_cmd} curl --connect-timeout 2 -s ipconfig.io/country || echo "")
    if [ "${REGION}" = "" ]; then
        REGION=$(${sudo_cmd} curl --connect-timeout 2 -s https://ifconfig.io/country_code || echo "")
    fi
    if [[ "${REGION}" = "China" ]] || [[ "${REGION}" = "CN" ]]; then
        NEXTZEN_DOWNLOAD_DOMAIN="https://casaos.oss-cn-shanghai.aliyuncs.com/"
    fi
}

# 1 Check Arch
Check_Arch() {
    case $UNAME_M in
    *aarch64*)
        TARGET_ARCH="arm64"
        ;;
    *64*)
        TARGET_ARCH="amd64"
        ;;
    *armv7*)
        TARGET_ARCH="arm-7"
        ;;
    *)
        Show 1 "Aborted, unsupported or unknown architecture: $UNAME_M"
        exit 1
        ;;
    esac
    Show 0 "Your hardware architecture is : $UNAME_M"
    NEXTZEN_PACKAGES=(
        "${GITHUB_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-Gateway/releases/download/v0.4.8-alpha2/linux-${TARGET_ARCH}-casaos-gateway-v0.4.8-alpha2.tar.gz"
        "${GITHUB_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-MessageBus/releases/download/v0.4.4-3-alpha2/linux-${TARGET_ARCH}-casaos-message-bus-v0.4.4-3-alpha2.tar.gz"
        "${GITHUB_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-UserService/releases/download/v0.4.8/linux-${TARGET_ARCH}-casaos-user-service-v0.4.8.tar.gz"
        "${GITHUB_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-LocalStorage/releases/download/v0.4.4/linux-${TARGET_ARCH}-casaos-local-storage-v0.4.4.tar.gz"
        "${GITHUB_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-AppManagement/releases/download/v0.4.9-alpha1/linux-${TARGET_ARCH}-casaos-app-management-v0.4.9-alpha1.tar.gz"
        "${NEXTZEN_DOWNLOAD_DOMAIN}setup/nextzenos/1.1/Release/linux-amd64-nextzen-v1.1.0.tar.gz"
        "${GITHUB_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-CLI/releases/download/v0.4.4-3-alpha1/linux-${TARGET_ARCH}-casaos-cli-v0.4.4-3-alpha1.tar.gz"
        "${NEXTZEN_DOWNLOAD_DOMAIN}setup/nextzenos/1.1/Release/linux-all-nextzen-v1.1.0.tar.gz"
        "${GITHUB_DOWNLOAD_DOMAIN}KaySar12/CasaOS-AppStore/releases/download/1.0.0/linux-all-appstore-v1.0.0.tar.gz"
    )
}

# 2 Check Distribution
Check_Distribution() {
    sType=0
    notice=""
    case $LSB_DIST in
    *debian*) ;;
    *ubuntu*) ;;
    *raspbian*) ;;
    *openwrt*)
        Show 1 "Aborted, OpenWrt cannot be installed using this script"
        exit 1
        ;;
    *alpine*)
        Show 1 "Aborted, Alpine installation is not yet supported."
        exit 1
        ;;
    *trisquel*) ;;
    *)
        sType=3
        notice="We have not tested it on this system and it may fail to install."
        ;;
    esac
    Show ${sType} "Your Linux Distribution is : ${LSB_DIST} ${notice}"
    if [[ ${sType} == 0 ]]; then
        select yn in "Yes" "No"; do
            case $yn in
            [yY][eE][sS] | [yY])
                Show 0 "Distribution check has been ignored."
                break
                ;;
            [nN][oO] | [nN])
                Show 1 "Already exited the installation."
                exit 1
                ;;
            esac
        done
    fi
}

# Check Port Use
Check_Port() {
    TCPListeningnum=$(${sudo_cmd} netstat -an | grep ":$1 " | awk '$1 == "tcp" && $NF == "LISTEN" {print $0}' | wc -l)
    UDPListeningnum=$(${sudo_cmd} netstat -an | grep ":$1 " | awk '$1 == "udp" && $NF == "0.0.0.0:*" {print $0}' | wc -l)
    ((Listeningnum = TCPListeningnum + UDPListeningnum))
    if [[ $Listeningnum == 0 ]]; then
        echo "0"
    else
        echo "1"
    fi
}

# Update package

Update_Package_Resource() {
    GreyStart
    if [ -x "$(command -v apk)" ]; then
        ${sudo_cmd} apk update
    elif [ -x "$(command -v apt-get)" ]; then
        ${sudo_cmd} apt-get update --allow-releaseinfo-change
    elif [ -x "$(command -v dnf)" ]; then
        ${sudo_cmd} dnf check-update
    elif [ -x "$(command -v zypper)" ]; then
        ${sudo_cmd} zypper update
    elif [ -x "$(command -v yum)" ]; then
        ${sudo_cmd} yum update
    fi
    ColorReset
}

# Install depends package
Install_Depends() {
    for ((i = 0; i < ${#NEXTZEN_DEPANDS_COMMAND[@]}; i++)); do
        cmd=${NEXTZEN_DEPANDS_COMMAND[i]}
        if [[ ! -x $(command -v "${cmd}") ]]; then
            packagesNeeded=${NEXTZEN_DEPANDS_PACKAGE[i]}
            Show 2 "Install the necessary dependencies: $packagesNeeded "
            GreyStart
            if [ -x "$(command -v apk)" ]; then
                ${sudo_cmd} apk add --no-cache "$packagesNeeded"
            elif [ -x "$(command -v apt-get)" ]; then
                ${sudo_cmd} apt-get -y -q install "$packagesNeeded" --no-upgrade
            elif [ -x "$(command -v dnf)" ]; then
                ${sudo_cmd} dnf install "$packagesNeeded"
            elif [ -x "$(command -v zypper)" ]; then
                ${sudo_cmd} zypper install "$packagesNeeded"
            elif [ -x "$(command -v yum)" ]; then
                ${sudo_cmd} yum install "$packagesNeeded"
            elif [ -x "$(command -v pacman)" ]; then
                ${sudo_cmd} pacman -S "$packagesNeeded"
            elif [ -x "$(command -v paru)" ]; then
                ${sudo_cmd} paru -S "$packagesNeeded"
            else
                Show 1 "Package manager not found. You must manually install: $packagesNeeded"
            fi
            ColorReset
        fi
    done
}
# Function to check if a URL is valid
check_url() {
    curl --silent --head --write-out '%{http_code}\n' --output /dev/null "$1"
}
# Function to uninstall Nextzen
setup_uninstall_nextzen() {
    if ! check_url "$NEXTZEN_UNINSTALL_URL"; then
        echo "Primary URL is not working, trying backup URL..."
        if check_url "$BACKUP_UNINSTALL_URL"; then
            curl -fsSLk "$BACKUP_UNINSTALL_URL" >"${PREFIX}/tmp/nextzenos-uninstall"
        else
            echo "Backup URL is also not working, cannot uninstall Nextzen."
            return 1
        fi
    else
        curl -fsSLk "$NEXTZEN_UNINSTALL_URL" >"${PREFIX}/tmp/nextzenos-uninstall"
    fi
}
Check_Dependency_Installation() {
    for ((i = 0; i < ${#NEXTZEN_DEPANDS_COMMAND[@]}; i++)); do
        cmd=${NEXTZEN_DEPANDS_COMMAND[i]}
        if [[ ! -x $(command -v "${cmd}") ]]; then
            packagesNeeded=${NEXTZEN_DEPANDS_PACKAGE[i]}
            Show 1 "Dependency \e[33m$packagesNeeded \e[0m installation failed, please try again manually!"
            exit 1
        fi
    done
}

#Install Rclone
Install_rclone_from_source() {
    ${sudo_cmd} wget -qO ./install.sh https://rclone.org/install.sh
    if [[ "${REGION}" = "China" ]] || [[ "${REGION}" = "CN" ]]; then
        sed -i 's/downloads.rclone.org/casaos.oss-cn-shanghai.aliyuncs.com/g' ./install.sh
    else
        sed -i 's/downloads.rclone.org/get.casaos.io/g' ./install.sh
    fi
    ${sudo_cmd} chmod +x ./install.sh
    ${sudo_cmd} ./install.sh || {
        Show 1 "Installation failed, please try again."
        ${sudo_cmd} rm -rf install.sh
        exit 1
    }
    ${sudo_cmd} rm -rf install.sh
    Show 0 "Rclone v1.61.1 installed successfully."
}

Install_Rclone() {
    Show 2 "Install the necessary dependencies: Rclone"
    if [[ -x "$(command -v rclone)" ]]; then
        version=$(rclone --version 2>>errors | head -n 1)
        target_version="rclone v1.61.1"
        rclone1="${PREFIX}/usr/share/man/man1/rclone.1.gz"
        if [ "$version" != "$target_version" ]; then
            Show 3 "Will change rclone from $version to $target_version."
            rclone_path=$(command -v rclone)
            ${sudo_cmd} rm -rf "${rclone_path}"
            if [[ -f "$rclone1" ]]; then
                ${sudo_cmd} rm -rf "$rclone1"
            fi
            Install_rclone_from_source
        else
            Show 2 "Target version already installed."
        fi
    else
        Install_rclone_from_source
    fi
    ${sudo_cmd} systemctl enable rclone || Show 3 "Service rclone does not exist."
}

#Configuration Addons
Configuration_Addons() {
    Show 2 "Configuration Addons"
    #Remove old udev rules
    if [[ -f "${PREFIX}/etc/udev/rules.d/11-usb-mount.rules" ]]; then
        ${sudo_cmd} rm -rf "${PREFIX}/etc/udev/rules.d/11-usb-mount.rules"
    fi

    if [[ -f "${PREFIX}/etc/systemd/system/usb-mount@.service" ]]; then
        ${sudo_cmd} rm -rf "${PREFIX}/etc/systemd/system/usb-mount@.service"
    fi

    #Udevil
    if [[ -f "${PREFIX}${UDEVIL_CONF_PATH}" ]]; then

        # Revert previous udevil configuration
        #shellcheck disable=SC2016
        ${sudo_cmd} sed -i 's/allowed_media_dirs = \/DATA, \/DATA\/$USER/allowed_media_dirs = \/media, \/media\/$USER, \/run\/media\/$USER/g' "${PREFIX}${UDEVIL_CONF_PATH}"
        ${sudo_cmd} sed -i '/exfat/s/, nonempty//g' "$PREFIX"${UDEVIL_CONF_PATH}
        ${sudo_cmd} sed -i '/default_options/s/, noexec//g' "$PREFIX"${UDEVIL_CONF_PATH}
        ${sudo_cmd} sed -i '/^ARGS/cARGS="--mount-options nosuid,nodev,noatime --ignore-label EFI"' "$PREFIX"${DEVMON_CONF_PATH}

        # GreyStart
        # Add a devmon user
        USERNAME=devmon
        id ${USERNAME} &>/dev/null || {
            ${sudo_cmd} useradd -M -u 300 ${USERNAME}
            ${sudo_cmd} usermod -L ${USERNAME}
        }

        # Add and start Devmon service
        GreyStart
        ${sudo_cmd} systemctl enable devmon@devmon
        ${sudo_cmd} systemctl start devmon@devmon
        ColorReset
        # ColorReset
    fi
}

# Download And Install NextZenOS
DownloadAndInstallNextzenOS() {

    if [ -z "${BUILD_DIR}" ]; then

        ${sudo_cmd} mkdir -p ${TMP_ROOT} || Show 1 "Failed to create temporary directory"
        TMP_DIR=$(${sudo_cmd} mktemp -d -p ${TMP_ROOT} || Show 1 "Failed to create temporary directory")
        ${sudo_cmd} chmod 755 "${TMP_DIR}"
        ${sudo_cmd} chown "$USER" "${TMP_DIR}"
        pushd "${TMP_DIR}"

        for PACKAGE in "${NEXTZEN_PACKAGES[@]}"; do
            Show 2 "Downloading ${PACKAGE}..."

            ${sudo_cmd} wget -t 3 -q --show-progress -c "${PACKAGE}" || Show 1 "Failed to download package"

        done

        for PACKAGE_FILE in linux-*.tar.gz; do
            Show 2 "Extracting ${PACKAGE_FILE}..."
            ${sudo_cmd} tar zxf "${PACKAGE_FILE}" || Show 1 "Failed to extract package"
        done

        BUILD_DIR=$(realpath -e "${TMP_DIR}"/build || Show 1 "Failed to find build directory")

        popd
    fi

    # for SERVICE in "${NEXTZEN_SERVICES[@]}"; do
    #     Show 2 "Stopping ${SERVICE}..."

    #   systemctl stop "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."

    # done

    MIGRATION_SCRIPT_DIR=$(realpath -e "${BUILD_DIR}"/scripts/migration/script.d || Show 1 "Failed to find migration script directory")

    for MIGRATION_SCRIPT in "${MIGRATION_SCRIPT_DIR}"/*.sh; do
        Show 2 "Running ${MIGRATION_SCRIPT}..."

        ${sudo_cmd} bash "${MIGRATION_SCRIPT}" || Show 1 "Failed to run migration script"

    done

    Show 2 "Installing NextzenOS..."
    SYSROOT_DIR=$(realpath -e "${BUILD_DIR}"/sysroot || Show 1 "Failed to find sysroot directory")

    # Generate manifest for uninstallation
    MANIFEST_FILE=${BUILD_DIR}/sysroot/var/lib/casaos/manifest
    ${sudo_cmd} touch "${MANIFEST_FILE}" || Show 1 "Failed to create manifest file"

    find "${SYSROOT_DIR}" -type f | ${sudo_cmd} cut -c ${#SYSROOT_DIR}- | ${sudo_cmd} cut -c 2- | ${sudo_cmd} tee "${MANIFEST_FILE}" >/dev/null || Show 1 "Failed to create manifest file"

    # Remove old UI files.
    ${sudo_cmd} rm -rf /var/lib/casaos/www/*

    ${sudo_cmd} cp -rf "${SYSROOT_DIR}"/* / >>/dev/null || Show 1 "Failed to install NextzenOS"

    SETUP_SCRIPT_DIR=$(realpath -e "${BUILD_DIR}"/scripts/setup/script.d || Show 1 "Failed to find setup script directory")

    for SETUP_SCRIPT in "${SETUP_SCRIPT_DIR}"/*.sh; do
        Show 2 "Running ${SETUP_SCRIPT}..."
        ${sudo_cmd} bash "${SETUP_SCRIPT}" || Show 1 "Failed to run setup script"
    done

    # Reset Permissions
    UI_EVENTS_REG_SCRIPT=/etc/casaos/start.d/register-ui-events.sh
    if [[ -f ${UI_EVENTS_REG_SCRIPT} ]]; then
        ${sudo_cmd} chmod +x $UI_EVENTS_REG_SCRIPT
    fi

    # Modify app store configuration
    sed -i "/ServerAPI/d" "$PREFIX/etc/casaos/app-management.conf"
    sed -i "/ServerApi/d" "$PREFIX/etc/casaos/app-management.conf"
    if grep -q "IceWhaleTech/_appstore/archive/refs/heads/main.zip" "$PREFIX/etc/casaos/app-management.conf"; then
        sed -i "/https:\/\/github.com\/IceWhaleTech/c\appstore = ${NEXTZEN_DOWNLOAD_DOMAIN}IceWhaleTech/_appstore/archive/refs/heads/main.zip" "$PREFIX/etc/casaos/app-management.conf"
    else
        echo "appstore = ${NEXTZEN_DOWNLOAD_DOMAIN}IceWhaleTech/_appstore/archive/refs/heads/main.zip" >>"$PREFIX/etc/casaos/app-management.conf"
    fi

    #Download Uninstall Script
    if [[ -f ${PREFIX}/tmp/nextzenos-uninstall ]]; then
        ${sudo_cmd} rm -rf "${PREFIX}/tmp/nextzenos-uninstall"
    fi
    # ${sudo_cmd} curl -fsSLk "$NEXTZEN_UNINSTALL_URL" >"${PREFIX}/tmp/nextzenos-uninstall"
    setup_uninstall_nextzen
    ${sudo_cmd} cp -rvf "${PREFIX}/tmp/nextzenos-uninstall" $NEXTZEN_UNINSTALL_PATH || {
        Show 1 "Download uninstall script failed, Please check if your internet connection is working and retry."
        exit 1
    }

    ${sudo_cmd} chmod +x $NEXTZEN_UNINSTALL_PATH
    Install_Rclone

    ## Special markings

    Show 0 "NextzenOS upgrade successfully"
    for SERVICE in "${NEXTZEN_SERVICES[@]}"; do
        Show 2 "restart ${SERVICE}..."

        ${sudo_cmd} systemctl restart "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."

    done

}

###############################################################################
# Main                                                                        #
###############################################################################

#Usage
usage() {
    cat <<-EOF
		Usage: get.sh [options]
		Valid options are:
		    -p <builddir>           Specify build directory
		    -h                      Show this help message and exit
	EOF
    exit "$1"
}

while getopts ":p:h" arg; do
    case "$arg" in
    p)
        BUILD_DIR=$OPTARG
        ;;
    h)
        usage 0
        ;;
    *)
        usage 1
        ;;
    esac
done

# Step 0: Get Download Url Domain
Get_Download_Url_Domain

# Step 1: Check ARCH
Check_Arch

# Step 2: Install Depends
Update_Package_Resource
Install_Depends
Check_Dependency_Installation

# Step 3: Configuration Addon
Configuration_Addons

# Step 4: Download And Install NextzenOS
DownloadAndInstallNextzenOS
