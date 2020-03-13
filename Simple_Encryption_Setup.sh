#!/usr/bin/env bash

help(){
cat << END_OF_HELP
./SimpleEncryptionSetup.sh -fvh -p 'partition1:mountpoint1[ partitionN:mountpointN]' -r root-partition [-e efi-partition {-d DIR}]

-p, --partitions 'partition1:mountpoint1[ partitionN:mountpointN]'  Specify the partition(s) to encrypt.
                                                                    Example: '/dev/sda1:/ /dev/sda2:/home'
                                                                    
-r, --root <root-partition>                                         The root partition. This can be either
                                                                    /dev/sd*, or if using LVM /dev/mapper/<root-name>.
                                                                    Example: /dev/sda1
                                                                    
-e, --efi <efi-partition>                                           Specify the EFI partition.
                                                                    Example: /dev/sda3
                                                                    
    -d, --efi-path <DIR>                                            The directory in /mnt/boot/efi/EFI/ where 
                                                                    grub will be installed. This directory MUST 
                                                                    already exist. If lost, 'ls' the directories 
                                                                    in said EFI path and find a file named grubx64.efi, 
                                                                    if the directory contains that file it's probably 
                                                                    the right one. This directory is also used as the 
                                                                    bootloader-id.
                                                                    Example: ubuntu
                                                                    
-f, --fake                                                          Do not make modifications to the system. This is used
                                                                    to check the output for errors *before* modifying
                                                                    the system.

-v, --version                                                       Print version information then exit.
                                                                    
-h, --help                                                          Print this help page then exit.
END_OF_HELP
exit $1
}

options=$(getopt -o p:r:e:d:fvh -l partitions:,root:,efi:,efi-path:,fake,version,help -n "$0" -- "$@") || help '1'
eval set -- "$options"

while [[ $1 != -- ]]
do
	case $1 in
		-p|--partitions)
			PARTITIONS=($(awk -F ':| ' '{ for ( i = 1; i <= NF; i=i+2 ) if ( !seen[$i]++ ) printf "%s ",$i }' <<< $2))

			MOUNTPOINTS=($(awk -F ':| ' '{ for ( i = 2; i <= NF; i=i+2 ) if ( !seen[$i]++ ) printf "%s ",$i }' <<< $2))

			VOLUME_NAMES=()
			
			# Checks to see if a colon(:) was specified in each field, e.g. /dev/sda1:/ /dev/sda2:/home
			for syntaxError in $(grep -Eo '(^|\b )([^:]*)(\b |$)' <<< $2)
			do
                if [ ! -z $syntaxError ]
                then
                    printf '[ERROR] Syntax error at: %s\n' $syntaxError
                    syntaxErrorsHaveOccured=true
                fi
			done
			
			if [ ! -z $syntaxErrorsHaveOccured ]
			then
                exit 1
			fi

			for key in ${!PARTITIONS[@]}
			do
				if [ ! -b ${PARTITIONS[$key]} ]
				then
					printf '[ERROR] %s is not a block device\n' ${PARTITIONS[$key]}
					errorWhenPerformingCheck=true
				elif [[ ! $(sudo file -sL ${PARTITIONS[$key]}) =~ ext[2|3|4] ]]
				then
					printf '[ERROR] %s is not an EXT* filesystem\n' ${PARTITIONS[$key]}
					errorWhenPerformingCheck=true
				fi

				if [[ ${MOUNTPOINTS[$key]} == "/" ]]
				then
					VOLUME_NAMES[$key]="root"
				else
					VOLUME_NAMES[$key]=$(echo ${MOUNTPOINTS[$key]} | sed 's|^/||;s|/|_|g')
				fi
			done

			if [ ! -z $errorWhenPerformingCheck ]
			then
				exit 1
			fi

			for key in ${!PARTITIONS[@]}
			do
				printf 'PARTITION [%s]:\n' $key
				printf '\tSelected Partition: %s\n' ${PARTITIONS[$key]}
				printf '\tSize: %s\n' $(lsblk --raw --noheadings --output SIZE ${PARTITIONS[$key]})
				printf '\tMountpoint: %s\n' ${MOUNTPOINTS[$key]}
				printf '\tLogical Name: %s\n' ${VOLUME_NAMES[$key]}
			done

			partitionsWereSpecified=true
			shift 2
		;;
		-r|--root)
			if [ ! -b $2 ]
			then
				printf '[ERROR] %s is not a block device\n' $2
				exit 1
			elif [[ ! $(sudo file -sL $2) =~ ext[2|3|4] ]]
			then
				printf '[ERROR] %s is not an EXT* filesystem\n' $2
				exit 1
			else
				printf '[INFO] root partition: %s\n' $2
				rootFileSystem=$2
			fi
			shift 2
		;;
		-e|--efi)
			if [ ! -b $2 ]
			then
				printf '[ERROR] %s is not a block device\n' $2
				exit 1
            elif [[ $(sudo file -sL $2 | grep 'FAT (32 bit)' || echo "false") == "false" ]]
            then
                printf '[ERROR] %s is not a FAT formatted partition\n' $2
                exit 1
			else
				printf '[INFO] EFI partition: %s\n' $2
				EFIPartition=$2
			fi
			shift 2
		;;
		-d|--efi-path)
            EFIPath=$2
            shift 2
        ;;
		-f|--fake)
			operationGeneralDeny=true
			fakeMount='-f'
			shift 1
		;;
		-v|--version) printf 'SimpleEncryptionSetup v2.0\n' ; exit 0 ; shift 1 ;;
		-h|--help) help '0' ; shift 1 ;;
		*) help '1' ;;
	esac
