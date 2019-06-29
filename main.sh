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

#Ask the user if they have installed cryptsetup on the target device before encrypting.
#If cryptsetup is not installed on the device by the time of encryption, the device will fail to boot.
#And will have to be recovered either from a backup, or by chrooting and installing the package.

function FUNCT_populate_resume_array(){
	#Define the resume array before populating.
	_resume_array=()

	#Define a count variable that corrisponds to the
	#number of iterations in the below while loop.
	local _array_index=0

	while read ___COMPLETED_INSTRUCTIONS___
	do
		#Now, populate the _resume_array array;
		#using the _array_index variable to specify
		#the index.
		_resume_array[$_array_index]=$___COMPLETED_INSTRUCTIONS___

		#Increment the _array_index variable by
		#1 for every iteration.
		_array_index=$(($_array_index+1))
	done < RESUME.log
}
#Check if the RESUME.log file exists, if so call the above function.
if [[ -e RESUME.log ]]
then
	FUNCT_populate_resume_array
else
	printf '[%bINFO%b] No resume log found! Will iterate entire program.\n' $YELLOW $NC >&2
fi

#Get the rootfs partition
function FUNCT_get_rootfs_mountpoint(){
	if [[ ! ${_resume_array[0]} =~ "ROOTFS_partition" ]]
	then
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
		echo "ROOTFS_partition:$_initial_rootfs_mount" >> RESUME.log
	else
		printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[0]} >&2
		_initial_rootfs_mount=${_resume_array[0]##ROOTFS_partition:}
	fi
}
FUNCT_get_rootfs_mountpoint

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

	#Be verbose as to which packages are being checked.
	for REQUIRED_PACKAGES in cryptsetup update-initramfs
	do
		#Search within the chroot for the required packeges.
		sudo chroot /mnt which $REQUIRED_PACKAGES 1>/dev/null

		if [ $? == '0' ]
		then
			printf '[%bOK%b]   %s is installed on %s\n' $GREEN $NC $REQUIRED_PACKAGES $_initial_rootfs_mount >&2
		else
			printf '[%bFAIL%b] %s is NOT installed on %s\n' $RED $NC $REQUIRED_PACKAGES $_initial_rootfs_mount >&2
			sudo umount /mnt
			exit 1
		fi
	done
}
FUNCT_verify_required_packages

