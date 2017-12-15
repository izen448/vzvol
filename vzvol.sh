#!/bin/sh
# Debugging Stuff
#set -e 
#set -x
# 

ZROOT=$(zpool list | awk '{ zPools[NR-1]=$1 } END { print zPools[2] }')
ZUSER=$(whoami)
SIZE=10G
VOLNAME=DIE
VOLMK="sudo zfs create -V"
FSTYPE=DIE
errorfunc='MAIN'
IMPORTIMG=DIE
VZVOL_PROGRESS_FLAG="NO"

if [ "$(zpool list | awk '{ zPools[NR-1]=$1 } END { print zPools[1] }')" = bootpool ]; then
	ZROOT=$(zpool list | awk '{ zPools[NR-1]=$1 } END { print zPools[2] }')
else
	ZROOT=$(zpool list | awk '{ zPools[NR-1]=$1 } END { print zPools[1] }')
fi

show_help() {
	errorfunc='show_help'
	cat << 'EOT'
	
	virtbox-zvol is a shell script designed to help automate the process of 
	creating a ZFS zvol for use as a storage unit for virtualization, or testing.
	vzvol was originally created to allow you to back a light .VMDK with a zvol for 
	use with VirtualBox, however additional functionality has been added over time to
	make vzvol a general-use program. I hope you find it useful!

	This script is released under the 2-clause BSD license.
	(c) 2017 RainbowHackerHorse

	https://github.com/RainbowHackerHorse/vzvol

	-h | --help
	Shows this help

	zvol Creation Flags:

	-s | --size
	Allows you to set a size for the zvol.
	Size should be set using M or G.
	Example: --size 10G | -s 1024M
	Defaults to 10G if nothing specified.

	-u | --user
	Sets the user under which we grant permissions for the zvol.
	Defaults to your username if nothing is specified.

	-v | --volume
	MANDATORY OPTION!!
	Sets the zvol name. If nothing is specified or this option is left off,
	the command will FAIL!

	-p | --pool
	This flag will allow you to override the logic to choose the zpool you want
	your zvol on.
	By default, this script selects the first zpool available, unless your 
	first pool is "bootpool" (as with an encrypted system).
	If your first pool is "bootpool", this script will default to the second
	listed pool, usually "zroot" in a default install.

	--sparse
	The sparse flag allows you to create a sparse zvol instead of a pre-allocated one.
	Be careful using this option! Disk space will not be pre-allocated prior to creating
	the zvol which can cause you to run out of room in your VM!

	-t | --type
	This option allows you to set the disk type behavior.
	The following types are accepted:
	virtualbox 	- The default behavior, vzvol will create a shim VMDK to point to the created 
				zvol.
	raw			- Create a raw, normal zvol with no shim, in the default location of 
				/dev/zvol/poolname/volumename
	--file-system
	Setting this flag allows you to format the zvol with your choice of filesystem.
	The default for vzvol is to not create a filesystem on the new zvol.
	The following types are accepted:
	Filesystems with support in FreeBSD:
		zfs 		- Creates a zfs filesystem, using the name set in --volume as the pool name.
		ufs 		- Create a FreeBSD compatible UFS2 filesystem.
		fat32		- Create an MS-DOS compatible FAT32 filesystem.

	Filesystems that require a port be installed:
	*REQUIRES* sysutils/e2fsprogs!
		ext2		- Creates a Linux-compatible ext2 filesystem.
		ext3		- Creates a Linux-compatible ext3 filesystem. 	
		ext4		- Creates a Linux-compatible ext4 filesystem. 	
	*REQUIRES* sysutils/xfsprogs!
		xfs 		- Create an XFS filesystem. 

	--import 
	The --import flag allows you to import the contents of a downloaded disk image to
	your newly created zvol. This is useful when using a pre-installed VM image, such as
	https://github.com/RainbowHackerHorse/FreeBSD-On-Linode 

	-p
	The -p flag is used with --import to show a progress bar for image data importation
	to the vzol. -p requires that sysutils/pv be installed.

	zvol Management Flags:

	--format
	The --format flag allows you to reformat a zvol created by vzvol, using the same 
	options and arguments as --file-system

	--delete
	The --delete flag deletes the zvol you specify. If a .VMDK file is associated with
	the zvol, the .VMDK will also be deleted.
	You MUST specify the zpool the zvol resides on.
	You can get this information from running vzvol --list or zfs list -t volume
	Example: vzvol --delete zroot/smartos11

	--list
	List all zvols on your system, the type, and any associated .VMDK files.
	Example output:
	ZVOL              TYPE        VMDK                        
	zroot/smartos     RAW         none                        
	zroot/ubuntu1604  VirtualBox  /home/username/VBoxDisks/ubuntu1604.vmdk             
	
	
EOT
}

