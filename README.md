<div align=center>
<img src="./Assets/logo.gif" width="50%" />
</div>

## Description

This script uses cryptsetup to add encryption to all partitions defined in your /etc/fstab <b>without losing data</b>.

* <a href="#10-download">1.0: Download</a>
* <a href="#20-pre-setup">2.0: Pre-Setup</a>
  * <a href="#required-packages">Required Packages</a>
  * <a href="#obtain-clonezilla-and-image-writter">Obtain Clonezilla and Image Writter</a>
  * <a href="#backup-your-system">Backup Your System</a>
  * <a href="#setup-clonezilla-environment">Setup Clonezilla Environment</a>
* <a href="#30-running-the-script">3.0: Running the Script</a>
* <a href="#40-things-to-note-before-using-the-program">4.0: Things to note before using the program</a>
  * <a href="#partition-schemes">Partition Schemes</a>
  * <a href="#known-working-distributions">Known Working Distributions</a>
* <a href="#50-planned-features">5.0: Planned Features</a>
* <a href="#60-recovery-deprecated">6.0: Recovery (deprecated)</a>
  * <a href="#recover-from-backup">Recover From Backup</a>
  * <a href="#recover-without-a-backup">Recover WITHOUT a Backup</a>

## 1.0: Download

<b>Please read the <a href="#40-drawbacks-and-shortcomings">Drawbacks and Shortcomings</a> section before using the program.</b>

Once in the Clonezilla terminal (see section <a href="#setup-clonezilla-environment">Setup Clonezilla Environment</a>) you can download the script with one of the following commands.

    curl 'https://raw.githubusercontent.com/ReallySecureShell/Simple_Encryption_Setup/master/main.sh' > encrypt.sh && chmod 744 encrypt.sh

Or use the shortend URL: 

    curl --location 'https://tinyurl.com/y4ufmrcb' > encrypt.sh && chmod 744 encrypt.sh

SHA256 Checksum

    204d5561a2a518d8b1a1bcf933984957645e36da4ba8ced966554ad47acc4c1a  encrypt.sh

## 2.0: Pre-Setup

You <b>cannot</b> encrypt your system while it's in use. You must boot into another system to run this script.
A good choice is to burn a Clonezilla ISO to a USB drive.<br>

Also be sure to unplug/disable any device that you do not want encrypted. This only applies to devices listed in your /etc/fstab.

### Required Packages
The package: <b>cryptsetup</b> is required. <b>You must install this package on the target system <i>before</i> encrypting</b>.

    sudo apt update
    sudo apt install cryptsetup

You <b>must</b> also be using either `initramfs-tools` or `mkinitcpio` as your initramfs generation utility.

### Obtain Clonezilla and Image Writter

<a href="https://mirrors.xtom.com/osdn//clonezilla/71030/clonezilla-live-2.6.1-25-amd64.iso">Download the Clonezilla ISO</a>

If you need an image writer you can <a href="http://wiki.rosalab.ru/ru/images/2/24/RosaImageWriter-2.6.1-lin-x86_64.txz">download</a> RosaImageWriter.

We are using Clonezilla because it's the OS where all testing is being done. That way we make sure the script acts as expected.
If you have a version of Clonezilla already, <b>make sure it's at least version `2.6.1-25`</b>. Earlier versions have a problem with chrooting that causes a <i>bus error</i> to be thrown.

### Backup Your System

Now boot into the Clonezilla USB you've just made. <b>You will also need another drive (that isn't the one you're encrypting) to store the device image</b>.

Instructions how to perform a backup with clonezilla can be found <a href="https://www.unixmen.com/backup-clone-disk-linux-using-clonezilla/">here</a>

Additionally look in the `/Assets` directory to find pictures of (almost) every step needed to backup your system.

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

Once networking is up you can <a href="#10-download">download</a> the script.

## 3.0: Running the Script

![Output sample](./Assets/Run_example.gif)

## 4.0: Things to note before using the program

| Drawbacks and Shortcomings |
| --- |
| Only EXT4 and EXT3 filesystems are supported |
| mkinitcpio and initramfs-tools are the only supported initramfs generation utilities |
| Only works with i386 and x86_64 systems |
| Advanced LVM setups (such as mirrors) are most likely going to break the script |
| Only systems using the GRUB bootloader are supported |
| "Destructive" to /etc/mkinitcpio.conf, where the line `HOOKS` is replaced with: `HOOKS="base udev autodetect keyboard keymap modconf block encrypt filesystems"` (will adjust for LVM by adding the `lvm2` hook between "block" and "encrypt") |
| Not compatible with any type of RAID setup |
| Disables the ability to use Hibernation mode |
| Multiple partitions are supported, however the `/usr` partition is not treated specially. This can cause the system to be unbootable |
| Vulnerable to <a href="https://en.wikipedia.org/wiki/Evil_maid_attack">Evil-Maid</a> attacks |
| Does not properly secure the keyfile (used by initramfs for unlocking encrypted partitions) i.e. the keyfile is in plain-text |
| Uses LUKS version 1 (<a href="https://savannah.gnu.org/bugs/?55093">because GRUB does not support</a> <a href="https://gitlab.com/cryptsetup/cryptsetup/blob/master/docs/v2.0.0-ReleaseNotes">LUKS version 2</a>) |

