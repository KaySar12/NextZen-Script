#! /bin/bash

###############################################################################
# GOLBALS                                                                     #
###############################################################################
echo '
 _   _ _______  _______ __________ _   _ 
| \ | | ____\ \/ /_   _|__  / ____| \ | |
|  \| |  _|  \  /  | |   / /|  _| |  \| |
| |\  | |___ /  \  | |  / /_| |___| |\  |
|_| \_|_____/_/\_\ |_| /____|_____|_| \_|                                   
   --- Power by NextZEN ---
'
((EUID)) && sudo_cmd="sudo"
SERVICES=(
  "casaos-gateway.service"
  "casaos-message-bus.service"
  "casaos-user-service.service"
  "casaos-local-storage.service"
  "casaos-app-management.service"
  "rclone.service"
  "casaos.service" # must be the last one so update from UI can work
)
# COLORS
readonly COLOUR_RESET='\e[0m'
readonly aCOLOUR=(
  '\e[38;5;154m' # green  	| Lines, bullets and separators
  '\e[1m'        # Bold white	| Main descriptions
  '\e[90m'       # Grey		| Credits
  '\e[91m'       # Red		| Update notifications Alert
  '\e[33m'       # Yellow		| Emphasis
)

readonly GREEN_LINE=" ${aCOLOUR[0]}─────────────────────────────────────────────────────$COLOUR_RESET"
readonly GREEN_BULLET=" ${aCOLOUR[0]}-$COLOUR_RESET"
readonly GREEN_SEPARATOR="${aCOLOUR[0]}:$COLOUR_RESET"
NEXTZEN_DOWNLOAD_DOMAIN="https://dl.nextzenos.com"
CASAOS_DOWNLOAD_DOMAIN="https://get.casaos.io"
Show() {
  # OK
  if (($1 == 0)); then
    echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[0]}  OK  $COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
  # FAILED
  elif (($1 == 1)); then
    echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[3]}FAILED$COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    exit 1
  # INFO
  elif (($1 == 2)); then
    echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[0]} INFO $COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
  # NOTICE
  elif (($1 == 3)); then
    echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[4]}NOTICE$COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
  fi
}
stop() {
  for SERVICE in "${SERVICES[@]}"; do
    Show 2 "Stopping ${SERVICE}..."

    ${sudo_cmd} systemctl stop "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."

  done
  main
}

restart() {
  for SERVICE in "${SERVICES[@]}"; do
    Show 2 "restart ${SERVICE}..."

    ${sudo_cmd} systemctl restart "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."

  done
  main
}
status() {
  ${sudo_cmd} systemctl --type service --all | grep casaos
  main
}
stopOne() {
  echo service name:
  read -r service </dev/tty
  ${sudo_cmd} systemctl stop "$service" || Show 3 "Service $service does not exist."
  main
}
startOne() {
  echo service name:
  read -r service </dev/tty
  ${sudo_cmd} systemctl restart "$service" || Show 3 "Service $service does not exist."
  main
}
listen() {
  echo Port Listen:
  read -r port </dev/tty
  ${sudo_cmd} $HOME/go/bin/dlv dap --listen=: $port --only-same-user=false || Show 3 "Error Port"
  main
}
reload() {
  ${sudo_cmd} systemctl daemon-reload
  ${sudo_cmd} systemctl reset-failed
  main
}
install() {
  echo "Enter Version:"
  read -r version </dev/tty

  if curl -fsSL "${NEXTZEN_DOWNLOAD_DOMAIN}/setup/nextzenos/$version/install.sh" >/dev/null 2>&1; then
    echo "valid version. Installing nextzenos $version"
    curl -fsSL "${NEXTZEN_DOWNLOAD_DOMAIN}/setup/nextzenos/$version/install.sh" | ${sudo_cmd} bash
  else
    echo "Invalid version. Please enter a valid version number."
  fi
}
installCasa() {
  echo "Enter Version:"
  read -r version </dev/tty
  if curl -fsSL "${CASAOS_DOWNLOAD_DOMAIN}/install/$version" >/dev/null 2>&1; then
    echo "valid version. Installing casaos v$version..."
    curl -fsSL "${CASAOS_DOWNLOAD_DOMAIN}/install/$version" | ${sudo_cmd} bash
  else
    echo "Invalid version. Please enter a valid version number."
  fi
}
update() {
  echo "Enter Version:"
  read -r version </dev/tty
  if curl -fsSL "${NEXTZEN_DOWNLOAD_DOMAIN}/setup/nextzenos/$version/update.sh" >/dev/null 2>&1; then
    echo "valid version. Updating nextzen $version"
    curl -fsSL "${NEXTZEN_DOWNLOAD_DOMAIN}/setup/nextzenos/$version/update.sh" | ${sudo_cmd} bash
  else
    echo "Invalid version. Please enter a valid version number."
  fi
}

updateCasa() {
  echo "Enter Version:"
  read -r version </dev/tty

  if curl -fsSL "${CASAOS_DOWNLOAD_DOMAIN}/update/$version" >/dev/null 2>&1; then
    echo "valid version. Updating casaos v$version"
    curl -fsSL "${CASAOS_DOWNLOAD_DOMAIN}/update/$version" | ${sudo_cmd} bash
  else
    echo "Invalid version. Please enter a valid version number."
  fi
}
uninstall() {
  ${sudo_cmd} nextzenos-uninstall
  reload
}
uninstallCasa() {
  ${sudo_cmd} casaos-uninstall
  reload
}
log() {
  #   sudo journalctl -xef -u ${service name}
  echo "Enter Services name:"
  read -r service </dev/tty
  ${sudo_cmd} journalctl -xef -u "$service"
}
main() {
  echo 'Options:
      install - install nextzenOS
      uninstall - uninstall nextzenOS
      update - Update nextzenOS
      installCasa - install casaOS
      uninstallCasa - uninstall casaOS
      updateCasa - update CasaOS
      1.stop all service
      2.stop a service
      3.start a service
      4.restart all service
      5.services status
      6.listen to port
      7.reload system
      8.service logs
      '
  echo "choose:"
  read -r choice </dev/tty

  case $choice in
  "install")
    echo "Execute install script"
    install
    ;;
  "uninstall")
    echo "Execute uninstall script"
    uninstall
    ;;
  "update")
    echo "Execute update script"
    update
    ;;
  "installCasa")
    echo "Execute CasaOS install script"
    installCasa
    ;;
  "uninstallCasa")
    echo "Execute CasaOS uninstall script"
    uninstallCasa
    ;;
  "updateCasa")
    echo "Execute CasaOS update script"
    updateCasa
    ;;
  "1")
    echo "Progressing"
    stop
    echo "All CasaOS Services Stop"
    ;;
  "2")
    echo "Progressing"
    stopOne
    echo "Service Stopped"
    ;;
  "3")
    echo "Progressing"
    startOne
    echo "Service Started"
    ;;
  "4")
    echo "restarting ..."
    restart
    echo "All CasaOS Services restarted"
    ;;
  "5")
    status
    ;;
  "6")
    echo "Listening..."
    listen
    ;;
  "7")
    echo "Reloading..."
    reload
    ;;
  "8")
    log
    ;;
  *)
    exit 1
    ;;
  esac
}
main
