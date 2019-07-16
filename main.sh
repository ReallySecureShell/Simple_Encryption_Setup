#!/bin/bash
##################################LICENSE##########################################
#MIT License
#
#Copyright (c) 2019 Max-Secure
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.
###################################################################################

#Is the terminal capable of color?
case $TERM in
	xterm-color|*-256color)
		#If yes, then assign the color variables
		RED='\e[0;31m'
		GREEN='\e[0;32m'
		YELLOW='\e[1;33m'
		YELLOW_ITALICS='\e[3;1;33m'
		NC='\e[0m'
	;;
	*)
		#If color is not supported, tell the user.
		printf 'Color not supported by this terminal.\n' >&2

		#Set the color variables to white.
		for color in RED GREEN YELLOW YELLOW_ITALICS NC
		do
			$color='\\033[38m'
			eval $_ 
		done 2>/dev/null
	;;
esac

#Get the rootfs partition
function FUNCT_get_rootfs_mountpoint(){
	#To help the user, run the lsblk command
        lsblk

	#Prompt the user for the partition containing the root filesystem.
	function __subfunct_check_if_valid_block_device(){
		read -p 'Partition containing the ROOT filesystem: ' _initial_rootfs_mount
		if [[ ! -b $_initial_rootfs_mount ]]
		then
			printf '[%bWARN%b] Not a valid block device!\n' $RED $NC >&2
			printf 'I: Specify FULL PATH to DEVICE\n'
			__subfunct_check_if_valid_block_device
		fi
	}
	__subfunct_check_if_valid_block_device
}
FUNCT_get_rootfs_mountpoint

#ONLY INITRAMFS-TOOLS and mkinitcpio are supported at the moment. But this function will stay as DRACUT support is planned.
########################################################################################################
function FUNCT_verify_required_packages(){
	printf '[%bINFO%b] Mounting %s\n' $YELLOW $NC $_initial_rootfs_mount >&2

	#Mount root partition into /mnt
	if [[ `lsblk --output MOUNTPOINT $_initial_rootfs_mount | grep '^\/mnt$'` != '/mnt' ]]
	then
		sudo mount $_initial_rootfs_mount /mnt
		case $? in
		'0')
			printf '[%bINFO%b] Successfully mounted %s\n' $YELLOW $NC $_initial_rootfs_mount >&2
		;;
		*)
			printf '[%bFAIL%b] Failed to mount %s\n' $RED $NC $_initial_rootfs_mount >&2
			exit 1
		;;
		esac
	fi

	#Keep track if initramfs-tools is found first. If not use dracut.
	local SUCCESS=0

	#Keep track if initramfs is not found.
	local ERROR=0	

	#Be verbose as to which packages are being checked.
	for REQUIRED_PACKAGE in cryptsetup update-initramfs mkinitcpio dracut
	do
		#Search within the chroot for the required packeges.
		if [[ ! -z $(sudo chroot /mnt which $REQUIRED_PACKAGE 2>/dev/null) ]]
		then #If found
			printf '[%bOK%b]   %s is installed on %s\n' $GREEN $NC $REQUIRED_PACKAGE $_initial_rootfs_mount >&2
			if [ $REQUIRED_PACKAGE == 'update-initramfs' ]
			then
				___INIT_BACKEND___='update-initramfs'

				SUCCESS=$(($SUCCESS+1))
			elif [ $REQUIRED_PACKAGE == 'mkinitcpio' ]
			then
				___INIT_BACKEND___='mkinitcpio'
				SUCCESS=$(($SUCCESS+1))
			elif [ $REQUIRED_PACKAGE == 'dracut' ]
			then
				#If 0 then update-initramfs tools was not found
				if [ $SUCCESS == 0 ]
				then
					___INIT_BACKEND___='dracut'

					#Exit because there is no dracut support in the script yet.
					###########################################################################
					printf '[%bFAIL%b] No dracut support. Exiting\n' $RED $NC >&2
					sudo umount /mnt
					exit 1
					###########################################################################

					printf '[%bINFO%b] Creating directories to store dracut configuration files\n' $YELLOW $NC >&2
					#Pre-make the directories for dracut. These will be named the same as the initramfs-tools directory/sub-directories to make things simpler.
					sudo chroot /mnt mkdir -p /etc/initramfs-tools/{conf.d,scripts,hooks}
				fi
			fi
		else #If NOT found
			printf '[%bWARN%b] %s is NOT installed on %s\n' $YELLOW $NC $REQUIRED_PACKAGE $_initial_rootfs_mount >&2
			#If cryptsetup is not installed
			if [ $REQUIRED_PACKAGE == 'cryptsetup' ]
			then
				sudo umount /mnt
				exit 1
			#If update-initramfs is not found
			elif [ $REQUIRED_PACKAGE == 'update-initramfs' ]
			then
				#Tell the dracut command that initramfs failed to be found.
				ERROR=$(($ERROR+1))
			elif [ $REQUIRED_PACKAGE == 'mkinitcpio' ]
			then
				ERROR=$(($ERROR+1))
			elif [ $REQUIRED_PACKAGE == 'dracut' ]
			then
				if [[ $ERROR -ge 2 ]]
				then
					printf '[%bFAIL%b] No compatible initramfs creation tool found. Exiting\n' $RED $NC >&2
					sudo umount /mnt
					exit 1
				fi
			fi
		fi
	done

	printf '[%bINFO%b] Will use %s as the backend initramfs creation tool\n' $YELLOW $NC $___INIT_BACKEND___ >&2
}
FUNCT_verify_required_packages
#########################################################################################################################################################

