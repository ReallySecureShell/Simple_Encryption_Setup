
<div align="center">

<img src="./Assets/logo.gif" width="40%" />
</div>

## Description

This script is designed to encrypt a users root and swap partitions without loosing data. The intention of which is to stop your data from being accessed if your drive (a laptop for example) is stolen.

* <a href="#download">1.0: Download</a>
* <a href="#pre-setup">2.0: Pre-Setup</a>
  * <a href="#required-packages">Required Packages</a>
  * <a href="#get-a-live-cd">Get a Live-CD</a>
  * <a href="#backup-your-system">Backup Your System</a>
* <a href="#limitations">3.0: Limitations</a>

## Download

    curl --location 'https://tinyurl.com/yxekdxwq' > encrypt.sh && chmod 744 encrypt.sh

## Pre-Setup

You <b>cannot</b> encrypt your system while it's in use. You must boot into another system to run this script.
A good choice is to burn a Clonezilla ISO to a USB drive. Clonezilla has all the software that we need to setup encryption on the main drive.

<b color=red>Before proceeding please visit the <a href="#limitations">Limitations</a> section to determine if your system is compatible before continuing.</b>

### Required Packages
There are two required packages: initramfs-tools, and cryptsetup. Both are available in the default Ubuntu repositories. And it is assumed that most Ubuntu derivatives will also carry these packages.

    sudo apt update
    sudo apt install cryptsetup initramfs-tools

### Get a Live-CD

<a href="https://mirrors.xtom.com/osdn//clonezilla/71030/clonezilla-live-2.6.1-25-amd64.iso">Download the Clonezilla ISO</a>

If you need an image writer you can <a href="http://wiki.rosalab.ru/ru/images/2/24/RosaImageWriter-2.6.1-lin-x86_64.txz">download</a> RosaImageWriter.

We are using Clonezilla because it's the OS where all testing is being done. That way we make sure the script acts as expected.
If you have a version of Clonezilla already, <b>make sure it's at least version `2.6.1-25`</b>. Because there is bug on (at least) version 2.5.6-22 that when attempting to chroot, all attempts will fail with a `bus error`.

### Backup Your System

Now boot into the Clonezilla USB you've just made. <b>You will also need another drive (that isn't the one you're encrypting) to store the device image</b>.

You'll be prompted to enter your language and keyboard layout. Before arriving at this screen:

```
Choose: Start_Clonezilla
<img src="./Assets/Clonezilla_backup_step_1.png" width="85%" />

Choose: device-image
<img src="./Assets/Clonezilla_backup_step_2.png" width="85%" />

Choose: local_dev
<img src="./Assets/Clonezilla_backup_step_3.png" width="85%" />

Choose: The device thats not the drive you're encrypting
<img src="./Assets/Clonezilla_backup_step_4.png" width="85%" />

Choose: The directory where you want to store the image
<img src="./Assets/Clonezilla_backup_step_5.png" width="85%" />

Choose: Beginner
<img src="./Assets/Clonezilla_backup_step_6.png" width="85%" />

Choose: savedisk
<img src="./Assets/Clonezilla_backup_step_7.png" width="85%" />

Optionally write a name for your image or leave it as the default.
<img src="./Assets/Clonezilla_backup_step_8.png" width="85%" />

Choose: The drive you want to backup
<img src="./Assets/Clonezilla_backup_step_9.png" width="85%" />

Choose: -sfsck<br>
<img src="./Assets/Clonezilla_backup_step_10.png" width="85%" />

Choose: Yes, check the saved image
<img src="./Assets/Clonezilla_backup_step_11.png" width="85%" />

Choose: -senc Not to encrypt the image
<img src="./Assets/Clonezilla_backup_step_12.png" width="85%" />

Choose: -p choose (boot into the shell when finished)
<img src="./Assets/Clonezilla_backup_step_13.png" width="85%" />

```

## Limitations

| Drawbacks and Shortcomings |
| --- |
| Incompatible with LVM (<a href="https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#LUKS_on_LVM">although it is still possible to setup encryption on LVM</a>) | 
| Only supports "basic" partitioning schemes (see section: <a href="#compatible-partition-schemes">Compatible Partition Schemes</a>) |
| Vulnerable to <a href="https://en.wikipedia.org/wiki/Evil_maid_attack">Evil-Maid</a> attacks | 
| Uses LUKS version 1 (<a href="https://savannah.gnu.org/bugs/?55093">because grub does not support</a> <a href="https://gitlab.com/cryptsetup/cryptsetup/blob/master/docs/v2.0.0-ReleaseNotes">LUKS version 2</a>) |
| Requires initramfs-tools instead of the more common dracut utility (If initramfs-tools are not in the repository, you'll have to install it from <a href="https://wiki.debian.org/initramfs-tools">source</a>) |

### Compatible Partition Schemes

The diagram that follows details known working partition schemes. If your partitions do not match any of the following, there is NO GUARANTEE that the script will operate properly.

Note: The partition "ROOT" is <b>implicit</b> to all files/directories (except for the swapfile). For example, if you could have a separate `/home` partition, it would be explicitly specified.

```
1: ________________________       2: ________________________ 
  |          EFI           |        |          EFI           |
  |------------------------|        |------------------------|
  |          ROOT          |        |          ROOT          |
  |________________________|        |        SWAPFILE        |
  |          SWAP          |        |________________________|
  |________________________|        |                        |
  |    EFI in /boot/efi    |        |    EFI in /boot/efi    |
  |________________________|        |________________________|
  

3: ________________________       4: ________________________ 
  |          DOS           |        |          DOS           |
  |------------------------|        |------------------------|
  |                        |        |                        |
  |          ROOT          |        |          ROOT          |
  |                        |        |        SWAPFILE        |
  |________________________|        |                        |
  |          SWAP          |        |                        |
  |________________________|        |________________________|

```

## In-Depth Operation

The following subsections will discuss the inner workings of the script. This information is provided to help the user replicate and improve upon the existing code.

### Auto Detect Partition Table Type

This function is called `FUNCT_detect_partition_table_type`. Its purpose is to detect weather the partition table is DOS or EFI.

First we check if the mounted partition (your `/`) contains the `x86_64-efi` directory:

```bash
...
#Has grub been installed with EFI support?
if [ -d '/mnt/boot/grub/x86_64-efi' ]
then
...
```

If so try to get the UUID of the EFI partition from the filesystem's /etc/fstab:

```bash
_uuid_of_efi_part=`sed -n '/\/boot\/efi/{
   /^UUID\=/{
    s/^UUID\=//
    s/ .*//
    p
}
}' /mnt/etc/fstab`
```
STOPPED HERE

#### Specific for EFI

#### Specific for i386

## Recovery
reboot system 
recovery options
 - restore from backup (easiest)
 - cryptsetup-reencrypt /dev/partition_of_root --decrypt (will have to reconfigure the system. Cannot be undone!)
 - if both fail acknowledge i take no responsibility for damages

#Reminders to write about:
#State that this tool (for the moment) only is used to 'stapple' encryption onto the drive. Explain the security risks in doing so #and provide alternative methods for acheiving a safer setup.
#Add efi support and signing uefi keys.
#See if it is possible to create an auto-updater, and an option or separate script that embedds and updates the main script in a clonezilla image.