# Script Maintainence Functions
error_code() {
	echo "Error occurred in function ${errorfunc}"
	echo "Exiting"
	exit 1
}
getargz() {
	errorfunc='getargz'
	while :; do
		case $1 in
			-h|--help)
				show_help
				exit
			;;
			-s|--size)
				if [ "$2" ]; then
					SIZE="${2}"
					# Add input check to ensure proper syntax
					shift
				else
					echo "Please provide a size!"
					return 1
				fi
			;;
			-u|--user)
				if [ "$2" ]; then
					ZUSER="${2}"
					# Add input check to ensure proper syntax
					shift
				else
					echo "Please provide a username!"
					return 1
				fi
			;;
			-v|--volume)
				if [ "$2" ]; then
					VOLNAME="${2}"
					# Add input check to ensure proper syntax
					shift
				else
					echo "Please provide a zvol name!"
					return 1
				fi
			;;
			-p|--pool)
				if [ "$2" ]; then
					ZROOT="${2}"
					shift
				else
					echo "Please provide a pool name!"
					return 1
				fi
			;;
			-t|--type)
				if [ "$2" ]; then
					VOLTYPE="${2}"
					if [ "${VOLTYPE}" != "raw" -a "${VOLTYPE}" != "virtualbox" ]; then
						echo "Error. Invalid type ${VOLTYPE} selected!"
						return 1
					fi
					shift
				else
					echo "Type not specified!"
					return 1
				fi
			;;
			--sparse)
				VOLMK="sudo zfs create -s -V"
				shift
			;;
			--file-system)
				if [ "$2" ]; then
					if [ ! "${IMPORTIMG}" = "DIE" ]; then
						echo "--file-system is incompatible with --import."
						return 1
					fi
					FSTYPE="${2}"
					vzvol_fscheck "${FSTYPE}"
					FORMAT_ME="${ZROOT}/${VOLNAME}"
				fi
				shift
			;;
			--import)
				if [ ! "${FSTYPE}" = "DIE" ]; then
						echo "--import is incompatible with --file-system."
						return 1
				fi
				if [ "$2" ]; then
					if [ ! -f "${2}" ]; then
						echo "Error. ${2} does not exist or has incorrect permissions, and can not be imported"
						return 1
					fi
					IMPORTIMG="${2}"
				fi
				shift
			;;
			-p)
				if pkg info | grep -vq pv; then
					echo "Error! You need to install sysutils/pv first, or don't use -p"
					return 1
				fi
				VZVOL_PROGRESS_FLAG="YES"
				shift
			;;
			--delete)
				if [ $(zfs list -t volume | awk '{print $1}' | grep -v "NAME" | grep -vq "${2}") ]; then
					echo "Error, zvol ${2} does not exist."
					echo "Try running vzvol --list or zfs list -t volume to see the available zvols on the system."
					return 1
				else
					DELETE_ME="${2}"
					DELETE_VMDK="${HOME}/VBoxDisks/${2}.vmdk"
					vzvol_delete || exit 1
					exit
				fi
			;;
			--list)
				vzvol_list
				exit
			;;
			--format)
				if [ $(zfs list -t volume | awk '{print $1}' | grep -v "NAME" | grep -vq "${2}") ]; then
					echo "Error, zvol ${2} does not exist."
					echo "Try running vzvol --list or zfs list -t volume to see the available zvols on the system."
					return 1
				else
					if [ ! "$3" ]; then
						echo "Error, please select a zvol to format"
						return 1
					else
						FSTYPE="${2}"
						FORMAT_ME="${3}"
						vzvol_fscheck
						zvol_fs_type
					fi
				fi
			;;
			*)
				break
		esac
		shift
	done
}

# Display Data
vzvol_list() {
	(printf "ZVOL TYPE VMDK \n" \
	; vzvol_list_type) | column -t
}
vzvol_list_type() {
	list_my_vols=$(zfs list -t volume | awk '{print $1}' | grep -v NAME)
	for vols in $list_my_vols; do
		purevolname=$(echo $vols | awk -F "/" '{print $2}')
		if [ -f "${HOME}/VBoxdisks/${purevolname}.vmdk" ]; then
			echo "${vols} VirtualBox ${HOME}/VBoxdisks/${purevolname}.vmdk"
		else
			echo "${vols} RAW none"
		fi
	done
}