#Read the mounted filesystems /etc/fstab to determine the location of all other partitions.
function FUNCT_identify_all_partitions(){
	printf '[%bINFO%b] Searching for partitions\n' $YELLOW $NC >&2

	#Array containing discovered partitions.
	___PARTITIONS___=()

	local counter=0

	for __PART__ in `awk '/^[^#]/{if ($3 == "swap" || $3 == "tmpfs" || $2 == "/boot" || $2 == "/boot/efi");else print $1":"$2":"$3;}' /mnt/etc/fstab`
	do
		___PARTITIONS___[$counter]=$__PART__
		printf 'Discovered partition: %s\n' ${___PARTITIONS___[$counter]}

		counter=$(($counter+1))
	done
}
FUNCT_identify_all_partitions

#Check if /boot/grub/x86_64-efi exists, if so
#determine the mountpoint of the EFI partition.
#and verify that it is a valid efi partition.
function FUNCT_detect_partition_table_type(){
	local __get_grub_architecture__=$(ls -1d /mnt/boot/grub/{x86_64-efi,i386-pc} 2>/dev/null)

	case $__get_grub_architecture__ in
	'/mnt/boot/grub/x86_64-efi')
		#Has grub been installed with EFI support?
		printf '[%bINFO%b] Grub reports being installed with EFI support. Verifying\n' $YELLOW $NC >&2

		#Check /mnt/etc/fstab for /boot/efi
		printf '[%bINFO%b] Reading fstab information for the %s filesystem\n' $YELLOW $NC $_initial_rootfs_mount >&2

		#Get the UUID of the EFI partition from /mnt/etc/fstab
		#Use the below variable to mount the efi partition and
		#check its contents, verifying that it is a valid EFI
		#partition. This variable can also be used to quickly
		#mount the efi partition if needed.
		_uuid_of_efi_part=`sed -n '/\/boot\/efi/{
		/^UUID\=/{
			s/^UUID\=//
			s/ .*//
			p
		}
		}' /mnt/etc/fstab`

		#Verify that the value found is a valid EFI partition.
		#If the _uuid_of_efi_part value is empty, that tells the rest of the
		#script to use DOS instead.
		if [ -z $_uuid_of_efi_part ]
		then
			printf '[%bINFO%b] Failed to detect the location of the EFI partition\n' $YELLOW $NC >&2
		else
			printf '[%bINFO%b] Potential EFI partition discovered with the UUID of: %s\n' $YELLOW $NC $_uuid_of_efi_part >&2

			#Mount the EFI partition in /mnt/boot/efi
			printf '[%bINFO%b] Mounting potential EFI partition: %s\n' $YELLOW $NC $_uuid_of_efi_part >&2
			sudo mount --uuid $_uuid_of_efi_part /mnt/boot/efi

			printf '[%bINFO%b] Checking if partition: %s is a valid EFI partition\n' $YELLOW $NC $_uuid_of_efi_part >&2
			#Basic check to see if the partition contains EFI files.
			if [[ -z `find /mnt/boot/efi/EFI/* -name "*.efi" | xargs -i file {} | grep 'EFI application'` ]]
			then
				printf '[%bWARN%b] %s is invalid. No EFI files discovered on partition. DOS will be used instead\n' $RED $NC $_uuid_of_efi_part >&2
				unset _uuid_of_efi_part
			else
				printf '[%bOK%b]   %s: is a valid EFI partition\n' $GREEN $NC $_uuid_of_efi_part >&2
			fi

			#Unmount the mounted EFI partition
			printf '[%bINFO%b] Unmounting /mnt/boot/efi\n' $YELLOW $NC >&2
			sudo umount /mnt/boot/efi
		fi
	;;
	'/mnt/boot/grub/i386-pc')
		printf '[%bINFO%b] Partition table type is DOS\n' $YELLOW $NC >&2
	;;
	*)
		printf '[%bFAIL%b] Unsupported GRUB architecture. Only i386-pc and x86_64-efi are supported!\n' $RED $NC >&2
		printf 'Error from input: %s\n' $__get_grub_architecture__
		exit 1
	;;
	esac

	#Unmount the root partition
	printf '[%bINFO%b] Detection finished, unmounting /mnt\n' $YELLOW $NC >&2
	sudo umount /mnt

	#Tell the user which partition table will be used
	if [ -z $_uuid_of_efi_part ]
	then
		printf '[%bINFO%b] Will install for the i386 platform\n' $YELLOW $NC >&2
	else
		printf '[%bINFO%b] Will install for the x86_64-efi platform\n' $YELLOW $NC >&2
	fi
}
FUNCT_detect_partition_table_type

#Autogenerate a GPG key-pair to use for encrypting/decrypting the LUKS passphrase.
function FUNCT_create_gpg_key_passphrase(){
	#Create passphrase used by gpg for the rest of the script.
	printf '[%bINFO%b] Creating GPG passphrase\n' $YELLOW $NC >&2
	__key_passphrase__=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | sha256sum | sed 's/\ -//')

	#We are editing the GPG user configs because otherwise we will be given an ioctl error when trying to encrypt/decrypt the LUKS passphrase.
	printf '[%bINFO%b] Editing GPG user configuration\n' $YELLOW $NC >&2
	cat << __EDIT_GPG.CONF__ > ~/.gnupg/gpg.conf
use-agent
pinentry-mode loopback
__EDIT_GPG.CONF__

	cat << __EDIT_GPG_AGENT__ > ~/.gnupg/gpg-agent.conf
allow-loopback-pinentry
__EDIT_GPG_AGENT__

	printf '[%bINFO%b] Reloading GPG agent\n' $YELLOW $NC >&2
	gpg-connect-agent <<< 'RELOADAGENT'
}
FUNCT_create_gpg_key_passphrase

