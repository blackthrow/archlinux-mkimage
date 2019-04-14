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

# file
compress_file () {
	gzip -8 "$1"
}

atexit () {
	[ -z "$mnt_root" ] || umount_fs "$mnt_root"
	[ -z "$mnt_boot" ] || umount_fs "$mnt_boot"
}

SIZE=3400 # MB
STAGING_DIR="`mktemp -d`"

if [ $# -lt 2 ]; then
	echo "Usage: $0 <tarball> <output>"
	echo
	echo "Create a bootable image from Arch Linux ARM tarball."
	exit 1
fi

trap atexit EXIT

tarball="$1"
disk="$2"

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

progress "Compress image..."
compress_file "$disk"
[ $? -eq 0 ] || exit 1

progress "DONE: $disk"

exit 0

