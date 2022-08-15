#!/bin/bash
# Script to install arch faster than I otherwise would be able to due to my chronic need to reinstall my OS
# Very haphazard and my first script so forgive me
# Likely only works in my specific usecase so don't even bother
# LUKS on LVM
# Credit: DreamSequence

#Variables

DISKNAME="/dev/nvme0n1" # Name of the disk to partition
EFIPART=$DISKNAME"p1" # Partition name for EFI partition
BOOTPART=$DISKNAME"p2" # Partition name for boot partition
LVMPART=$DISKNAME"p3" # Partition name for lvm partition
GROUPNAME="blackBox" # Name of lvm virtual volume
ROOTSIZE="50G" # Size (in GB) of root lvm partition
MEMSIZE=$(free -m | grep "Mem:" | awk '{print $2}')
ENCRYPTPASSWORD="testPass"
REGION="Europe"
CITY="London"
HOSTNAME="theStratosphere"
BOOTLOADER="blackBox"

preInstall() {
	clear
	echo "Starting install..."
	echo "LUKS on LVM setup"
	cat << EOM
	    _        _   _         _      __  __   U _____ u        ____    _  _      _   _        ____   
	U  /"\  u   | \ |"|       /"|   U|' \/ '|u \| ___"|/     U /"___|u | ||"|    | \ |"|    U /"___|u 
	 \/ _ \/   <|  \| |>    u | |u  \| |\/| |/  |  _|"       \| |  _ / | || |_  <|  \| |>   \| |  _ / 
	 / ___ \   U| |\  |u     \| |/   | |  | |   | |___        | |_| |  |__   _| U| |\  |u    | |_| |  
	/_/   \_\   |_| \_|       |_|    |_|  |_|   |_____|        \____|    /|_|\   |_| \_|      \____|  
	 \\    >>   ||   \\,-.  _//<,-, <<,-,,-.    <<   >>        _)(|_    u_|||_u  ||   \\,-.   _)(|_   
	(__)  (__)  (_")  (_/  (__)(_/   (./  \.)  (__) (__)      (__)__)   (__)__)  (_")  (_/   (__)__)  
EOM
	# set timedatectl
	timedatectl set-ntp true
}

diskPartition(){
	# fdisk partition drive
	fdisk $DISKNAME << EOF
g
n

+1G
n

+1G
n


t
1
1
t
2
20
t
3
43
w
EOF
	#LVM partition drive
	pvcreate $LVMPART
	vgcreate $GROUPNAME $LVMPART
	lvcreate -L $ROOTSIZE -n ${GROUPNAME}Root $GROUPNAME
	lvcreate -L $MEMSIZE -n ${GROUPNAME}Tmp $GROUPNAME
	lvcreate -L $MEMSIZE -n ${GROUPNAME}Swap $GROUPNAME
	lvcreate -l "100%FREE" -n ${GROUPNAME}Home $GROUPNAME
}

rootEncrypt(){
	cryptsetup luksFormat /dev/${GROUPNAME}/${GROUPNAME}Root << EOF
	${ENCRYPTPASSWORD}
EOF
	cryptsetup open /dev/${GROUPNAME}/${GROUPNAME}Root << EOF
	${ENCRYPTPASSWORD}
EOF
	mkfs.ext4 /dev/mapper/root
}

mountParts(){
	mkdir /mnt/boot
	dd if=/dev/zero of=$BOOTPART bs=1M
	mkfs.ext4 $BOOTPART
	mkdir /mnt/efi
	dd if=/dev/zero of=$LVMPART bs=1M
	mkfs.fat -F 32 $LVMPART
	mount /dev/mapper/root /mnt
	mount $BOOTPART /mnt/boot
	mount $LVMPART /mnt/efi
}

archInstall(){
	pacstrap /mnt base linux linux-firmware base-devel vim lvm2 man-db man-pages amd-ucode grub efibootmgr iwd
	gefstab -U /mnt >> /mnt/etc/fstab
	arch-chroot /mnt
}

