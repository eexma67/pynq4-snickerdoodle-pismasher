#!/bin/bash

set -x
set -e

target=$1
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

sudo cp $script_dir/pynq_fixes.py $target/root/
sudo cp $script_dir/ssh-host-keys.service $script_dir/pynq-eth-mac.service $target/lib/systemd/system/
sudo cp $script_dir/pynq-eth-mac.sh $target/usr/local/bin/
sudo install -D -m 0644 $script_dir/jupyter-timeout.conf $target/etc/systemd/system/jupyter.service.d/timeout.conf
