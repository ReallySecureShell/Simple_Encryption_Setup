## Description

This script adds a basic encryption setup to your system <i>without</i> losing data.

* <a href="#10-download">1.0: Download</a>
* <a href="#20-pre-setup">2.0: Pre-Setup</a>
  * <a href="#required-packages">Required Packages</a>
  * <a href="#get-a-live-cd">Get a Live-CD</a>
  * <a href="#backup-your-system">Backup Your System</a>
  * <a href="#setup-clonezilla-environment">Setup Clonezilla Environment</a>
* <a href="#30-limitations">3.0: Limitations</a>
  * <a href="#compatible-partition-schemes">Compatible Partition Schemes</a>
* <a href="#40-recovery">4.0: Recovery</a>
  * <a href="#recover-from-backup">Recover From Backup</a>
  * <a href="#recover-without-a-backup">Recover WITHOUT a Backup</a>

## 1.0: Download

Once in the Clonezilla terminal (see section <a href="#setup-clonezilla-environment">Setup Clonezilla Environment</a>) you can download the script with one of the following commands.

    curl 'https://raw.githubusercontent.com/ReallySecureShell/Simple_Encryption_Setup/master/main.sh' > encrypt.sh && chmod 744 encrypt.sh

Or use the shortend URL: 

    curl --location 'https://tinyurl.com/y4ufmrcb' > encrypt.sh && chmod 744 encrypt.sh

## 2.0: Pre-Setup

You <b>cannot</b> encrypt your system while it's in use. You must boot into another system to run this script.
A good choice is to burn a Clonezilla ISO to a USB drive. Clonezilla has all the software that we need to setup encryption on the main drive.

<b color=red>Before proceeding please visit the <a href="#compatible-partition-schemes">Compatible Partition Schemes</a> subsection to determine if your system is compatible before continuing.</b>

### Required Packages
There are two required packages: initramfs-tools, and cryptsetup. Both are available in the default Ubuntu repositories. And it is assumed that most Ubuntu derivatives will also carry these packages. <b>You must install these packages on the target system <i>before</i> encrypting</b>.

    sudo apt update
    sudo apt install cryptsetup initramfs-tools

### Get a Live-CD

<a href="https://mirrors.xtom.com/osdn//clonezilla/71030/clonezilla-live-2.6.1-25-amd64.iso">Download the Clonezilla ISO</a>

If you need an image writer you can <a href="http://wiki.rosalab.ru/ru/images/2/24/RosaImageWriter-2.6.1-lin-x86_64.txz">download</a> RosaImageWriter.

We are using Clonezilla because it's the OS where all testing is being done. That way we make sure the script acts as expected.
If you have a version of Clonezilla already, <b>make sure it's at least version `2.6.1-25`</b>. Earlier versions have a problem with chrooting that causes a <i>bus error</i> to be thrown.

### Backup Your System

Now boot into the Clonezilla USB you've just made. <b>You will also need another drive (that isn't the one you're encrypting) to store the device image</b>.

You'll be prompted to enter your language and keyboard layout. Before arriving at this screen:

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

Choose: savedisk<br>
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

### Setup Clonezilla Environment

Once the backup is finished boot into the Clonezilla terminal. This can be done by selecting `Enter_shell` when prompted.

<img src="./Assets/Clonezilla_backup_step_1.png" width="85%" />

By default Clonezilla will not have networking enabled. To enable networking run:

```
sudo systemctl start NetworkManager
```

If you are <b>not</b> on a wired connection run the following to setup WIFI:

```
nmtui
```

## 3.0: Limitations