# File Creation and Deletion
create_vmdk() {
	errorfunc='create_vmdk'
	if [ ! -d /home/"${ZUSER}"/VBoxdisks/ ]; then
		mkdir -p /home/"${ZUSER}"/VBoxdisks/
	fi
	if [ ! -e /home/"${ZUSER}"/VBoxdisks/"${VOLNAME}".vmdk ]; then
		echo "Creating /home/${ZUSER}/VBoxdisks/${VOLNAME}.vmdk"
		sleep 3
		VBoxManage internalcommands createrawvmdk \
		-filename /home/"${ZUSER}"/VBoxdisks/"${VOLNAME}".vmdk \
		-rawdisk /dev/zvol/"${ZROOT}"/"${VOLNAME}"
	else
		echo "/home/${ZUSER}/VBoxdisks/${VOLNAME}.vmdk" already exists.
		return 1
	fi
}
create_zvol() {
	errorfunc='create_vzol'
	if [ ! -e /dev/zvol/"${ZROOT}"/"${VOLNAME}" ]; then
		"${VOLMK}" "${SIZE}" "${ZROOT}"/"${VOLNAME}"
	fi
	sudo chown "${ZUSER}" /dev/zvol/"${ZROOT}"/"${VOLNAME}"
	sudo echo "own	zvol/${ZROOT}/${VOLNAME}	${ZUSER}:operator" | sudo tee -a /etc/devfs.conf
	if [ ! "${FSTYPE}" = DIE ]; then
		zvol_fs_type || return 1
	fi
	if [ ! "${IMPORTIMG}" = DIE ]; then
		zvol_import_img || return 1
	fi
}
vzvol_delete() {
	errorfunc='vzvol_delete'
	echo "WARNING!"
	echo "This will DESTROY ${DELETE_ME}"
	echo "Unless you have a snapshot of this zvol,"
	echo "ALL DATA WILL BE DELETED AND UNRECOVERABLE!"
	read -p "Do you want to continue? [y/N]?" line </dev/tty
	case "$line" in
		y)
			echo "Deleting ${DELETE_ME}"
			zfs destroy "${DELETE_ME}"
			if [ -f "${DELETE_VMDK}" ]; then
				rm -f "${DELETE_VMDK}"
			fi
		;;
		*)
			echo "Deletion cancelled!"
			return 1
		;;
	esac
}

# Data Management
zvol_import_img() {
	errorfunc='zvol_import_img'
	if [ "${VZVOL_PROGRESS_FLAG}" = "YES" ]; then
		VZVOL_IMPORT_CMD="dd if=${IMPORTIMG} | pv -petrb | of=/dev/zvol/${ZROOT}/${VOLNAME}"
	else
		VZVOL_IMPORT_CMD="dd if=${IMPORTIMG} of=/dev/zvol/${ZROOT}/${VOLNAME}"
	fi
	echo "Now importing ${IMPORTIMG} to /dev/zvol/${ZROOT}/${VOLNAME}"
	echo "This will DESTROY all data on /dev/zvol/${ZROOT}/${VOLNAME}"
	read -p "Do you want to continue? [y/N]?" line </dev/tty
	case "$line" in
		y)
			echo "Beginning import..."
			"${VZVOL_IMPORT_CMD}"
		;;
		*)
			echo "Import cancelled!"
			return 1
		;;
	esac
}

# Checks
checkzvol() {
	errorfunc='checkzvol'
	if [ "${VOLNAME}" = 'DIE' ]; then
		echo "Please provide a zvol name. See --help for more information."
		return 1
	fi 
}