mntSetup(){
	ln -sf /usr/share/zoneinfo/$REGION/$CITY /etc/localtime
	hwclock --systohc
	echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" >> /etc/locale.conf
	echo $HOSTNAME > /etc/hostname
	cat > /etc/hosts << EOF
127.0.0.1	localhost
::1	localhost
127.0.1.1	$HOSTNAME
EOF
	cat > /etc/mkinitcpio.conf << EOF
# vim:set ft=sh
# MODULES
# The following modules are loaded before any boot hooks are
# run.  Advanced users may wish to specify all system modules
# in this array.  For instance:
#     MODULES=(piix ide_disk reiserfs)
MODULES=()

# BINARIES
# This setting includes any additional binaries a given user may
# wish into the CPIO image.  This is run last, so it may be used to
# override the actual binaries included by a given hook
# BINARIES are dependency parsed, so you may safely ignore libraries
BINARIES=()

# FILES
# This setting is similar to BINARIES above, however, files are added
# as-is and are not parsed in any way.  This is useful for config files.
FILES=()

# HOOKS
# This is the most important setting in this file.  The HOOKS control the
# modules and scripts added to the image, and what happens at boot time.
# Order is important, and it is recommended that you do not change the
# order in which HOOKS are added.  Run 'mkinitcpio -H <hook name>' for
# help on a given hook.
# 'base' is _required_ unless you know precisely what you are doing.
# 'udev' is _required_ in order to automatically load modules
# 'filesystems' is _required_ unless you specify your fs modules in MODULES
# Examples:
##   This setup specifies all modules in the MODULES setting above.
##   No raid, lvm2, or encrypted root is needed.
#    HOOKS=(base)
#
##   This setup will autodetect all modules for your system and should
##   work as a sane default
#    HOOKS=(base udev autodetect block filesystems)
#
##   This setup will generate a 'full' image which supports most systems.
##   No autodetection is done.
#    HOOKS=(base udev block filesystems)
#
##   This setup assembles a pata mdadm array with an encrypted root FS.
##   Note: See 'mkinitcpio -H mdadm' for more information on raid devices.
#    HOOKS=(base udev block mdadm encrypt filesystems)
#
##   This setup loads an lvm2 volume group on a usb device.
#    HOOKS=(base udev block lvm2 filesystems)
#
##   NOTE: If you have /usr on a separate partition, you MUST include the
#    usr, fsck and shutdown hooks.
HOOKS=(base udev autodetect keyboard keymap consolefont modconf block lvm2 encrypt filesystems fsck)

# COMPRESSION
# Use this to compress the initramfs image. By default, zstd compression
# is used. Use 'cat' to create an uncompressed image.
#COMPRESSION="zstd"
#COMPRESSION="gzip"
#COMPRESSION="bzip2"
#COMPRESSION="lzma"
#COMPRESSION="xz"
#COMPRESSION="lzop"
#COMPRESSION="lz4"

# COMPRESSION_OPTIONS
# Additional options for the compressor
#COMPRESSION_OPTIONS=()
EOF
	mkinitcpio -P
	echo "Time to set ROOT password"
	passwd root
}

grubInstall(){
	grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=$BOOTLOADER
	clear
	echo "Please copy down the correct UUID then hit any key to continue:"
	echo ""
	blkid
	echo ""
	echo "You need this for grubs kernal parameter"
	echo "The syntax will be:"
	echo "cryptdevice=UUID=copiedUUID:root root=/dev/mapper/root"
	vim /etc/default/grub
	grub-mkconfig -o /boot/grub/grub.cfg
}

finishingUp(){
	cat >> /etc/crypttab << EOF
swap	/dev/$GROUPNAME/${GROUPNAME}Swap /dev/urandom swap,cipher=aes-xts-plain64,size=256
tmp	/dev/$GROUPNAME/${GROUPNAME}Tmp /dev/urandom tmp,cipher=aes-xts-plain64,size=256
EOF
	cat >> /etc/fstab << EOF
/dev/mapper/swap none swap sw 0 0

/dev/mapper/tmp /tmp tmpfs defaults 0 0
EOF
}

homeDrive(){
	mkdir -m 700 /etc/luksKeys
	dd if=/dev/random of=/etc/luksKeys/home bs=1 count=256
	cryptsetup luksFormat -v /dev/$GROUPNAME/${GROUPNAME}Home /etc/luksKeys/home
	cryptsetup -d /etc/luksKeys/home open /dev/$GROUPNAME/${GROUPNAME}Home home
	mkfs.ext4 /dev/mapper/home
	mount /dev/mapper/home /home
	cat >> /etc/crypttab << EOF
home	/dev/$GROUPNAME/${GROUPNAME}Home /etc/luksKeys/home
EOF
	cat >> /etc/fstab << EOF
/dev/mapper/home /home ext4 defaults 0 2
EOF
}

preInstall
diskPartition
rootEncrypt
mountParts
archInstall
mntSetup
grubInstall
finishingUp
homeDrive

echo "Done!"
echo "Prepare to reboot, hit any key"
read -rsn1;echo
reboot