#Check if /boot/grub/x86_64-efi exists, if so
#determine the mountpoint of the EFI partition.
#and verify that it is a valid efi partition.
function FUNCT_detect_partition_table_type(){
	if [ ! -e /mnt/etc/fstab ]
	then
		printf '[%bFAIL%b] Mounted successfully, but the partition does not contain an fstab file\n' $RED $NC >&2
		sudo umount /mnt
		exit 1
	fi

	#Has grub been installed with EFI support?
	if [ -d '/mnt/boot/grub/x86_64-efi' ]
	then
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

			#Check /mnt/boot/efi, basic check to see if the files in there exist or not.
			local counter=0
			for EFI_FILES in '/mnt/boot/efi/EFI/boot/BOOTX64.EFI' '/mnt/boot/efi/EFI/boot/fbx64.efi'
			do
				if [ -e $EFI_FILES ]
				then
					printf 'Verified existence of: %s\n' $EFI_FILES
				else
					printf '%s: Does not exist\n' $EFI_FILES
					counter=$(($counter+1))
				fi
			done

			#Did one or more critical EFI files go undiscovered?
			if [[ $counter -gt '0' ]]
			then
				printf '[%bWARN%b] %s: partition is deemed invalid do to above errors\n         Will use DOS instead\n' $RED $NC $_uuid_of_efi_part >&2
				unset _uuid_of_efi_part
			else
				printf '[%bOK%b]   %s: is a valid EFI partition\n' $GREEN $NC $_uuid_of_efi_part >&2
			fi

			#Unmount the mounted EFI partition
			printf '[%bINFO%b] Unmounting /mnt/boot/efi\n' $YELLOW $NC >&2
			sudo umount /mnt/boot/efi
		fi
	else
		printf '[%bINFO%b] Partition table type is DOS\n' $YELLOW $NC >&2
	fi

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
function FUNCT_create_gpg_key(){
	#Generate GPG key if key does not already exist.
	if [[ ! `gpg --list-keys | grep 'ReallySecureShell\@github\.com'` =~ ReallySecureShell\@github\.com ]]
	then
		#Create the random passphrase for the keypair.
		__key_passphrase__=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | sha256sum | sed 's/\ -//')

		printf '[%bINFO%b] Creating GPG keyfile template\n' $YELLOW $NC >&2
		#Create keyfile template. This file is generated 
		cat << __END_OF_KEY_TEMPLATE__ > key.template
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Name-Real: ReallySecureShell
Name-Email: ReallySecureShell@github.com
Expire-Date: 0
Passphrase: $__key_passphrase__
__END_OF_KEY_TEMPLATE__

		printf '[%bINFO%b] Generating GPG key\n' $YELLOW $NC >&2
		#Generate the gpg key
		gpg --batch --gen-key key.template

		#We are editing the GPG user configs because otherwise we will be given an ioctl error when trying to decrypt the LUKS passphrase.
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

	elif [[ `gpg --list-keys | grep 'ReallySecureShell\@github\.com'` =~ ReallySecureShell\@github\.com ]]
	then
		#If this condition is true then that means that the script already ran.
		printf '[%bINFO%b] Skipping generation of GPG key. Key already exists\n' $YELLOW $NC >&2

		#Attempt to obtain key password.	
		if [ -e key.template ]
		then
			printf '[%bINFO%b] Obtaining key passphrase from key.template\n' $YELLOW $NC >&2

			__key_passphrase__=$(sed -n '/Passphrase: /{
			s/Passphrase: //
			p
			}' key.template)
		else
			printf '[%bERROR%b] key.template does not exist. Cannot obtain the password for the key\n' $RED $NC >&2
			exit 1
		fi
	fi
}
FUNCT_create_gpg_key

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
			gpg --armor -er 'ReallySecureShell@github.com' --passphrase $__key_passphrase__ -o /dev/shm/LUKS_PASSPHRASE.gpg << __END_OF_PASSPHRASE__
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
	if [[ ${_resume_array[1]} != "e2fsck" ]]
	then
		#Run e2fsck on the partition provided by the user
		sudo e2fsck -fy $1
		echo "e2fsck" >> RESUME.log
	else
		printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[1]} >&2
	fi

	if [[ ${_resume_array[2]} != "resize2fs" ]]
	then
		#Then resize the disk
		sudo resize2fs -M $1
		echo "resize2fs" >> RESUME.log
	else
		printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[2]} >&2
	fi

	if [[ ${_resume_array[3]} != "cryptsetup-reencrypt" ]]
	then
		#Add encryption to the specified drive.
		echo -n `gpg --quiet -dr ReallySecureShell@github.com --passphrase $__key_passphrase__ /dev/shm/LUKS_PASSPHRASE.gpg` | sudo cryptsetup-reencrypt --key-file=- --new --type=luks1 --reduce-device-size 4096S $1
		echo "cryptsetup-reencrypt" >> RESUME.log
	else
		printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[3]} >&2
	fi

	if [[ ! ${_resume_array[4]} =~ "cryptsetup-open" ]]
        then
                #Ask the user what the mapper name for the root filesystem should be.
		read -p 'Root filesystem mapper name [rootfs]: '

		#If input is left blank, then set the mapper name to 'rootfs'.
		case $REPLY in
        		"")
                		_rootfs_mapper_name='rootfs'
        		;;
       			*)
                		_rootfs_mapper_name=$REPLY
        		;;
		esac

		#Open the root filesystem as a mapped device.
		echo -n `gpg --quiet -dr ReallySecureShell@github.com --passphrase $__key_passphrase__ /dev/shm/LUKS_PASSPHRASE.gpg` | sudo cryptsetup --key-file=- open $1 $_rootfs_mapper_name
		echo "cryptsetup-open:$_rootfs_mapper_name" >> RESUME.log
        else
 		printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[4]} >&2
		_rootfs_mapper_name=${_resume_array[4]##cryptsetup-open:}
        fi

	if [[ ${_resume_array[5]} != "resize2fs_2" ]]
        then
                #Size the partition back to max size.
                sudo resize2fs /dev/mapper/$_rootfs_mapper_name
                echo "resize2fs_2" >> RESUME.log
        else
                printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[5]} >&2
        fi
}
FUNCT_initial_drive_encrypt $_initial_rootfs_mount