done

if [ -z $partitionsWereSpecified ]
then
	printf '[ERROR] Use of the -p flag is required! No partition(s) specified. Unable to continue.\n'
	exit 1
elif [ -z $rootFileSystem ]
then
	printf '[ERROR] Use of the -r flag is required! No root filesystem specified. Unable to continue.\n'
	exit 1
elif [[ -z $EFIPartition ]] && [[ ! -z $EFIPath ]]
then
    printf '[ERROR] Cannot specify the distribution EFI path without specifying the EFI partition\n'
    exit 1
elif [[ ! -z $EFIPartition ]] && [[ -z $EFIPath ]]
then
    printf '[ERROR] Cannot specify the EFI partition without specifying the distribution EFI path\n'
    exit 1
else
	unset partitionsWereSpecified
fi

for i in ${PARTITIONS[@]}
do
	if [ $i == $rootFileSystem ]
	then
		printf 'The root filesystem %s will be encrypted\n' $rootFileSystem
		rootFilesystemIsEncrypted=true
	fi
done

function checkCurrentMountStatusOfMnt(){
	mountpoint -q /mnt

    if [ $? == 0 ]
    then
        printf '[WARN] /mnt is a mountpoint. Attempting to unmount\n'
        sudo umount --recursive /mnt

        mountpoint -q /mnt
        if [ $? == 1 ] 
        then
            printf '[INFO] Unmount Successful\n'
        else
			printf '[ERROR] Unmount Unsuccessful\n'
			exit 1
        fi  
	fi
}
checkCurrentMountStatusOfMnt

function promptForVolumePassword(){
	PASSPHRASE=()

	read -sp 'Create LUKS passphrase: ' PASSPHRASE[0]
	printf '\n'

	read -sp 'Verify passphrase: ' PASSPHRASE[1]
	printf '\n'

	if [[ ${PASSPHRASE[0]} != ${PASSPHRASE[1]} ]]
	then
		printf 'Passphrases do not match\n'
		promptForVolumePassword
	elif [[ -z ${PASSPHRASE[0]} ]]
	then
		printf 'Passphrase must not be empty\n'
		promptForVolumePassword
	fi
	
	printf '%s' "${PASSPHRASE[0]}" > luksPassphrase.txt
}
promptForVolumePassword

function createKeyfile(){
	printf '[INFO] Creating keyfile: unlock.key\n'
	if [ -z $operationGeneralDeny ]
	then
        dd if=/dev/urandom bs=4096 count=1 2>/dev/null | base64 | xargs -i printf '%s' {} | sudo tee unlock.key 1>/dev/null
	fi
}
createKeyfile