#Creates a temparary file in shared memory that stores the LUKS encryption password. 
function FUNCT_get_LUKS_passphrase(){
	printf '[%bINFO%b] Mounting tmpfs\n' $YELLOW $NC >&2
	#Create a mapped memory file in /dev/shm
	sudo mount -t tmpfs -o size=1k tmpfs /dev/shm

	function __subfunct_ask_for_password(){
		#Store the LUKS passphrase and verify passphrase to check if the user entered the passphrase correctly.
		local ___LUKS_PASSPHRASE___=()
		
		#Ask user for their LUKS password. Verify it. Encrypt it and add it to /dev/shm/LUKS_passphrase.
		read -sp 'Enter LUKS passphrase: ' ___LUKS_PASSPHRASE___[0]
		#Print new-line character because read does not print a newline.
		printf '\n'

		#Verify passphrase
		read -sp 'Verify passphrase: ' ___LUKS_PASSPHRASE___[1]
		printf '\n'

		#If the passphrases differ, recall the function.
		if [[ ${___LUKS_PASSPHRASE___[0]} != ${___LUKS_PASSPHRASE___[1]} ]]
		then
			printf 'Invalid passphrase\n'
			__subfunct_ask_for_password
		else
			printf '[%bINFO%b] Saving encrypted LUKS passphrase to /dev/shm/LUKS_PASSPHRASE.gpg\n' $YELLOW $NC >&2
			#Encrypt LUKS passphrase and store it in /dev/shm/LUKS_Password.gpg
			gpg --quiet --cipher-algo aes256 --digest-algo sha512 -c -a --passphrase $__key_passphrase__ -o /dev/shm/LUKS_PASSPHRASE.gpg << __END_OF_PASSPHRASE__
${___LUKS_PASSPHRASE___[0]}
__END_OF_PASSPHRASE__
		fi
	}
	__subfunct_ask_for_password
}
if [[ ! -e /dev/shm/LUKS_PASSPHRASE.gpg ]]
then
	FUNCT_get_LUKS_passphrase
else
	printf '[%bINFO%b] Already created LUKS passphrase\n' $YELLOW $NC >&2
fi

function FUNCT_initial_drive_encrypt(){
	#Run e2fsck on whichever partition was discovered.
	sudo e2fsck -fy $1

	#Then resize the disk
	sudo resize2fs -M $1

	#Add encryption to the block device.
	echo -n `gpg --quiet -d --passphrase $__key_passphrase__ /dev/shm/LUKS_PASSPHRASE.gpg` | sudo cryptsetup-reencrypt --key-file=- --new --type=luks1 --reduce-device-size 4096S $1

	#Open the filesystem as a mapped device.
	echo -n `gpg --quiet -d --passphrase $__key_passphrase__ /dev/shm/LUKS_PASSPHRASE.gpg` | sudo cryptsetup --key-file=- open $1 $2

	#Size filesystem back to max size.
	sudo resize2fs /dev/mapper/$2
}

#The map name is the mountpoint minus the /'s.
___MAPPER_NAMES___=()

#The UUID or LVM mapper name that corrisponds to the device.
___SOURCE_DEVICE___=()

#The location of the LUKS drive so a keyfile can be added to it.
__ADD_KEYFILE_TO_DEVICE__=()

for __DISCOVERED_PARTITIONS__ in ${___PARTITIONS___[@]}
do
	_rootfs_mapper_name=$(awk -F : '{if ($2 == "/") gsub("\/", "root");else gsub("\/", "");print $2}' <<< $__DISCOVERED_PARTITIONS__ 2>/dev/null)

	if [[ ! $__DISCOVERED_PARTITIONS__ =~ (.){8}\-((.){4}\-){3}(.){12} ]]
	then
		__DISCOVERED_PARTITIONS__=$(sed 's/\:.*//' <<< $__DISCOVERED_PARTITIONS__)

		if [[ -b $__DISCOVERED_PARTITIONS__ ]]
		then
			___MAPPER_NAMES___+=($_rootfs_mapper_name)
			___SOURCE_DEVICE___+=("$__DISCOVERED_PARTITIONS__")
			__ADD_KEYFILE_TO_DEVICE__+=("$__DISCOVERED_PARTITIONS__")
			FUNCT_initial_drive_encrypt $__DISCOVERED_PARTITIONS__ $_rootfs_mapper_name
		else
			printf '[%bWARN%b] The partition %s is not currently present\n' $RED $NC $__DISCOVERED_PARTITIONS__ >&2
		fi
	else
		for __PART__ in "$(sed -E 's/.*\=|\:.*//g' <<< "$__DISCOVERED_PARTITIONS__" | xargs -i find /dev/disk/by-uuid/{} | xargs -i readlink {} | sed 's/^.*\//\/dev\//')"
		do
			if [[ -b $__PART__ ]]
			then
				___MAPPER_NAMES___+=($_rootfs_mapper_name)
				___SOURCE_DEVICE___+=("UUID=$(sed -E 's/.*\=|\:.*//g' <<< $__DISCOVERED_PARTITIONS__)")
				__ADD_KEYFILE_TO_DEVICE__+=($__PART__)
				FUNCT_initial_drive_encrypt $__PART__ $_rootfs_mapper_name
			else
				printf '[%bWARN%b] The partition %s is not currently present\n' $RED $NC $__PART__ >&2
			fi
		done
	fi
done

#set mapper name back to the string root. As that is the mapper name for the root partition.
_rootfs_mapper_name='root'