#Chroot into the encrypted filesystem.
function FUNCT_setup_mount(){
	#Since opening the device can be skipped in the above function,
	#check if the mountpoint exists, if not, open the encrypted
	#filesystem.
	if [[ ! -b $1 ]]
	then
		printf '[%bINFO%b] %s not yet opened! Opening it now.\n' $YELLOW $NC $2 >&2
		echo -n `gpg --quiet -dr ReallySecureShell@github.com --passphrase $__key_passphrase__ /dev/shm/LUKS_PASSPHRASE.gpg` | sudo cryptsetup --key-file=- open $2 $_rootfs_mapper_name
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
}
FUNCT_setup_mount "/dev/mapper/$_rootfs_mapper_name" $_initial_rootfs_mount

function FUNCT_add_rootfs_to_crypttab(){
	#Get the UUID of the root filesystem.
	#Note this is NOT the mapper UUID but
	#the UUID of the actual encrypted
	#partition.
	local _sed_compatible_rootfs_mount_name=$(sed 's/\//\\\//g' <<< $_initial_rootfs_mount)

	local _rootfs_uuid=$(sed -n '/'"$_sed_compatible_rootfs_mount_name"'/{
        s/^.*:\ //
        s/\ .*//
        s/UUID\=//
        s/[\"]//g
        p
        }' <<< `sudo chroot /mnt blkid`)

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

	#Now write the entry for the root filesystem in /etc/crypttab
	local _crypttab_rootfs_entry="$_rootfs_mapper_name UUID=$_rootfs_uuid none luks$discard,keyscript=/etc/initramfs-tools/hooks/unlock.sh"

	#Take own of the crypttab file so we can write to it.
	sudo chown $USER:$USER /mnt/etc/crypttab

	#Append the value of the above variable into /etc/crypttab
	echo "$_crypttab_rootfs_entry" >> /mnt/etc/crypttab

	#Set crypttab to be owned by root.
	sudo chown root:root /mnt/etc/crypttab

	#Unset the discard variable
	unset discard
}
if [[ ${_resume_array[6]} != "crypttab_rootfs_entry" ]]
then
	FUNCT_add_rootfs_to_crypttab $_rootfs_mapper_name $_initial_rootfs_mount
	echo "crypttab_rootfs_entry" >> RESUME.log
else
	printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[6]} >&2
fi

function FUNCT_write_unlock_script(){
	#Create key used for unlocking the root filesystem in initramfs.
	printf '[%bINFO%b] Generating keyfile from /dev/urandom\n' $YELLOW $NC >&2
	dd if=/dev/urandom count=4 bs=512 of=unlock.key

	#Add new keyfile to LUKS as an additional key.
	printf '[%bINFO%b] Adding keyfile to %s\n' $YELLOW $NC $_initial_rootfs_mount >&2
	echo -n `gpg --quiet -dr ReallySecureShell@github.com --passphrase $__key_passphrase__ /dev/shm/LUKS_PASSPHRASE.gpg` | sudo cryptsetup --key-file=- luksAddKey $_initial_rootfs_mount unlock.key

	#Move keyfile into /mnt/etc/initramfs-tools/scripts/, this will make sure the
	#keyfile is picked-up by initramfs as a required file, and therefore
	#will be included in the initramfs image.
	printf '[%bINFO%b] Moving keyfile into initramfs configuration\n' $YELLOW $NC >&2
	sudo mv unlock.key /mnt/etc/initramfs-tools/scripts/

	#Generate unlock.sh keyfile for initramfs.
	printf '[%bINFO%b] Creating unlock.sh script for initramfs\n' $YELLOW $NC >&2
	sudo touch /mnt/etc/initramfs-tools/hooks/unlock.sh

	#Change ownership of /mnt/etc/initramfs-tools/hooks/unlock.sh
	sudo chown $USER:$USER /mnt/etc/initramfs-tools/hooks/unlock.sh

	cat << _unlock_script_file_data > /mnt/etc/initramfs-tools/hooks/unlock.sh
#!/bin/sh

cat /scripts/unlock.key

exit 0
_unlock_script_file_data

	#Set ownership for unlock.sh back to root and set unlock.key to be owned by root also.
	sudo chown root:root /mnt/etc/initramfs-tools/hooks/unlock.sh
	sudo chown root:root /mnt/etc/initramfs-tools/scripts/unlock.key

	#Set restrictive permissions on the keyscript and keyfile.
	printf '[%bINFO%b] Applying restrictive permissions to the key and script files\n' $YELLOW $NC >&2
	sudo chroot /mnt chmod 100 /etc/initramfs-tools/hooks/unlock.sh
	sudo chroot /mnt chmod 400 /etc/initramfs-tools/scripts/unlock.key
}
if [[ ${_resume_array[7]} != "unlock.sh" ]]
then
        FUNCT_write_unlock_script
        echo "unlock.sh" >> RESUME.log