### Partition Schemes

Below are known working partition setups. I want to make it clear that you DO NOT have to follow this partition scheme exactly. For example, you can have your `/` on any partition (sda1, sda2, sda3...etc) or Logical Volume (myGroupRoot, myRoot, Root...etc) same applies for the other partitions. Also you may notice there is no SWAP partition in the scheme, don't worry, encrypting SWAP is still supported just not depicted.

Lastly, you can choose what partitions to encrypt during runtime. You can even opt to not encrypt your `/` partition.

Just to be clear the diagram below depicts partition setups *before* encryption. You compare what is shown to your current setup to determine if your system is compatible.
```
  LEGEND (Without LVM)
+---------------------+
|  WHAT IT STORES     |
|                     |
|                     |
|  WHERE ITS MOUNTED  |
|                     |
|                     |
|  WHAT PARTITION     |
+---------------------+

      LEGEND (WITH LVM)
+---------------------------+
|  WHAT IT STORES           |
|                           |
|  WHERE ITS MOUNTED        |
|___________________________|
|  LOGICAL VOLUME           |
|___________________________|
|                           |
|  PHYSICAL VOLUME (Part.)  |
+---------------------------+

                                          ----WITHOUT LVM----

MBR Example Setup
+-------------------+--------------------+--------------------+
|  Root Partition   |  Home Partition    |  Var Partition     |
|                   |                    |                    |
|                   |                    |                    |
|  /                |  /home             |  /var              |
|                   |                    |                    |
|                   |                    |                    |
|  /dev/sda1        |  /dev/sda2         |  /dev/sda3         |
+-------------------+--------------------+--------------------+

EFI Example Setup
+------------------+-------------------+--------------------+--------------------+
|  EFI Partition   |  Root Partition   |  Home Partition    |  Var Partition     |
|                  |                   |                    |                    |
|                  |                   |                    |                    |
|  /boot/efi       |  /                |  /home             |  /var              |
|                  |                   |                    |                    |
|                  |                   |                    |                    |
|  /dev/sda1       |  /dev/sda2        |  /dev/sda3         |  /dev/sda4         |
+------------------+-------------------+--------------------+--------------------+

                                          ----WITH LVM----

MBR Example Setup
+---------------------------+---------------------------+--------------------------+
|  Root Partition           |  Home Partition           |  Var Partition           |
|                           |                           |                          |
|                           |                           |                          |
|  /                        |  /home                    |  /var                    |
|                           |                           |                          |
|___________________________|___________________________|__________________________|
|  /dev/mapper/myGroupRoot  |  /dev/mapper/myGroupHome  |  /dev/mapper/myGroupVar  |
|___________________________|___________________________|__________________________|
|                                                                                  |
|                                  /dev/sda1                                       |
+----------------------------------------------------------------------------------+

EFI Example Setup
+--------------------+---------------------------+---------------------------+--------------------------+
|  EFI Partition     |  Root Partition           |  Home Partition           |  Var Partition           |
|                    |                           |                           |                          |
|                    |                           |                           |                          |
|  /boot/efi         |  /                        |  /home                    |  /var                    |
|                    |                           |                           |                          |
|                    |___________________________|___________________________|__________________________|
|                    |  /dev/mapper/myGroupRoot  |  /dev/mapper/myGroupHome  |  /dev/mapper/myGroupVar  |
|                    |___________________________|___________________________|__________________________|
|                    |                                                                                  |
|  /dev/sda1         |                                  /dev/sda2                                       |
+--------------------+----------------------------------------------------------------------------------+
```

### Known Working Distributions

| Distribution | Remarks |
| :--- | :--- | 
| Ubuntu 18.04 | None |
| Manjaro 18.0 | None |

## 5.0: Planned Features

| Feature | Description |
| :---     | :--- |
| Dracut support | Support for the dracut init-generation utility |
| Detached LUKS header | Choose to store the LUKS header on a separate medium |
| Yubikey support for LUKS | Use a challenge-response from a yubikey as a LUKS key |

## 6.0: Recovery (deprecated)

### Recover From Backup
If you have a backup, then restore it using Clonezilla. The steps to restore to a backup are nearly identical to making a backup. 

Choose <b>restoredisk</b> when prompted with this screen:

