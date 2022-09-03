#!/bin/bash
# Version two of a badly written script to install arch

# Vars
MEMSIZE=$(free -m | grep "Mem:" | awk '{print $2}')
REGION="Europe"
CITY="London"
ROOTSIZE="20G"
# Read in userinput
clear
fdisk -l
ws
read -p "What disk do you want to install on? Syntax: /dev/x" INSTALLDISK
clear
read -p "What do you want as your hostname?" HOSTNAME
clear
read -p "What do you want to call your bootloader?" BOOTLOADER
clear
read -p "What do you want to call your virtual group for LVM?" LVMNAME

EFIPART=$INSTALLDISK"1"
BOOTPART=$INSTALLDISK"2"
LVMPART=$INSTALLDISK"3"

if [ "$1" == "chrooted" ]
then
    ln -sf /usr/share/zoneinfo/$REGION/$CITY /etc/localtime
    hwclock --systohc
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" >> /etc/locale.conf
    echo $HOSTNAME > /etc/hostname
    cat >> /etc/hosts << EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME
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
    clear
    echo "Time to set root account password"
    ws
    passwd root
    clear
    grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=$BOOTLOADER
    clear
    blkid
    read -rsn1;echo
    vim /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    	cat >> /etc/crypttab << EOF
swap /dev/$GROUPNAME/${GROUPNAME}Swap /dev/urandom swap,cipher=aes-xts-plain64,size=256
tmp /dev/$GROUPNAME/${GROUPNAME}Tmp /dev/urandom tmp,cipher=aes-xts-plain64,size=256
EOF
	cat >> /etc/fstab << EOF
/dev/mapper/swap none swap sw 0 0
/dev/mapper/tmp /tmp tmpfs defaults 0 0
EOF
    mkdir -m 700 /etc/luksKeys
	dd if=/dev/random of=/etc/luksKeys/home bs=1 count=256
	cryptsetup luksFormat -v /dev/$GROUPNAME/${GROUPNAME}Home /etc/luksKeys/home << EOF
YES
EOF
	cryptsetup -d /etc/luksKeys/home open /dev/$GROUPNAME/${GROUPNAME}Home home
	mkfs.ext4 /dev/mapper/home
	mount /dev/mapper/home /home
	cat >> /etc/crypttab << EOF
home	/dev/$GROUPNAME/${GROUPNAME}Home /etc/luksKeys/home
EOF
	cat >> /etc/fstab << EOF
/dev/mapper/home /home ext4 defaults 0 2
EOF

else
    echo "Starting install..."
    timedatectl set-ntp true
# Partition disk
    fdisk $INSTALLDISK << EOF
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

# Partition disks into LVM 
    pvcreate $LVMPART
    vgcreate $LVMNAME $LVMPART
    lvcreate -L $ROOTSIZE -n ${LVMNAME}Root $LVMNAME
    lvcreate -L $MEMSIZE -n ${LVMNAME}Tmp $LVMNAME
    lvcreate -L $MEMSIZE -n ${LVMNAME}Swap $LVMNAME
    lvcreate -l "100%FREE" -n ${LVMNAME}Home $LVMNAME
# Encrypt the root device
    cryptsetup luksFormat /dev/${LVMNAME}/${LVMNAME}Root
    cryptsetup open /dev/${LVMNAME}/${LVMNAME}Root root
    mkfs.ext4 /dev/mapper/root
    mount /dev/mapper/root /mnt
# create and deal with efi and boot partitions
    mkdir /mnt/boot
    dd if=/dev/zero of=$BOOTPART bs=1M
    mkfs.ext4 $BOOTPART
    mount $BOOTPART /mnt/boot
    mkdir /mnt/efi
    mkfs.fat -F 32 $EFIPART
    mount $EFIPART /mnt/efi
# Install arch and enter chroot
    pacstrap /mnt base linux linux-firmware base-devel vim lvm2 amd-ucode grub efibootmgr
    genfstab -U /mnt >> /mnt/etc/fstab
    cp installScript.sh /mnt/root
    arch-chroot /mnt ./root/installScript.sh chrooted
fi






# Print whitespace
ws(){
    echo " "
}