else
        printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[7]} >&2
fi

function FUNCT_modify_grub_configuration(){
	#Enable cryptodisks for grub.
	sudo sed -Ei 's/GRUB_CMDLINE_LINUX="(.*?)\"/&\nGRUB_ENABLE_CRYPTODISK=y/' /mnt/etc/default/grub

	#Have grub preload the required modules for luks and cryptodisks.
	sudo sed -Ei 's/GRUB_ENABLE_CRYPTODISK=y/&\nGRUB_PRELOAD_MODULES="luks cryptodisk"/' /mnt/etc/default/grub

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
		sudo chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader=ubuntu --boot-directory=/boot/efi/EFI/ubuntu --modules="part_gpt part_msdos" --recheck
		sudo chroot /mnt grub-mkconfig -o /boot/efi/EFI/ubuntu/grub/grub.cfg
	else
		#Remove partition numbers from the end of the root device.
        	local _grub_install_device=${_initial_rootfs_mount%%[0-9]}

		#Install grub with i386 architecture support ONLY.
        	printf '[%bINFO%b] Installing grub to %s\n' $YELLOW $NC $_grub_install_device >&2
		sudo chroot /mnt grub-install --modules="part_gpt part_msdos" --recheck $_grub_install_device
	fi
}
if [[ ${_resume_array[8]} != "grub_config" ]]
then
        FUNCT_modify_grub_configuration
        echo "grub_config" >> RESUME.log
else
        printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[8]} >&2
fi

