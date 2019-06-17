                                                                                              
<div align="center">

<img src="./Assets/logo.gif" width="40%" />
</div>

## Description

This utility aims to help users quickly setup full-disk encryption, with the intent of providing a basic encryption setup for the user.

| INDEX |
| :--- |
|1.0: <a href="#pre-setup">Pre-Setup</a> |

## Pre-Setup

You <b>cannot</b> encrypt your system while it's in use. You must boot into another system to run this script.
A good choice is to burn a clonezilla iso to a USB drive. Clonezilla has all the software that we need to setup encryption on the main drive.

<b color=red>Before proceeding please visit the Limitations section to determine if your system is compatible before continuing.</b>

### Required Packages
There are two required packages: initramfs-tools, and cryptsetup. Both are available in the default Ubuntu repositories. And it is assumed that most Ubuntu derivatives will also carry these packages.

    sudo apt update
    sudo apt install cryptsetup initramfs-tools

### Get a Live-CD

Download the Clonezilla ISO
      
<a href="https://mirrors.xtom.com/osdn//clonezilla/71030/clonezilla-live-2.6.1-25-amd64.iso">clonezilla-live-2.6.1-25</a>

If you need an image writer you can <a href="http://wiki.rosalab.ru/ru/images/2/24/RosaImageWriter-2.6.1-lin-x86_64.txz">Download</a> RosaImageWriter.

We are using Clonezilla because thats the system where all testing was done. That way we make sure the script acts as expected.
If you have a version of Clonezilla already, <b>make sure</b> it's at least version `2.6.1-25`. Because (at least) version 2.5.6-22 throws a `bus error` when attempting to chroot.

### Backup Your System

Now boot into the Clonezilla USB you've just made. You will also need another drive (that isn't the one you're encrypting) to store the device image.

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

Choose: -p choose
<img src="./Assets/Clonezilla_backup_step_13.png" width="85%" />

### Partition Layout

We will now need to check that the system is able to be 




### Tested Distributions
put these in tables
Ubuntu 18.04 EFI and DOS 
Zorin OS 15 EFI and DOS

## Limitations

Not compatiable with lvm - notes
Check to see if other non-ubuntu distros work

## Security Concerns



## Download

    curl --location 'https://tinyurl.com/yxekdxwq' > encrypt.sh && chmod 744 encrypt.sh

## Running The Script

Example output for an operation
Explanation of questions the script asks the user.

### Manually Configuring

  All configuration options that are actually run when the script runs\

#### General Configuration

#### Specific for EFI

#### Specific for i386

## Post Execution
reboot system 
recovery options
 - restore from backup (easiest)
 - cryptsetup-reencrypt /dev/partition_of_root --decrypt (will have to reconfigure the system. Cannot be undone!)
 - if both fail acknowledge i take no responsibility for damages

#Reminders to write about:
#State that this tool (for the moment) only is used to 'stapple' encryption onto the drive. Explain the security risks in doing so #and provide alternative methods for acheiving a safer setup.
#Add efi support and signing uefi keys.
#See if it is possible to create an auto-updater, and an option or separate script that embedds and updates the main script in a clonezilla image.
