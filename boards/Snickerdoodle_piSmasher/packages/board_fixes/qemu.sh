#!/bin/bash
#
# snickerdoodle/piSmasher image fixes:
#  * patch pynqmetadata and pynq.lib.Wifi for this board (see pynq_fixes.py)
#  * drop the SSH host keys and machine-id generated on the build machine,
#    so each board makes its own on first boot
#  * stable per-board Ethernet MAC addresses (pynq-eth-mac.sh)

set -x
set -e

. /etc/environment
for f in /etc/profile.d/*.sh; do source $f; done

python3 /root/pynq_fixes.py
rm /root/pynq_fixes.py

rm -f /etc/ssh/ssh_host_*
systemctl enable ssh-host-keys.service

# An empty machine-id makes systemd treat the first boot as "first boot" and
# enable units by preset (systemd-networkd, -resolved, ... which fight PYNQ's
# ifupdown). First-boot presets are enable-only, so "disable *" keeps the unit
# state exactly as built here.
mkdir -p /etc/systemd/system-preset
echo "disable *" > /etc/systemd/system-preset/00-pynq.preset
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

systemctl enable pynq-eth-mac.service