function FUNCT_create_encrypted_swap(){
	#See if any SWAP devices are present before asking which one the user wants to encrypt.
	if [[ -z `sudo chroot /mnt blkid -t TYPE="swap"` ]]
	then
		printf '[%bINFO%b] No swap filesystem(s) present\n' $YELLOW $NC >&2

		#If no swap devices are present, exit function.
		return 0
	fi

	#Help the user choose the swap partition.
	sudo chroot /mnt blkid -t TYPE="swap"

	function __subfunct_prep_for_encrypting_swap(){
		#Tell the user they need to enter the path to the swap device.
		printf '[%bINFO%b] Enter the location of the swap device\n' $YELLOW $NC >&2

		#Ask the user for the swap partition to encrypt.
        	read -p 'Partition containing the SWAP filesystem [none]: '

		case $REPLY in
			"")
				function __subfunct_confirm_to_not_encrypt_swap(){
					read -p 'Keep swap partition unencrypted? (y/n): '

					case $REPLY in
						y|Y)
							abortCreatingEncryptedSwap='true'
							return 0
						;;
						n|N)
							__subfunct_prep_for_encrypting_swap
						;;
					esac
				}
				__subfunct_confirm_to_not_encrypt_swap

				return 0
			;;
			*)
				if [[ -z `sudo chroot /mnt blkid -t TYPE="swap" $REPLY` ]]
                		then
					printf '[%bWARN%b] Not a swap device!\n' $RED $NC >&2
					__subfunct_prep_for_encrypting_swap
				else
					_initial_swapfs_mount=$REPLY
				fi
			;;
		esac

		if [[ ! -z $abortCreatingEncryptedSwap ]]
		then
			return 0
		fi

		#Ask what the LABEL name for the swap device should be.
        	read -p 'Swap filesystem label name [swapfs]: '

        	case $REPLY in
                	"")
                       		_swapfs_label_name='swapfs'
                	;;
                	*)
                        	_swapfs_label_name=$REPLY
                	;;
        	esac
	}
	__subfunct_prep_for_encrypting_swap

	if [[ ! -z $abortCreatingEncryptedSwap ]]
	then
		printf '[%bNOTICE%b] Aborting the creation of the encrypted swap partition\n' $YELLOW $NC >&2
		unset abortCreatingEncryptedSwap
		return 0
	fi

	#Unmount all swap partitions
        printf '[%bINFO%b] Unmounting all mounted swap devices\n' $YELLOW $NC >&2
        sudo chroot /mnt swapoff -a

	#Create a blank filesystem 1M in size at the start of the swap partition, this is so we can set a stable name to the swap partition.
	printf '[%bINFO%b] Creating blank ext2 filesystem at the start of %s\n' $YELLOW $NC $_initial_swapfs_mount >&2
	sudo chroot /mnt mkfs.ext2 -L $_swapfs_label_name $_initial_swapfs_mount 1M <<< "y"

	#Change ownership of /mnt/etc/crypttab
	sudo chown $USER:$USER /mnt/etc/crypttab

	#Add entry in crypttab for our encrypted swapfs.
	printf '[%bINFO%b] Adding swap entry to /mnt/etc/crypttab\n' $YELLOW $NC >&2
	echo "swap LABEL=$_swapfs_label_name /dev/urandom swap,offset=2048,cipher=aes-xts-plain64,size=512" >> /mnt/etc/crypttab

	#Change ownership back to root
	sudo chown root:root /mnt/etc/crypttab

	#Comment out all lines in /mnt/etc/fstab that has "swap" somewhere in the line.
	printf '[%bINFO%b] Disabling swap entries in /mnt/etc/fstab\n' $YELLOW $NC >&2
	sudo sed -i 's/.*swap.*/#&/' /mnt/etc/fstab

	#Change ownership of /mnt/etc/fstab
	sudo chown $USER:$USER /mnt/etc/fstab

	#Append new swapfs entry into /mnt/etc/fstab
	printf '[%bINFO%b] Adding swap entry to /mnt/etc/fstab\n' $YELLOW $NC >&2
	echo "/dev/mapper/swap none swap sw 0 0" >> /mnt/etc/fstab

	#Reset ownership on /mnt/etc/fstab
	sudo chown root:root /mnt/etc/fstab

	#If the resume file does not exist, create it.
	if [ ! -e /mnt/etc/initramfs-tools/conf.d/resume ]
	then
		printf '[%bINFO%b] Creating resume file at /mnt/etc/initramfs-tools/conf.d/resume\n' $YELLOW $NC >&2
		sudo chroot /mnt touch /etc/initramfs-tools/conf.d/resume
	fi

	#Edit the RESUME file found at /etc/initramfs-tools/conf.d/resume
	#This is so the resume function will always point to our fixed-named swap partition.
	printf '[%bINFO%b] Modifying /mnt/etc/initramfs-tools/conf.d/resume\n' $YELLOW $NC >&2
	sudo sed -i 's/.*/RESUME=LABEL='"$_swapfs_label_name"'/' /mnt/etc/initramfs-tools/conf.d/resume
}
if [[ ${_resume_array[9]} != "encrypt_swap" ]]
then
	FUNCT_create_encrypted_swap
	echo "encrypt_swap" >> RESUME.log
else
        printf '[%bINFO%b] The %s command was already run! Skipping.\n' $YELLOW $NC ${_resume_array[9]} >&2
fi

function FUNCT_update_changes_to_system(){
	printf '[%bINFO%b] Applying changes to grub configuration.\n' $YELLOW $NC >&2
	#Update grub
	sudo chroot /mnt update-grub

	printf '[%bINFO%b] Updating all initramfs configurations.\n' $YELLOW $NC >&2

	#Update all initramfs filesystems
	sudo chroot /mnt update-initramfs -c -k all
	printf '[%bINFO%b] It is alright that the initramfs updater was not able to find the unlock.key file.\n       This is because the unlock.sh script contains the location of the keyfile relative\n       to the initramfs image and not the primary root filesystem.\n' $YELLOW $NC >&2
}
FUNCT_update_changes_to_system

#Unmount partitions
function FUNCT_cleanup(){
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
	#Close the LUKS device
	printf '[%bINFO%b] Closing mapped ROOT device: /dev/mapper/%s\n' $YELLOW $NC $_rootfs_mapper_name >&2
	sudo cryptsetup close /dev/mapper/$_rootfs_mapper_name

	#Remove Encrypted LUKS file from memory.
	printf '[%bINFO%b] Shreding encrypted LUKS passphrase\n' $YELLOW $NC >&2
	sudo shred /dev/shm/LUKS_PASSPHRASE.gpg

	#End message
	printf '[%bDONE%b] Cleanup complete. Exiting\n' $GREEN $NC >&2
}
FUNCT_cleanup