function encryptPartitions(){
    for counter in ${!PARTITIONS[@]}
    do
        printf '[INFO] Encrypting %s\n' ${PARTITIONS[$counter]}
    
        if [ -z $operationGeneralDeny ]
        then
            sudo e2fsck -fy ${PARTITIONS[$counter]}
            sudo resize2fs -M ${PARTITIONS[$counter]}
            
            printf '%s' $(cat unlock.key) | sudo cryptsetup-reencrypt --key-file=- --new --type=luks1 --reduce-device-size 4096S ${PARTITIONS[$counter]}
            
            printf '%s' $(cat unlock.key) | sudo cryptsetup --key-file=- open ${PARTITIONS[$counter]} ${VOLUME_NAMES[$counter]}
            sudo resize2fs /dev/mapper/${VOLUME_NAMES[$counter]}
            
            if [ ${VOLUME_NAMES[$counter]} == 'root' ]
            then
                printf '%s' $(cat unlock.key) | sudo cryptsetup --key-file=- luksAddKey ${PARTITIONS[$counter]} luksPassphrase.txt
            fi
        fi
    done
}
encryptPartitions

function mountPartitions(){
    if [ ! -z $rootFilesystemIsEncrypted ] && [ -z $operationGeneralDeny ]
    then
        printf '[INFO] Mounting /dev/mapper/root into /mnt\n'
        sudo mount /dev/mapper/root /mnt
    else
        printf '[INFO] Mounting %s into /mnt\n' $rootFileSystem
        sudo mount $rootFileSystem /mnt
    fi
    
    for bind in dev sys proc
    do
        printf 'Binding /%s into /mnt/%s\n' $bind $bind
        sudo mount $fakeMount --bind /$bind /mnt/$bind
    done

    IFS=$'\n'
    sortedMountpoints=($(sort <<< "${MOUNTPOINTS[*]}"))
    sortedVolumeNames=($(sort <<< "${VOLUME_NAMES[*]}"))
    allMountpoints=($(sort <<< $(findmnt --noheadings --tab-file /mnt/etc/fstab --type ext4,ext3,ext2,vfat --output TARGET | grep '[^/]$')))

    for counter in ${!allMountpoints[@]}
    do
        for encryptedIndex in "${!sortedMountpoints[@]}"
        do
            if [[ ${allMountpoints[$counter]} == ${sortedMountpoints[$encryptedIndex]} ]]
            then
                printf '[INFO] Mounting encrypted partition: /dev/mapper/%s into: /mnt%s\n' ${sortedVolumeNames[$encryptedIndex]} ${sortedMountpoints[$encryptedIndex]}
                if [ -z $operationGeneralDeny ]
                then
                    sudo mount /dev/mapper/${sortedVolumeNames[$encryptedIndex]} /mnt${sortedMountpoints[$encryptedIndex]}
                fi
                break
            fi
        done

        if [[ ${allMountpoints[$counter]} != ${sortedMountpoints[$encryptedIndex]} ]]
        then
            printf '[INFO] Mounting normal partition: %s into: /mnt%s\n' $(findmnt --evaluate --noheadings --tab-file /mnt/etc/fstab --output SOURCE ${allMountpoints[$counter]}) ${allMountpoints[$counter]}
            if [ -z $operationGeneralDeny ]
            then
                sudo mount $(findmnt --evaluate --noheadings --tab-file /mnt/etc/fstab --output SOURCE ${allMountpoints[$counter]}) /mnt${allMountpoints[$counter]}
            fi
        fi
    done
    unset IFS
}
mountPartitions

function configureCrypttab(){
	if [ ! -e /mnt/etc/crypttab ]
	then
		printf '[INFO] Creating /mnt/etc/crypttab as it does not exist\n'
		printf '****This might mean cryptsetup is not installed on the target system****\n'
		
        sudo touch /mnt/etc/crypttab
        sudo chmod 644 /mnt/etc/crypttab
	fi

	printf '[INFO] Appending the following entries to /mnt/etc/crypttab:\n'
	for counter in ${!PARTITIONS[@]}
	do
		UUID=$(lsblk --nodeps --noheadings --output UUID ${PARTITIONS[$counter]})
		
        if [ ${VOLUME_NAMES[$counter]} == 'root' ]
        then
            printf '\t[%s]: root UUID=%s none luks,keyscript=/etc/initramfs-tools/hooks/unlock.sh\n' $counter $UUID
            if [ -z $operationGeneralDeny ]
            then
                echo "root UUID=$UUID none luks,keyscript=/etc/initramfs-tools/hooks/unlock.sh" | sudo tee --append /mnt/etc/crypttab 1>/dev/null
            fi
        else
            printf '\t[%s]: %s UUID=%s /etc/initramfs-tools/scripts/unlock.key luks\n' $counter ${VOLUME_NAMES[$counter]} $UUID
            if [ -z $operationGeneralDeny ]
            then
                echo "${VOLUME_NAMES[$counter]} UUID=$UUID /etc/initramfs-tools/scripts/unlock.key luks" | sudo tee --append /mnt/etc/crypttab 1>/dev/null
            fi
        fi
	done
}
configureCrypttab

