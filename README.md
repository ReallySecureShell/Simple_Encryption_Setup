                                                                                              
<div align="center">

<img src="./Assets/logo.gif" width="40%" />
</div>

## Description

This utility aims to help users quickly setup full-disk encryption on x86_64 or i386 based systems.

## Pre-Setup

You <b>cannot</b> encrypt your system while it's in use. You must boot into another medium (such as a Clonezilla-live CD) to run this script.

### Required Packages

### Live-CD

### Backup System

### Partition Layout

## Limitations

Not compatiable with lvm - notes
Check to see if other non-ubuntu distros work

## Security Concerns



## Download

    curl --location 'https://tinyurl.com/yxekdxwq' > encrypt.sh && chmod 744 encrypt.sh

## Running the script

Example output for an operation
Explanation of questions the script asks the user.

### Manually configuring

  All configuration options that are actually run when the script runs

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