#Chroot into the encrypted filesystem.
function FUNCT_setup_mount(){
	#Since opening the device can be skipped in the above function,
	#check if the mountpoint exists, if not, open the encrypted
	#filesystem.
	if [[ ! -b $1 ]]
	then
		printf '[%bINFO%b] %s not yet opened! Opening it now.\n' $YELLOW $NC $2 >&2
		echo -n `gpg --quiet -d --passphrase $__key_passphrase__ /dev/shm/LUKS_PASSPHRASE.gpg` | sudo cryptsetup --key-file=- open $2 $_rootfs_mapper_name
		if [[ -b $1 ]]
		then
			printf '[%bOK%b]   Successfully opened %s\n' $GREEN $NC $2 >&2
		else
			printf '[%bFAIL%b] Failed to open %s\n' $RED $NC $2 >&2

			#Exit because there is nothing that can be done if the LUKS device fails to mount.
			exit 1
		fi
	fi

	#Mount the decrypted filesystem in the /mnt directory
	if [[ `mountpoint /mnt 2>/dev/null` != "/mnt is a mountpoint" ]]
	then
		printf '[%bINFO%b] Mounting %s into /mnt\n' $YELLOW $NC $1 >&2
		sudo mount $1 /mnt
		if [[ `mountpoint /mnt 2>/dev/null` == "/mnt is a mountpoint" ]]
		then
			printf '[%bOK%b]   Successfully mounted %s into /mnt!\n' $GREEN $NC $1 >&2
		else
			printf '[%bFAIL%b] Failed to mount %s into /mnt!\n' $RED $NC $1 >&2
			exit 1
		fi
	fi

	#To make sure the system will be mostly usable when we chroot,
	#bind the dev, sys, and proc directories to the decrypted
	#filesystem.
	for _bindings_for_chroot_jail in dev sys proc
	do
		if [[ `mountpoint /mnt/$_bindings_for_chroot_jail 2>/dev/null` != "/mnt/$_bindings_for_chroot_jail is a mountpoint" ]]
		then
			sudo mount --bind /$_bindings_for_chroot_jail /mnt/$_bindings_for_chroot_jail
		fi
	done

	local counter=0

	#Mount all other encrypted partitions to the mount point inside the mounted filesystem.
	for __MAPPER__ in ${___MAPPER_NAMES___[@]}
	do
		for __MOUNTPOINT__ in ${___PARTITIONS___[$counter]}
		do
			__MOUNTPOINT__=$(awk -F ':' '{print $2}' <<< $__MOUNTPOINT__)
			break
		done
		if [[ $__MAPPER__ != 'root' ]] && [[ $__MOUNTPOINT__ != '/' ]]
		then
			printf '[%bINFO%b] Mounting /dev/mapper/%s to /mnt%s\n' $YELLOW $NC $__MAPPER__ $__MOUNTPOINT__ >&2
			sudo mount /dev/mapper/$__MAPPER__ /mnt$__MOUNTPOINT__
		fi
		counter=$(($counter+1))
	done
}
FUNCT_setup_mount "/dev/mapper/$_rootfs_mapper_name" $_initial_rootfs_mount

function FUNCT_add_encrypted_partitions_to_crypttab_and_modify_fstab(){
	#Ask the user if they want to allow TRIM operations for SSDs.
	#If the user is using an HDD, they should say No (N).
	#This is to know if the "discard" option should be set in crypttab.
	#The option tells luks weather or not to allow TRIMMING for FLASH
	#devices, such as SSDs.
	function __subfunct_trim(){
		read -p 'Allow TRIM operations for solid-state drives? (y/N): '

		#Using the default $REPLY variable since it is automatically assigned anyway.
		#And it saves writting a variable that will be used only once.
		case $REPLY in
			y|Y)
				discard=',discard'
			;;
			n|N)
				discard=''
			;;
			*)
				__subfunct_trim
			;;
		esac
	}
	__subfunct_trim

	#Take own of the crypttab file so we can write to it.
	sudo chown $USER:$USER /mnt/etc/crypttab

	#Add all encrypted partitions to /mnt/etc/crypttab
	counter=0
	for __MAPPER__ in ${___MAPPER_NAMES___[@]}
	do
		#USE add_keyfile variable. the UUIDs of the enties are for the mapped device instead of the actual encrypted device. 
		for __SOURCE__ in $(sed -E 's/.*UUID/UUID/;s/^UUID\: /UUID=/' <<< $(sudo file -sL ${__ADD_KEYFILE_TO_DEVICE__[$counter]}))
		do
			break
		done

		if [ $___INIT_BACKEND___ == 'update-initramfs' ]
		then
			if [[ $__MAPPER__ == 'root' ]]
			then 
				echo "$__MAPPER__ $__SOURCE__ none luks$discard,keyscript=/etc/initramfs-tools/hooks/unlock.sh" >> /mnt/etc/crypttab
			else
				echo "$__MAPPER__ $__SOURCE__ /etc/initramfs-tools/scripts/unlock.key luks$discard" >> /mnt/etc/crypttab
			fi
		elif [ $___INIT_BACKEND___ == 'mkinitcpio' ]
		then
			if [[ $__MAPPER__ == 'root' ]]
			then
				echo "$__MAPPER__ $__SOURCE__ none luks$discard" >> /mnt/etc/crypttab
			else
				echo "$__MAPPER__ $__SOURCE__ /crypto_keyfile.bin luks$discard" >> /mnt/etc/crypttab
			fi
		fi
		counter=$(($counter+1))
	done

	#Modify /mnt/etc/fstab to point to the correct partitions.
	local counter=0
	for __FSTAB_ORIGINAL_ENTRY__ in ${___SOURCE_DEVICE___[@]}
	do
		__MAPPER_NAME__=${___MAPPER_NAMES___[$counter]}

		printf 'fstab: %s changed_to: /dev/mapper/%s\n' $__FSTAB_ORIGINAL_ENTRY__ $__MAPPER_NAME__ >&2
		if [[ ! $__FSTAB_ORIGINAL_ENTRY__ =~ ^UUID\= ]]
		then
			__FSTAB_ORIGINAL_ENTRY__=$(sed 's/\//\\\//g' <<< "$__FSTAB_ORIGINAL_ENTRY__")
		fi

		sudo sed -Ei 's/'"$__FSTAB_ORIGINAL_ENTRY__"'/\/dev\/mapper\/'"$__MAPPER_NAME__"'/' /mnt/etc/fstab
		counter=$(($counter+1))
	done

	#Set crypttab to be owned by root.
	sudo chown root:root /mnt/etc/crypttab

	#Unset the discard variable
	unset discard
}
FUNCT_add_encrypted_partitions_to_crypttab_and_modify_fstab