vzvol_fscheck() {
	if [ "${FSTYPE}" != "zfs" -a "${FSTYPE}" != "ufs" -a "${FSTYPE}" != "fat32" -a "${FSTYPE}" != "ext2" -a "${FSTYPE}" != "ext3" -a "${FSTYPE}" != "ext4" -a "${FSTYPE}" != "xfs" ]; then
		echo "Error. Invalid filesystem ${FSTYPE} selected!"
		return 1
	fi
}
zvol_fs_type() {
	errorfunc='zvol_fs_type'
	if [ "${FSTYPE}" = "ext2" -a "${FSTYPE}" = "ext3" -a "${FSTYPE}" = "ext4" -a "${FSTYPE}" = "xfs" ]; then
		echo "Warning. You have selected an FS type supplied by a port. Now checking to see if the port is installed."
		echo "Please note that unsupported FSes may exhibit unexpected behavior!"
		if [ "${FSTYPE}" = "ext2" -a "${FSTYPE}" = "ext3" -a "${FSTYPE}" = "ext4" ]; then
			if pkg info | grep -vq e2fsprogs; then
				echo "Error! You need to install sysutils/e2fsprogs first!"
				return 1
			fi
		elif [ "${FSTYPE}" = "xfs" ]; then
			if pkg info | grep -vq xfsprogs; then
				echo "Error! You need to install sysutils/xfsprogs first!"
				return 1
			fi
		fi
	fi
	echo "Now formatting /dev/zvol/${FORMAT_ME} as ${FSTYPE}"
	echo "This will DESTROY all data on /dev/zvol/${FORMAT_ME}"
	read -p "Do you want to continue? [y/N]?" line </dev/tty
	case "$line" in
		y)
			echo "Beginning format..."
		;;
		*)
			echo "Format cancelled!"
			return 1
		;;
	esac
	case "${FSTYPE}" in
		zfs)
			zvol_create_fs_zfs
		;;
		ufs)
			zvol_create_fs_ufs
		;;
		fat32)
			zvol_create_fs_fat32
		;;
		ext2)
			zvol_create_fs_ext2
		;;
		ext3)
			zvol_create_fs_ext3
		;;
		ext4)
			zvol_create_fs_ext4
		;;
		xfs)
			zvol_create_fs_xfs
		;;
	esac
}

# Type Management
zvol_type_select() {
	errorfunc='zvol_type_select'
	if [ "${VOLTYPE}" = raw ]; then
		zvol_type_raw
	elif [ "${VOLTYPE}" = virtualbox ]; then
		zvol_type_virtualbox
	fi
}
zvol_type_virtualbox() {
	errorfunc='zvol_type_virtualbox'
	create_vzol || return 1
	create_vmdk || return 1
	echo "Please use /home/${ZUSER}/VBoxdisks/${VOLNAME}.vmdk as your VM Disk"
}
zvol_type_raw() {
	errorfunc='zvol_type_raw'
	create_vzol || return 1
	echo "You can find your zvol at: /dev/zvol/${ZROOT}/${VOLNAME}"
}

# zvol Format Functions
zvol_create_fs_zfs() {
	errorfunc='zvol_create_fs_zfs'
	echo "Creating ZFS Filesystem on /dev/zvol/${FORMAT_ME}"
	zpool create "${VOLNAME}" /dev/zvol/"${FORMAT_ME}" || return 1
}
zvol_create_fs_ufs() {
	errorfunc='zvol_create_fs_ufs'
	echo "Creating UFS Filesystem on /dev/zvol/${FORMAT_ME}"
	newfs -E -J -O 2 -U /dev/zvol/"${FORMAT_ME}" || return 1
}
zvol_create_fs_fat32() {
	errorfunc='zvol_create_fs_fat32'
	echo "Creating FAT32 Filesystem on /dev/zvol/${FORMAT_ME}"
	newfs_msdos -F32 /dev/zvol/"${FORMAT_ME}" || return 1
}
zvol_create_fs_ext2() {
	errorfunc='zvol_create_fs_ext2'
	echo "Creating ext2 Filesystem on /dev/zvol/${FORMAT_ME}"
	mke2fs -t ext2 /dev/zvol/"${FORMAT_ME}" || return 1
}
zvol_create_fs_ext3() {
	errorfunc='zvol_create_fs_ext3'
	echo "Creating ext3 Filesystem on /dev/zvol/${FORMAT_ME}"
	mke2fs -t ext3 /dev/zvol/"${FORMAT_ME}" || return 1
}
zvol_create_fs_ext4() {
	errorfunc='zvol_create_fs_ext4'
	echo "Creating ext4 Filesystem on /dev/zvol/${FORMAT_ME}"
	mke2fs -t ext4 /dev/zvol/"${FORMAT_ME}" || return 1
}
zvol_create_fs_xfs() {
	errorfunc='zvol_create_fs_xfs'
	echo "Creating XFS Filesystem on /dev/zvol/${FORMAT_ME}"
	mkfs.xfs /dev/zvol/"${FORMAT_ME}" || return 1
}

getargz "$@" || error_code
checkzvol || error_code
zvol_type_select || error_code
exit 0