function configureFSTAB(){
	printf '[INFO] Modifying /mnt/etc/fstab:\n'

	for counter in ${!MOUNTPOINTS[@]}
	do
		for mountpoint in ${MOUNTPOINTS[$counter]}
		do
            printf '\t[%s]: %s\n' $counter "$(grep "^[^#].*$mountpoint[^_/A-Za-z0-9]" /mnt/etc/fstab | sed -E "s|^[^#].*$mountpoint[^_/A-Za-z0-9]|/dev/mapper/${VOLUME_NAMES[$counter]} $mountpoint |g")"
			if [ -z $operationGeneralDeny ]
			then
				sudo sed -Ei "s|^[^#].*$mountpoint[^_/A-Za-z0-9]|/dev/mapper/${VOLUME_NAMES[$counter]} $mountpoint |g" /mnt/etc/fstab
			fi
		done
	done
}
configureFSTAB

function configureAutoDecryptionInInitramfs(){
    printf '[INFO] Configuring initramfs to automatically unlock encrypted partition(s)\n'

    printf '[INFO] Creating /mnt/etc/initramfs-tools/hooks/unlock.sh\n'
    
    printf '[INFO] Moving unlock.key into /mnt/etc/initramfs-tools/scripts/unlock.key\n'

    if [ -z $operationGeneralDeny ]
    then
        cat << EOF | sudo tee /mnt/etc/initramfs-tools/hooks/unlock.sh 1>/dev/null
#!/bin/sh
cat /scripts/unlock.key

exit 0
EOF
        sudo chmod 100 /mnt/etc/initramfs-tools/hooks/unlock.sh
        
        sudo chmod 400 unlock.key
        sudo mv unlock.key /mnt/etc/initramfs-tools/scripts/unlock.key
    fi
}
configureAutoDecryptionInInitramfs

function modifyGrub(){
	printf '[INFO] Appending the following lines to /mnt/etc/default/grub:\n'
	printf '\t[0]: GRUB_ENABLE_CRYPTODISK=y\n'

	if [ -z $operationGeneralDeny ]
	then
		cat << EOF | sudo tee --append /mnt/etc/default/grub 1>/dev/null
# Options for enabling/working with encrypted volumes.
GRUB_ENABLE_CRYPTODISK=y
EOF
	fi

	# If system uses EFI, tell grub to install for the x86_64-efi platform.
	if [ ! -z $EFIPartition ]
    then
        printf '\t[1]: GRUB_PRELOAD_MODULES="part_gpt luks cryptodisk"\n'
        if [ -z $operationGeneralDeny ]
        then
            cat << EOF | sudo tee --append /mnt/etc/default/grub 1>/dev/null
GRUB_PRELOAD_MODULES="part_gpt luks cryptodisk"
EOF
        fi
        
        printf '[INFO] Installing GRUB for x86_64-efi\n'

        if [ ! -e /mnt/boot/efi/EFI/$EFIPath ]
        then
            printf '[WARN] The specified EFI path: /mnt/boot/efi/EFI/%s does not exist. Cannot install and configure GRUB\n' $EFIPath
            printf 'The commands needed to install and configure GRUB for the EFI system will be written to Install_and_Configure_GRUB.txt in the present directory\n'
            cat << EOF > Install_and_Configure_GRUB.txt
# chroot into the appropriate system and run the following:
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=<name-of-last-directory-without-slashes> --boot-directory=/boot/efi/<PATH> --recheck
grub-mkconfig -o /boot/efi/<PATH>/grub/grub.cfg
EOF
            sleep 5
            return 1
        fi
        
        printf '[INFO] EFI boot directory: /boot/efi/EFI/%s\n' $EFIPath
        printf '[INFO] GRUB configuration path: /boot/efi/EFI/%s/grub/grub.cfg\n' $EFIPath
        
        if [ -z $operationGeneralDeny ]
        then
            # Reinstall grub for x86_64-efi (even though it probably already is x86_64-efi)
            sudo chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=$EFIPath --boot-directory=/boot/efi/EFI/$EFIPath --recheck
            
            # Generate new grub configuration
            sudo chroot /mnt grub-mkconfig --output=/boot/efi/EFI/$EFIPath/grub/grub.cfg
        fi
        
    # If not using EFI
    elif [ -z $EFIPartition ]
    then
        printf '\t[1]: GRUB_PRELOAD_MODULES="part_msdos luks cryptodisk"\n'
        if [ -z $operationGeneralDeny ]
        then
            cat << EOF | sudo tee --append /mnt/etc/default/grub 1>/dev/null
GRUB_PRELOAD_MODULES="part_msdos luks cryptodisk"
EOF
        fi
        
        printf '[INFO] Installing GRUB for i386-pc\n'
        
        # If not using EFI and system uses LVM, get what physical device the logical root partition is a part of, and install grub there.
        isSystemLVM=$(lsblk --noheadings --nodeps --output TYPE $rootFileSystem | grep -o 'lvm')
        if [[ $isSystemLVM == 'lvm' ]]
        then
            local grubInstallDestination=$(sudo lvs --noheadings --options devices $rootFileSystem 2>/dev/null | sed -E 's/^  //;s/[0-9]+.*$//')
        
        # If not using EFI and system does not use LVM, install grub normally.
        else
            local grubInstallDestination=${rootFileSystem%%[0-9]}
        fi
        
        printf '[INFO] Installing GRUB to %s\n' $grubInstallDestination
        if [ -z $operationGeneralDeny ]
        then
            sudo chroot /mnt grub-install --target=i386-pc --recheck $grubInstallDestination
        fi
    fi
}
modifyGrub

function updateGrubAndInitramfs(){
    printf '[INFO] Updating grub and regenerating initramfs image(s)\n'
    if [ -z $operationGeneralDeny ]
    then
        sudo chroot /mnt update-grub
        sudo chroot /mnt update-initramfs -c -k all
    fi
}
updateGrubAndInitramfs

function createLUKSHeaderBackups(){
    if [ -z $operationGeneralDeny ]
    then
        mkdir headers/
    fi
    
    printf '[INFO] Creating backup of LUKS volume header(s):\n'
    for counter in ${!PARTITIONS[@]}
    do
        for LUKSVolume in ${PARTITIONS[$counter]}
        do
            printf '\t[%s]: Creating header backup for volume: %s named: %s_header_backup.luks\n' $counter $LUKSVolume ${VOLUME_NAMES[$counter]}
            if [ -z $operationGeneralDeny ]
            then
                sudo cryptsetup luksHeaderBackup $LUKSVolume --header-backup-file headers/${VOLUME_NAMES[$counter]}_header_backup.luks
                sudo chmod 444 headers/${VOLUME_NAMES[$counter]}_header_backup.luks
            fi
        done
    done

    printf '[INFO] Creating an encrypted TAR archive named LUKS_Header_Backups.tar.gz.gpg in /mnt\n'
    printf '****THE PASSPHRASE FOR LUKS_Header_Backups.tar.gz.gpg IS THE SAME AS YOUR LUKS PASSPHRASE****\n'
    if [ -z $operationGeneralDeny ]
    then
        tar --directory=headers/ --create --gzip --verbose --file=- . | sudo gpg --pinentry-mode loopback --cipher-algo aes256 --digest-algo sha512 --symmetric --armor --passphrase "${PASSPHRASE[0]}" --output /mnt/LUKS_Header_Backups.tar.gz.gpg
        sudo chmod 400 /mnt/LUKS_Header_Backups.tar.gz.gpg
    fi
    
    printf '****IT IS YOUR RESPONSIBILITY TO COPY THIS TO A SECURE MEDIUM SUCH AS A USB****\n'
}
createLUKSHeaderBackups

function cleanup(){
    printf '[INFO] Unmounting all partitions from /mnt\n'
    sudo umount -R /mnt
    
    printf '[INFO] Closing LUKS volume(s):\n'
    for counter in ${!VOLUME_NAMES[@]}
    do
        for LUKSVolume in ${VOLUME_NAMES[$counter]}
        do
            printf '\t[%s]: /dev/mapper/%s\n' $counter $LUKSVolume
            sudo cryptsetup close $LUKSVolume
        done
    done
}
cleanup
exit 0