function FUNCT_write_unlock_script(){
	#Change the name of the keyfile based on the initramfs tool being used.
	if [ $___INIT_BACKEND___ == 'update-initramfs' ]
	then
		local __keyfile_name='/mnt/etc/initramfs-tools/scripts/unlock.key'
	elif [ $___INIT_BACKEND___ == 'mkinitcpio' ]
	then
		local __keyfile_name='/mnt/crypto_keyfile.bin'
	fi

	#Create key used for unlocking the root filesystem in initramfs.
	printf '[%bINFO%b] Generating keyfile from /dev/urandom\n' $YELLOW $NC >&2
	sudo touch $__keyfile_name
	sudo chown $USER:$USER $__keyfile_name
	dd if=/dev/urandom count=4 bs=512 | base64 > $__keyfile_name

	#Add new keyfile to LUKS as an additional key to all encrypted partitions.
	for __DEVICE__ in ${__ADD_KEYFILE_TO_DEVICE__[@]}
	do
		printf '[%bINFO%b] Adding keyfile to %s\n' $YELLOW $NC $__DEVICE__ >&2
		echo -n `gpg --quiet -d --passphrase $__key_passphrase__ /dev/shm/LUKS_PASSPHRASE.gpg` | sudo cryptsetup --key-file=- luksAddKey $__DEVICE__ $__keyfile_name
	done

	#If initramfs-tools is the init creation tool, then run the below operation.
	if [ $___INIT_BACKEND___ == 'update-initramfs' ]
	then
		#Generate unlock.sh keyfile for initramfs.
		printf '[%bINFO%b] Creating unlock.sh script for initramfs\n' $YELLOW $NC >&2
		sudo touch /mnt/etc/initramfs-tools/hooks/unlock.sh

		#Change ownership of /mnt/etc/initramfs-tools/hooks/unlock.sh
		sudo chown $USER:$USER /mnt/etc/initramfs-tools/hooks/unlock.sh

		#Create unlock script
		printf '[%bINFO%b] Creating unlock script in /mnt/etc/initramfs-tools/hooks/unlock.sh\n' $YELLOW $NC >&2
		cat << _unlock_script_file_data > /mnt/etc/initramfs-tools/hooks/unlock.sh
#!/bin/sh

cat /scripts/unlock.key

exit 0
_unlock_script_file_data

		#Set ownership for unlock.sh back to root and set unlock.key to be owned by root also.
		sudo chown root:root /mnt/etc/initramfs-tools/hooks/unlock.sh

		#Set restrictive permissions on the keyscript and keyfile.
		sudo chroot /mnt chmod 100 /etc/initramfs-tools/hooks/unlock.sh

	#If using the mkinitcpio init-creation tool modify its config file found in /etc/mkinitcpio.conf to include the key file.
	elif [ $___INIT_BACKEND___ == 'mkinitcpio' ]
	then
		#Add the keyfile into the mkinitcpio configuration file. Add the file as the first entry in the FILE field.
		printf '[%bINFO%b] Adding entry for keyfile into /mnt/etc/mkinitcpio.conf\n' $YELLOW $NC >&2
		sudo sed -Ei 's/^FILES=[\"|\(](.*)[\"|\)]/FILES=\(\/crypto_keyfile.bin \1\)/g' /mnt/etc/mkinitcpio.conf
	fi

	sudo chown root:root $__keyfile_name
	sudo chmod 400 $__keyfile_name
	printf '[%bINFO%b] Restrictive permissions applied to generated files\n' $YELLOW $NC >&2
}
FUNCT_write_unlock_script

