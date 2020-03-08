## Description

This tool can be used to encrypt your Linux system post-installation without losing data.

* <a href="#10-pre-setup">1.0: Pre-Setup</a>
  * <a href="#required-packages">Required Packages</a>
  * <a href="#obtain-clonezilla-and-image-writter">Obtain Clonezilla and Image Writter</a>
  * <a href="setup-clonezilla-environment">Setup Clonezilla Environment</a>
* <a href="#20-usage">2.0: Usage</a>

## 1.0: Pre-Setup

You <b>cannot</b> encrypt your system while it's in use. You must boot into another system to run this script.
A good choice is to burn a Clonezilla ISO to a USB drive.<br>

### Required Packages
The package: <b>cryptsetup</b> is required. <b>You must install this package on the target system <i>before</i> encrypting</b>.

    sudo apt update
    sudo apt install cryptsetup

You <b>must</b> also be using `initramfs-tools` as your initramfs generation utility.

### Obtain Clonezilla and Image Writter

<a href="https://mirrors.xtom.com/osdn/clonezilla/71822/clonezilla-live-2.6.4-10-amd64.iso">Download the Clonezilla ISO</a>

If you need an image writer you can <a href="http://wiki.rosalab.ru/ru/images/2/24/RosaImageWriter-2.6.1-lin-x86_64.txz">download</a> RosaImageWriter.

It is recommended that you use Clonezilla as it's the OS where the script is tested on. This way you can be sure the system has all the required dependencies.

### Backup Your System

Now boot into the Clonezilla USB you've just made. <b>You will also need another drive (that isn't the one you're encrypting) to store the device image</b>.

Instructions how to perform a backup with clonezilla can be found <a href="https://www.unixmen.com/backup-clone-disk-linux-using-clonezilla/">here</a>

### Setup Clonezilla Environment

Once the backup is finished boot into the Clonezilla terminal. This can be done by selecting `Enter_shell` when prompted.

<img src="./Assets/Clonezilla_backup_step_1.png" width="85%" />

By default Clonezilla will not have networking enabled. To enable networking run:

```
sudo systemctl start NetworkManager
```

If you are <b>not</b> on a wired connection use the following to setup WIFI:

```
nmtui
```

Once networking is up you can use `netcat` to transfer the script from another device to the Clonezilla machine.

## 2.0: Usage
```
./SimpleEncryptionSetup.sh -fvh -p 'partition1:mountpoint1[ partitionN:mountpointN]' -r root-partition [-e efi-partition {-d DIR}]

-p, --partitions 'partition1:mountpoint1[ partitionN:mountpointN]'  Specify the partition(s) to encrypt.
                                                                    Example: '/dev/sda1:/ /dev/sda2:/home'
                                                                    
-r, --root <root-partition>                                         The root partition. This can be either
                                                                    /dev/sd*, or if using LVM /dev/mapper/<root-name>.
                                                                    Example: /dev/sda1
                                                                    
-e, --efi <efi-partition>                                           Specify the EFI partition.
                                                                    Example: /dev/sda3
                                                                    
    -d, --efi-path <DIR>                                            The directory in /mnt/boot/efi/EFI/ where grub will be installed.
                                                                    This directory MUST already exist. If lost, 'ls' the directories 
                                                                    in said EFI path and find a file named grubx64.efi, if the directory 
                                                                    contains that file it's probably the right one. This directory is also 
                                                                    used as the bootloader-id.
                                                                    Example: ubuntu
                                                                    
-f, --fake                                                          Do not make modifications to the system. This is used
                                                                    to check the output for errors *before* modifying
                                                                    the system.

-v, --version                                                       Print version information then exit.
                                                                    
-h, --help                                                          Print this help page then exit.
```
