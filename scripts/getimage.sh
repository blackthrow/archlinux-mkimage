#!/bin/sh

progress () {
    echo ">>> $1"
}

error () {
	echo "$1" >&2
	exit 1
}

# url, output
wget_resource () {
	wget "$1" -O "$2"
}

rpi_tarball () {
	if [ "$1" == "armv7" ]; then
		echo "http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-2-latest.tar.gz"
	elif [ "$1" == "aarch64" ]; then
		echo "http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-3-latest.tar.gz"
	else
		error "unknown architecture '$1'"
	fi
}

if [ $# -lt 2 ]; then
	echo "Usage: $0 <armv7|aarch64> <output>"
	echo
	echo "Download Arch Linux ARM tarball."
	exit 1
fi

arch="$1"
output="$2"

# This is for validation purposes only
rpi_tarball "$arch"

progress "Downloading Arch Linux tarball..."
wget_resource "`rpi_tarball "$arch"`" "$output"
[ $? -eq 0 ] || exit 1

exit 0