function FUNCT_modify_grub_configuration(){
	#Enable cryptodisks for grub.
	sudo sed -Ei 's/GRUB_CMDLINE_LINUX="(.*?)\"/&\nGRUB_ENABLE_CRYPTODISK=y/' /mnt/etc/default/grub

	#Have grub preload the required modules for luks and cryptodisks.
	sudo sed -Ei 's/GRUB_ENABLE_CRYPTODISK=y/&\nGRUB_PRELOAD_MODULES="part_gpt part_msdos luks cryptodisk"/' /mnt/etc/default/grub

	#Modify the GRUB_CMDLINE_LINUX_DEFAULT entry if using the mkinitcpio creation tool.
	if [ $___INIT_BACKEND___ == 'mkinitcpio' ]
	then
		#Get the UUID of the root partition.
		local __ROOT_UUID__=$(sudo sed -En '/^root/{
        	s/root UUID\=| none.*//g
        	p
		}' /mnt/etc/crypttab)

		#Apply change to the /mnt/etc/default/grub file.
		printf '[%bINFO%b] Editing the GRUB_CMDLINE_LINUX_DEFAULT line in /mnt/etc/default/grub\n       as mkinitcpio requires it.\n' $YELLOW $NC >&2
		sudo sed -Ei 's/^GRUB_CMDLINE_LINUX_DEFAULT\=\"(.*)\"/GRUB_CMDLINE_LINUX_DEFAULT\=\"\1 cryptdevice=UUID='"$__ROOT_UUID__"':root root=\/dev\/mapper\/root\"/g' /mnt/etc/default/grub
	fi

	#Mount EFI partition if installing for EFI.
	#And install grub with EFI.
	#Else install for DOS.
	if [ ! -z $_uuid_of_efi_part ]
	then
		#Mount EFI partition in /mnt/boot/efi
		printf '[%bINFO%b] Mounting EFI partition: %s to /mnt/boot/efi\n' $YELLOW $NC $_uuid_of_efi_part >&2
		sudo mount --uuid $_uuid_of_efi_part /mnt/boot/efi

		#Install grub with EFI support
		printf '[%bINFO%b] Installing grub with EFI support\n' $YELLOW $NC >&2
		
		function __subfunct_get_boot_directory_name(){
			#Pre-create a script file that will be run in a chroot.
			sudo touch /mnt/script.sh

			#Change ownership of the file to the current user.
			sudo chown $USER:$USER /mnt/script.sh

			#Make the file executable
			sudo chmod 744 /mnt/script.sh

			#Write the script file
			cat << __SCRIPT_FILE__ > /mnt/script.sh
#!/bin/bash

for __DISTRO__ in "\$(sed -n '/GRUB_DISTRIBUTOR/{p}' /etc/default/grub)"
do
	eval "\$__DISTRO__"
	echo \$GRUB_DISTRIBUTOR
done
__SCRIPT_FILE__
			#Execute the script file and place the output into DISTRIBUTOR.log
			sudo chroot /mnt /bin/bash << __EXEC__
./script.sh > DISTRIBUTOR.log
__EXEC__

			___DISTRIBUTOR_NAME___=$(sudo ls -1 /mnt/boot/efi/EFI | sudo grep -i "$(cat /mnt/DISTRIBUTOR.log)")
		}
		__subfunct_get_boot_directory_name

		sudo chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot/efi/EFI/$___DISTRIBUTOR_NAME___ --recheck
		sudo chroot /mnt grub-mkconfig -o /boot/efi/EFI/$___DISTRIBUTOR_NAME___/grub/grub.cfg

		#Remove the script and associated log file from the / of the mounted filesystem.
		sudo rm /mnt/{script.sh,DISTRIBUTOR.log}
	else
		if [[ `sed -E '/TYPE/d;/crypt/d' <<< $(lsblk --output TYPE $_initial_rootfs_mount)` == 'lvm' ]]
		then
			local _grub_install_device=$(sed -E 's/^  //;s/[0-9]+.*$//' <<< $(sudo chroot /mnt lvs --noheadings -o devices $_initial_rootfs_mount 2>/dev/null))
			printf '[%bINFO%b] Installing grub to %s\n' $YELLOW $NC $_grub_install_device >&2
			sudo chroot /mnt grub-install --target=i386-pc --recheck $_grub_install_device
		else
			#Remove partition numbers from the end of the root device.
			local _grub_install_device=${_initial_rootfs_mount%%[0-9]}

			#Install grub with i386 architecture support ONLY.
			printf '[%bINFO%b] Installing grub to %s\n' $YELLOW $NC $_grub_install_device >&2
			sudo chroot /mnt grub-install --target=i386-pc --recheck $_grub_install_device
		fi
	fi
}
FUNCT_modify_grub_configuration

function FUNCT_create_encrypted_swap(){
	###########################################################
	if [[ `sed '/TYPE/d' <<< $(lsblk --output TYPE $_initial_swapfs_mount)` == 'lvm' ]]
	then
		#If lvm then use the partition name for LVM.
		printf '[%bINFO%b] Adding swap entry to /mnt/etc/crypttab\n' $YELLOW $NC >&2
		echo "swap_$SWAP_INDEX $_initial_swapfs_mount /dev/urandom swap,offset=2048,cipher=aes-xts-plain64,size=512" >> /mnt/etc/crypttab

		if [[ $RESUME_PASSED == '0' ]] && [[ $___INIT_BACKEND___ == 'update-initramfs' ]]
		then
			sudo chown $USER:$USER /mnt/etc/initramfs-tools/conf.d/resume

			printf '[%bINFO%b] Modifying /mnt/etc/initramfs-tools/conf.d/resume\n' $YELLOW $NC >&2

			#Not really sure the purpose of this (as in its not doing anything), its appently been here for a bit without causing errors, but still...
			echo "RESUME=$_initial_swapfs_mount"

			sudo chown root:root /mnt/etc/initramfs-tools/conf.d/resume
			RESUME_PASSED=$(($RESUME_PASSED+1))
		fi
	else
		local _swapfs_label_name=swapfs_$counter

		#Create a blank filesystem 1M in size at the start of the swap partition, this is so we can set a stable name to the swap partition.
		printf '[%bINFO%b] Creating blank ext2 filesystem at the start of %s\n' $YELLOW $NC $_initial_swapfs_mount >&2
		sudo chroot /mnt mkfs.ext2 -L $_swapfs_label_name $_initial_swapfs_mount 1M <<< "y"

		#Add entry in crypttab for our encrypted swapfs.
		printf '[%bINFO%b] Adding swap entry to /mnt/etc/crypttab\n' $YELLOW $NC >&2
		echo "swap_$SWAP_INDEX LABEL=$_swapfs_label_name /dev/urandom swap,offset=2048,cipher=aes-xts-plain64,size=512" >> /mnt/etc/crypttab

		if [[ $RESUME_PASSED == '0' ]] && [[ $___INIT_BACKEND___ == 'update-initramfs' ]]
		then
			printf '[%bINFO%b] Modifying /mnt/etc/initramfs-tools/conf.d/resume\n' $YELLOW $NC >&2
			sudo sed -i 's/.*/RESUME=LABEL='"$_swapfs_label_name"'/' /mnt/etc/initramfs-tools/conf.d/resume
			RESUME_PASSED=$(($RESUME_PASSED+1))
		fi
	fi
	##########################################################

	#Append new swapfs entry into /mnt/etc/fstab
	printf '[%bINFO%b] Adding swap entry to /mnt/etc/fstab\n' $YELLOW $NC >&2
	echo "/dev/mapper/swap_$SWAP_INDEX none swap sw 0 0" >> /mnt/etc/fstab
}

