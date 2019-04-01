#!/bin/sh

progress () {
    echo ">>> $1"
}

error () {
	echo "$1" >&2
	exit 1
}

# name, sizeMB
touch_sparse () {
    dd if=/dev/zero of="$1" bs=1 count=0 seek=$2"M"
}

# file
partition_file () {
    parted "$1" --script \
        mklabel msdos \
        mkpart primary fat32 2048s 256MB \
        mkpart primary ext4 256MB 100% \
        set 1 boot on
}

# file
format_boot () {
    sudo mkfs.vfat "$1"
}

# file
format_root () {
    sudo mkfs.ext4 -F "$1" 
}

# file
mapper_prefix () {
    prefix="/dev/mapper"
    echo $prefix/$1
}

# file
add_mapping () {
    kpartx_out="`sudo kpartx -av "$1"`"
    rval=$?
    partitions="`echo -e "$kpartx_out" | cut -d ' ' -f 3`"
    for p in $partitions
    do
        mapper_prefix "$p"
    done
    return $rval
}

# file
delete_mapping () {
    sudo kpartx -dv "$1"
}

# file, destdir, [file]
extract () {
	bsdtar -xpf "$1" -C "$2" `[ -z "$3" ] || echo "$3"`
}

# device, mountpoint
mount_fs () {
	sudo mount "$1" "$2"
	sudo chown $USER: "$2"
}

# mountpoint
umount_fs () {
	sudo umount "$1" || true
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

atexit () {
	[ -z "$mnt_root" ] || umount_fs "$mnt_root"
	[ -z "$mnt_boot" ] || umount_fs "$mnt_boot"
}

SIZE=2048 # MB
STAGING_DIR="`mktemp -d`"

if [ $# -lt 1 ]; then
	echo "Usage: $0 <aarch64|armv7>"
	echo
	echo "Create a bootable image."
	exit 1
fi

trap atexit EXIT

arch="$1"
tarball="$STAGING_DIR/archlinux-$arch.tar.gz"
disk="blackthrow-$arch-`date +%Y%m%d`.img"

# This is for validation purposes only
rpi_tarball "$arch"

progress "Downloading Arch Linux tarball..."
wget_resource "`rpi_tarball "$arch"`" "$tarball"
[ $? -eq 0 ] || exit 1

progress "Creating a sparse file..."
touch_sparse "$disk" "$SIZE"
[ $? -eq 0 ] || exit 1

progress "Partitioning..."
partition_file "$disk"
[ $? -eq 0 ] || exit 1

progress "Mapping partitions..."
partitions="`add_mapping "$disk"`"
[ $? -eq 0 ] || exit 1

boot="`echo $partitions | cut -d ' ' -f 1`"
root="`echo $partitions | cut -d ' ' -f 2`"

echo "* boot partition -> $boot"
echo "* root partition -> $root"

[ ! -z "$boot" ] || error "boot partition not mapped"
[ ! -z "$root" ] || error "root partition not mapped"

if [ "$boot" == "$root" ]; then
	error "boot and root partitions are the same: this is not right"
fi

progress "Formatting boot partition..."
format_boot "$boot"
[ $? -eq 0 ] || exit 1

progress "Formatting root partition..."
format_root "$root"
[ $? -eq 0 ] || exit 1

mnt_root="$STAGING_DIR/mnt/root"
mkdir -p "$mnt_root"
[ $? -eq 0 ] || exit 1

progress "Mounting root partition..."
mount_fs "$root" "$mnt_root"
[ $? -eq 0 ] || exit 1

progress "Extracting root data from '$tarball'..."
extract "$tarball" "$mnt_root"
[ $? -eq 0 ] || exit 1

mnt_boot="$STAGING_DIR/mnt/boot"
mkdir -p "$mnt_boot"
[ $? -eq 0 ] || exit 1

progress "Mounting boot partition..."
mount_fs "$boot" "$mnt_boot"
[ $? -eq 0 ] || exit 1

progress "Copy boot data..."
mv "$mnt_root/boot/"* "$mnt_boot"
[ $? -eq 0 ] || exit 1

progress "Unmounting root partition..."
umount_fs "$mnt_root"
[ $? -eq 0 ] || exit 1

progress "Unmounting boot partition..."
umount_fs "$mnt_boot"
[ $? -eq 0 ] || exit 1

progress "Unmapping partitions..."
delete_mapping "$disk"
[ $? -eq 0 ] || exit 1

progress "DONE: $disk"

exit 0

