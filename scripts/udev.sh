#!/bin/bash

if [ -z "$SCRIPT" ]; then 
    /usr/bin/script /var/log/prind-udev.log /bin/bash -c "$0 $*"
    exit 0
fi

action="${1}"
shift

udev_script="$(readlink -f "${BASH_SOURCE}")"
prind_location="$(dirname "$(dirname "${udev_script}")")"

prind-compose() {
  docker-compose --file "${prind_location}/docker-compose.yaml"
}

klipper-exec() {
  prind-compose exec --user root --no-TTY klipper "$@"
}

read -r -d '' rules <<EOF
SUBSYSTEM!="tty", GOTO="end_prind"
ACTION=="add", SUBSYSTEM=="tty", KERNEL=="ttyUSB[0-9]|ttyACM[0-9]", RUN+="/bin/bash ${udev_script} add \$name \$major \$minor"
ACTION=="change", SUBSYSTEM=="tty", KERNEL=="ttyUSB[0-9]|ttyACM[0-9]", RUN+="/bin/bash ${udev_script} change \$name \$major \$minor"
ACTION=="remove", SUBSYSTEM=="tty", KERNEL=="ttyUSB[0-9]|ttyACM[0-9]", RUN+="/bin/bash ${udev_script} remove \$name"
LABEL="end_prind"
EOF

echo "Received $action $@" >> /var/log/prind-udev.log

if [ "${action}" = 'init' ]; then
  # usage: udev.sh init
  echo "${rules}" > /etc/udev/rules.d/99-prind.rules
  udevadm control --reload-rules
fi

if [ "${action}" = 'add' ] || [ "${action}" = 'change' ]; then
  # usage: udev.sh add|change {path} {major} {minor}
  # example: udev.sh add ttyUSB0 188 0
  name="/dev/${1}"
  major="${2}"
  minor="${3}"
  prind-compose restart klipper
  klipper-exec sh -c "test -c "${name}" && rm -f "${name}""
  klipper-exec sh -c "mknod --mode 660 "${name}" c "${major}" "${minor}" && chown root:dialout "${name}""

  find -L /dev/serial/ -samefile "${name}" -print0 | while read -d $'\0' link_name; do
    echo "found ${link_name}"
    link_dir="$(dirname "${link_name}")"
    klipper-exec sh -c "mkdir -p "${link_dir}" ; ln -sf "${name}" "${link_name}"" || echo "Could not create link at ${link_name}"
  done
fi

if [ "${action}" = 'remove' ]; then
  # usage: udev.sh remove {path}
  # example: udev.sh remove ttyUSB0
  name="/dev/${1}"
  klipper-exec sh -c "find -L /dev/serial/ -samefile "${name}" -exec rm -f '{}' \; ; rm -f ${name}"
fi

# > udevadm monitor --kernel --property --subsystem-match=tty
# monitor will print the received events for:
# KERNEL - the kernel uevent

# KERNEL[72054.815242] remove   /devices/platform/soc/5200400.usb/usb6/6-1/6-1:1.0/ttyUSB1/tty/ttyUSB1 (tty)
# ACTION=remove
# DEVPATH=/devices/platform/soc/5200400.usb/usb6/6-1/6-1:1.0/ttyUSB1/tty/ttyUSB1
# SUBSYSTEM=tty
# DEVNAME=/dev/ttyUSB1
# SEQNUM=4004
# MAJOR=188
# MINOR=1

# KERNEL[72061.271635] add      /devices/platform/soc/5200400.usb/usb6/6-1/6-1:1.0/ttyUSB1/tty/ttyUSB1 (tty)
# ACTION=add
# DEVPATH=/devices/platform/soc/5200400.usb/usb6/6-1/6-1:1.0/ttyUSB1/tty/ttyUSB1
# SUBSYSTEM=tty
# DEVNAME=/dev/ttyUSB1
# SEQNUM=4014
# MAJOR=188
# MINOR=1