#The purpose of the code below is for setting up swap automatically. It provides the information
#needed to identify/modify which swap partitions are encrypted.
###################################################################################################

#Check if any swap partitions are available
if [[ -z `sudo chroot /mnt blkid -t TYPE="swap"` ]]
then
	printf '[%bINFO%b] No swap filesystem(s) present\n' $YELLOW $NC >&2
else
	#This function has one purpose, to populate the __SWAP_FILESYSTEMS_ARRAY__. This will store ALL detectable swap partitions.
	#The reason its in a function is for easier control later on.
	function ___DISCOVER_SWAP_FILESYSTEMS___(){
		__SWAP_FILESYSTEMS_ARRAY__=($(sudo chroot /mnt blkid -t TYPE="swap" -o device))
	}
	___DISCOVER_SWAP_FILESYSTEMS___

	#Tell the user what swap partition will be encrypted. The partitions can be adjusted however and are not final.
	printf 'Will encrypt the following SWAP devices:\n'
	for i in ${__SWAP_FILESYSTEMS_ARRAY__[@]}
	do
		echo $i
	done

	#Function for handeling editing (primarily) of the swap array. It provides options for the user.
	function __subfunct_prep_for_encrypting_swap(){
		read -p 'Swap configuration alright? (y)es (e)dit (s)how_all_swap (S)how_configured_swap (r)escan (a)bort: '

		case $REPLY in
			[yY])
				#if array is NOT empty exit the function without setting anything
				if [ ! -z $__SWAP_FILESYSTEMS_ARRAY__ ]
				then
					return 0

				else
					#set the abort variable. This occurs when the user edits the swap array and as a result, no valid swap devices get discovered.
					abortCreatingEncryptedSwap='True'
					return 0
				fi
			;;
			[eE])
				#Output the contents of the swap array into a file, then unset the swap array (since items will then be appended).
				for __SWAP_DEVICE__ in ${__SWAP_FILESYSTEMS_ARRAY__[@]}
				do
					echo "$__SWAP_DEVICE__" >> swap_devices
				done
				unset __SWAP_DEVICE__
				unset __SWAP_FILESYSTEMS_ARRAY__

				#Edit/add valid swap enteries
				nano swap_devices

				#Refresh the array of SWAP devices
				counter=0
				while read __SWAP_DEVICE__
				do
					if [[ ! -z `sudo chroot /mnt blkid -t TYPE="swap" -o device $__SWAP_DEVICE__` ]]
					then
						__SWAP_FILESYSTEMS_ARRAY__[$counter]+=$__SWAP_DEVICE__
						counter=$(($counter+1))
					else
						printf '%s : Not a SWAP device!\n' $__SWAP_DEVICE__
					fi
				done < swap_devices

				unset counter
				rm swap_devices

				printf 'New SWAP device(s)\n'
				for i in ${__SWAP_FILESYSTEMS_ARRAY__[@]}
				do
					echo $i
				done
				__subfunct_prep_for_encrypting_swap
			;;
			's')
				#Show all swap devices that are discoverable.
				sudo chroot /mnt blkid -t TYPE="swap" -o device
				__subfunct_prep_for_encrypting_swap
			;;
			'S')
				#Show the current swap devices in the array. Generally this will be the same as output of 's' (the code above this one).
				if [ ! -z ${__SWAP_FILESYSTEMS_ARRAY__[@]} ]
				then
					for i in ${__SWAP_FILESYSTEMS_ARRAY__[@]}
					do
						echo $i
					done
				else
					printf 'No swap devices configured. If you believe this is a mistake\nrun (r)escan to re-populate the swap enteries.\n'
				fi
				__subfunct_prep_for_encrypting_swap
			;;
			'r')
				#Recall the function that populates the array, show what was found, then recall the options menu.
				___DISCOVER_SWAP_FILESYSTEMS___
				for i in ${__SWAP_FILESYSTEMS_ARRAY__[@]}
				do
					echo $i
				done
				__subfunct_prep_for_encrypting_swap
			;;
			'a')
				#Exit funtion and abort setup of swap devices.
				abortCreatingEncryptedSwap='True'
				return 0
			;;
			*)
				printf 'Not an option!\n'
				__subfunct_prep_for_encrypting_swap
			;;
		esac
	}
	__subfunct_prep_for_encrypting_swap

	if [ -z $abortCreatingEncryptedSwap ]
	then
		#Unmount all swap partitions
        	printf '[%bINFO%b] Unmounting all mounted swap devices\n' $YELLOW $NC >&2
        	sudo chroot /mnt swapoff -a

		if [ $___INIT_BACKEND___ == 'update-initramfs' ]
		then
			if [ ! -e /mnt/etc/initramfs-tools/conf.d/resume ]
			then
				#Sometimes the resume file does not exist, if so then it will be created.
				printf '[%bINFO%b] Creating resume file at /mnt/etc/initramfs-tools/conf.d/resume\n' $YELLOW $NC >&2
				sudo chroot /mnt touch /etc/initramfs-tools/conf.d/resume
			fi
		fi

		#Change ownership of crypttab and fstab to the current user.
		sudo chown $USER:$USER /mnt/etc/crypttab
		sudo chown $USER:$USER /mnt/etc/fstab

		#Comment out all lines in /mnt/etc/fstab that has "swap" somewhere in the line.
		printf '[%bINFO%b] Disabling swap entries in /mnt/etc/fstab\n' $YELLOW $NC >&2
		sudo sed -i 's/.*swap.*/#&/' /mnt/etc/fstab

		#Stop the resume file from being constantly edited each time the for-loop runs. Only run once then DONE!
		RESUME_PASSED=0

		#Increase by 1 for each iteration. This handles the naming of the swap mapper name. Ex: swap_0, swap_1, swap_2, etc...
		SWAP_INDEX=0

		#Pretty much the same as the above variable, however it is ONLY used when setting the '_swapfs_label_name' variable (not run if swap device is a logical volume). Ex: swapfs_0, swapfs_1, swapfs_2, etc...
		counter=0

		#Call FUNCT_create_encrypted_swap for each item in the swap array.
		for _initial_swapfs_mount in ${__SWAP_FILESYSTEMS_ARRAY__[@]}
		do
			FUNCT_create_encrypted_swap
			SWAP_INDEX=$(($SWAP_INDEX+1))
			counter=$(($counter+1))
		done

		#Set the ownership of crypttab and fstab to root.
		sudo chown root:root /mnt/etc/crypttab
		sudo chown root:root /mnt/etc/fstab
	else
		printf '[%bNOTICE%b] Aborting swap configuration\n' $YELLOW $NC >&2
	fi