| Drawbacks and Shortcomings |
| --- |
| Only works with i386 and x86_64 systems |
| Incompatible with LVM (<a href="https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#LUKS_on_LVM">although it is still possible to setup encryption on LVM</a>) | 
| Only supports "basic" partitioning schemes (see section: <a href="#compatible-partition-schemes">Compatible Partition Schemes</a>) |
| Vulnerable to <a href="https://en.wikipedia.org/wiki/Evil_maid_attack">Evil-Maid</a> attacks | 
| Uses LUKS version 1 (<a href="https://savannah.gnu.org/bugs/?55093">because GRUB does not support</a> <a href="https://gitlab.com/cryptsetup/cryptsetup/blob/master/docs/v2.0.0-ReleaseNotes">LUKS version 2</a>) |
| Requires initramfs-tools instead of the more common dracut utility (If initramfs-tools are not in the repository you'll have to install it from <a href="https://wiki.debian.org/initramfs-tools">source</a>) |

### Compatible Partition Schemes

The diagram that follows details known working partition schemes. If your partitions do not match any of the following there is NO GUARANTEE that the script will operate properly.

The partition "ROOT" is <b>implicit</b> to all files/directories (except for the swapfile). For example, if you could have a separate `/home` partition, it would be explicitly specified.

Each block specifies a whole drive. With ROOT, SWAPFILE/SWAP, and EFI representing partitions on those drives.

Note: The first entry in each block is the <i>type</i> of partition table (EFI/DOS), i.e. not a partition.

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

The following are examples of how one would setup their partitions to meet the requirements above.

#### Example for EFI

<img src="./Assets/compatible_efi_partition_scheme.png" width="100%" />

#### Example for DOS

<img src="./Assets/compatible_dos_partition_scheme.png" width="100%" />

Once you edit and/or confirm that your system is compatible <a href="#10-download">download</a> the script.

## 4.0: Recovery

### Recover From Backup
If you have a backup, then restore it using Clonezilla. The steps to restore to a backup are nearly identical to making a backup. 

Choose <b>restoredisk</b> when prompted with this screen:

<img src="./Assets/restore_from_backup.png" width="85%" />

### Recover WITHOUT a Backup

If a backup was not created you STILL have a chance at fully recovering your system.

Boot back into Clonezilla and load into a terminal. Once you've done so run the below command.
Doing so will remove all the encryption from the drive (including the LUKS headers).

```bash
sudo cryptsetup-reencrypt --decrypt /dev/<your_root_partition>
```

After the operation is complete, mount the filesystem into `/mnt`.

```bash
sudo mount /dev/<your_root_partition> /mnt
```

Setup chroot environment by binding /sys, /dev, /proc into the mounted filesystem, then chroot into it.

```bash
for i in proc sys dev;do sudo mount --bind /$i /mnt/$i;done

#Now chroot into the filesystem
sudo chroot /mnt
```

Remove initramfs unlock.sh and unlock.key. This is just for cleanup.

```bash
rm /etc/initramfs-tools/hooks/unlock.sh
rm /etc/initramfs-tools/scripts/unlock.key
```

In /etc/crypttab, remove the line that resembles the following:

```
rootfs UUID=4369eca1-a93c-45eb-a00b-e08d58831810 none luks,discard,keyscript=/etc/initramfs-tools/hooks/unlock.sh
```

Remove the following two lines in /etc/default/grub:

```
GRUB_ENABLE_CRYPTODISK=y
GRUB_PRELOAD_MODULES="luks cryptodisk"
```

Now we need to reinstall GRUB. How GRUB is installed depends on the type of partition table (EFI/DOS).

If installing for `i386-pc` note that the device you choose is NOT a partition. For example: if your `/` partition is located on /dev/sda1, then install GRUB on /dev/sda i.e. you simply remove the partition number from the device.

If installing for `x86_64-efi` mount the EFI partition into `/boot/efi` before installing GRUB.

```bash
#For i386-pc
grub-install --recheck /dev/<root_device>

#For x86_64-efi
mount /dev/<EFI_partition> /boot/efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader=ubuntu --boot-directory=/boot/efi/EFI/ubuntu --recheck
grub-mkconfig -o /boot/efi/EFI/ubuntu/grub/grub.cfg
```

Update GRUB and initramfs.

```bash
#Update grub configuration.
update-grub

#Re-generate initramfs images for all kernels.
update-initramfs -c -k all
```

Unmount the mounted filesystem.

```bash
#Exit the chroot
exit

#Unmount the bindings.
sudo umount /mnt/{proc,sys,dev}

#If the EFI directory is mounted, unmount it.
sudo umount /mnt/boot/efi

#Unmount the filesystem
sudo umount /mnt
```

Now attempt to boot back into your system.
