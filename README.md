## Description

This tool can be used to encrypt your Linux system post-installation without losing data.

* <a href="#10-pre-setup">1.0: Pre-Setup</a>
  * <a href="#required-packages">Required Packages</a>
  * <a href="#obtain-clonezilla">Obtain Clonezilla</a>
  * <a href="#setup-clonezilla-environment">Setup Clonezilla Environment</a>
* <a href="#20-usage">2.0: Usage</a>

## 1.0: Pre-Setup

### Required Packages

The package: <b>cryptsetup</b> is required. <b>You must install this package on the target system <i>before</i> encrypting</b>.

    sudo apt update
    sudo apt install cryptsetup

You <b>must</b> also be using `initramfs-tools` as your initramfs generation utility. Debian and Debian-based systems rely on initramfs-tools to generate their initramfs. If you do not have initramfs-tools installed, or are NOT on a Debian or Debian-based system, then this script is not recommended.

### Obtain Clonezilla

You cannot encrypt your system while it is in use, so you need to boot from a USB in-order to run this script. It is recommended that you use Clonezilla as it is the OS where the script is tested on. This way you can be sure the system has all the required dependencies.

<a href="https://mirrors.xtom.com/osdn/clonezilla/71822/clonezilla-live-2.6.4-10-amd64.iso">Download the Clonezilla ISO</a>

If you need an image writer you can <a href="http://wiki.rosalab.ru/ru/images/2/24/RosaImageWriter-2.6.1-lin-x86_64.txz">download</a> RosaImageWriter.

### Setup Clonezilla Environment

Boot into the Clonezilla terminal. This can be done by selecting `Enter_shell` when prompted.

<img src="./Assets/Clonezilla_backup_step_1.png" width="85%" />

By default Clonezilla will not have networking enabled. To enable networking run:

```
sudo systemctl start NetworkManager
```

If you are <b>not</b> on a wired connection use the following to setup WIFI:

```
nmtui
```

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
```