fi
###################################################################################################

function FUNCT_update_changes_to_system(){
	printf '[%bINFO%b] Applying changes to grub configuration.\n' $YELLOW $NC >&2
	#Update grub
	sudo chroot /mnt update-grub

	printf '[%bINFO%b] Updating all initramfs configurations.\n' $YELLOW $NC >&2
	#Update initramfs using the update-initramfs tool.
	if [ $___INIT_BACKEND___ == 'update-initramfs' ]
	then
		sudo chroot /mnt update-initramfs -c -k all
		printf '[%bINFO%b] It is alright that the initramfs updater was not able to find the unlock.key file.\n       This is because the unlock.sh script contains the location of the keyfile relative\n       to the initramfs image and not the primary root filesystem.\n' $YELLOW $NC >&2

	#Edit the /mnt/etc/mkinitcpio.conf file to give initramfs LUKS support, then generate the initramfs.
	elif [ $___INIT_BACKEND___ == 'mkinitcpio' ]
	then
		#Edit the /mnt/etc/mkinitcpio.conf file.
		if [[ `sed -E '/TYPE/d;/crypt/d' <<< $(lsblk --output TYPE $_initial_rootfs_mount)` == 'lvm' ]]
		then
			sudo sed -i 's/^HOOKS.*/HOOKS=\"base udev autodetect keyboard keymap modconf block lvm2 encrypt filesystems\"/' /mnt/etc/mkinitcpio.conf
		else
			sudo sed -i 's/^HOOKS.*/HOOKS=\"base udev autodetect keyboard keymap modconf block encrypt filesystems\"/' /mnt/etc/mkinitcpio.conf
		fi

		for PRESET in `ls -1 /mnt/etc/mkinitcpio.d/ | sed -E 's/.*\/|\.preset//g'`
		do
			sudo chroot /mnt mkinitcpio -p $PRESET
		done
	fi
}
FUNCT_update_changes_to_system

#Unmount partitions
function FUNCT_cleanup(){
	for __MOUNTPOINT__ in ${___PARTITIONS___[@]}
	do
		__MOUNTPOINT__=$(awk -F ':' '{print $2}' <<< $__MOUNTPOINT__)
		if [[ $__MOUNTPOINT__ != '/' ]]
		then
			printf '[%bINFO%b] Unmounting /mnt%s\n' $YELLOW $NC $__MOUNTPOINT__ >&2
			sudo umount /mnt$__MOUNTPOINT__
		fi
	done

	for UNMOUNT in /mnt/proc /mnt/sys /mnt/dev /mnt
	do
		if [ ! -z $_uuid_of_efi_part ] && [ $UNMOUNT == '/mnt/dev' ]
		then
			printf '[%bINFO%b] Unmounting /mnt/boot/efi\n' $YELLOW $NC >&2
			sudo umount /mnt/boot/efi
		fi
		printf '[%bINFO%b] Unmounting %s\n' $YELLOW $NC $UNMOUNT >&2
		sudo umount $UNMOUNT
	done

	#Close the mapped LUKS partitions.
	for __MAPPER__ in ${___MAPPER_NAMES___[@]}
	do
		printf '[%bINFO%b] Closing device: /dev/mapper/%s\n' $YELLOW $NC $__MAPPER__ >&2
		sudo cryptsetup close /dev/mapper/$__MAPPER__
	done
	#Remove Encrypted LUKS file from memory.
	printf '[%bINFO%b] Shreding encrypted LUKS passphrase\n' $YELLOW $NC >&2
	sudo shred /dev/shm/LUKS_PASSPHRASE.gpg

	#End message
	printf '[%bDONE%b] Cleanup complete. Exiting\n' $GREEN $NC >&2
}
FUNCT_cleanup