<img src="./Assets/restore_from_backup.png" width="85%" />

### Recover WITHOUT a Backup

If a backup was not created you STILL have a chance at fully recovering your system.

Boot back into Clonezilla and load into a terminal. Once you've done so you'll have to figure out what devices are encrypted. To do that run the following:

```bash
sudo cryptsetup open <your_root_partition> root

sudo mount /dev/mapper/root /mnt

#bind /proc, /sys, and /dev to the mounted filesystem.
for i in proc sys dev;do sudo mount --bind /$i /mnt/$i;done

sudo chroot /mnt

#The encrypted partitions are of type "crypto_LUKS"
blkid
```

Once you've written down all the encrypted devices unmount the partitions and close the LUKS device.

```bash
#Unmount the bindings
sudo umount /mnt/{dev,sys,proc}

#Unmount the opened LUKS device
sudo umount /mnt

#Close the LUKS device
sudo cryptsetup close /dev/mapper/root
```

Now that we know what devices are encrypted, enter them one-by-one into the command below.
```bash
sudo cryptsetup-reencrypt --decrypt /dev/<crypt_device>
```

<b>Remount your root device by following the previous steps (minus the cryptsetup open command and the mount command will be the root partition NOT /dev/mapper/root)</b>

Remove initramfs unlock.sh and unlock.key. This is just for cleanup.
```bash
rm /etc/initramfs-tools/hooks/unlock.sh
rm /etc/initramfs-tools/scripts/unlock.key
```

<b>In /etc/crypttab record what UUID(s) go to which device!</b> You will use this information to reconfigure your /etc/fstab in the next step.

Then remove all the enteries in /etc/crypttab <b>except</b> the one for the SWAP partition (if present).

```
#Example of an /etc/crypttab configuration

# <target name>	<source device>		<key file>	<options>
root UUID=b65a6d7e-b3dc-470d-8647-c8e6e0d85d9b none luks,keyscript=/etc/initramfs-tools/hooks/unlock.sh
home UUID=64dc8278-dc10-4c0c-a1f4-3f10f6abec8b /etc/initramfs-tools/scripts/unlock.key luks
opt UUID=b70bd54e-b900-47b5-9d5b-1740b6ccac47 /etc/initramfs-tools/scripts/unlock.key luks
var UUID=9751dab0-64c0-4192-8829-a7f74b62af53 /etc/initramfs-tools/scripts/unlock.key luks
```

Now remove the appropriate entries from crypttab.

Using the information recorded in the previous step, reconfigure your /etc/fstab.

<b>Before editing, /etc/fstab should look similar to this:</b>
```
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# / was on /dev/sda2 during installation
/dev/mapper/root /              ext4    errors=remount-ro 0       1
# /boot/efi was on /dev/sda1 during installation
UUID=3F9B-6958  /boot/efi       vfat    umask=0077      0       1
# /home was on /dev/sda3 during installation
/dev/mapper/home /home          ext4    defaults        0       2
# /opt was on /dev/sda5 during installation
/dev/mapper/opt /opt            ext4    defaults        0       2
# /var was on /dev/sda4 during installation
/dev/mapper/var /var            ext4    defaults        0       2
/swapfile       none            swap    sw              0       0
```

Replace the first column with the UUID recorded from crypttab.

<b>After editing, /etc/fstab should look similar to this:</b>
```
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# / was on /dev/sda2 during installation
UUID=b65a6d7e-b3dc-470d-8647-c8e6e0d85d9b /               ext4    errors=remount-ro 0       1
# /boot/efi was on /dev/sda1 during installation
UUID=3F9B-6958  /boot/efi       vfat    umask=0077      0       1
# /home was on /dev/sda3 during installation
UUID=64dc8278-dc10-4c0c-a1f4-3f10f6abec8b /home           ext4    defaults        0       2
# /opt was on /dev/sda5 during installation
UUID=b70bd54e-b900-47b5-9d5b-1740b6ccac47 /opt            ext4    defaults        0       2
# /var was on /dev/sda4 during installation
UUID=9751dab0-64c0-4192-8829-a7f74b62af53 /var            ext4    defaults        0       2
/swapfile                                 none            swap    sw              0       0
```

Remove the following two lines in /etc/default/grub:

```
GRUB_ENABLE_CRYPTODISK=y
GRUB_PRELOAD_MODULES="luks cryptodisk"
```

Now we need to reinstall GRUB. How GRUB is installed depends on the type of partition table (EFI/DOS).

If installing for `i386-pc` note that the device you choose is NOT a partition. Use `lsblk` to determine your root device.
```bash
#For i386-pc
grub-install --recheck /dev/<root_device>
```

If installing for `x86_64-efi` mount the EFI partition into `/boot/efi` before installing GRUB.

```bash
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
