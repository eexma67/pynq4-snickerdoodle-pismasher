#!/bin/bash
# Give eth0/eth1 stable, board-unique MAC addresses. The GEMs have no MAC
# EEPROM, so u-boot and the kernel otherwise pick a random one every boot.
# Derived from /etc/machine-id; locally administered, unicast.
#
# Also enlarge the RX ring: at gigabit line rate the Cortex-A9 cannot refill
# the default 512 descriptors fast enough (rx_resource_errors / overruns).
id=$(cat /etc/machine-id)
for i in eth0 eth1; do
    [ -e /sys/class/net/$i ] || continue
    h=$(echo -n "${id}${i}" | sha256sum)
    ip link set dev $i address "02:${h:0:2}:${h:2:2}:${h:4:2}:${h:6:2}:${h:8:2}"
    ethtool -G $i rx 2048 || true
done
