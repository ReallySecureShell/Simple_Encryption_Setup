## Description

This tool can be used to encrypt your Linux system post-installation without losing data.

* <a href="#10-pre-setup">1.0: Pre-Setup</a>
  * <a href="#required-packages">Required Packages</a>
  * <a href="#obtain-clonezilla-and-image-writter">Obtain Clonezilla and Image Writter</a>
  * <a href="setup-clonezilla-environment">Setup Clonezilla Environment</a>

## 1.0: Pre-Setup

You <b>cannot</b> encrypt your system while it's in use. You must boot into another system to run this script.
A good choice is to burn a Clonezilla ISO to a USB drive.<br>

### Required Packages
The package: <b>cryptsetup</b> is required. <b>You must install this package on the target system <i>before</i> encrypting</b>.

    sudo apt update
    sudo apt install cryptsetup

You <b>must</b> also be using `initramfs-tools` as your initramfs generation utility.

### Obtain Clonezilla and Image Writter

<a href="https://mirrors.xtom.com/osdn//clonezilla/71030/clonezilla-live-2.6.1-25-amd64.iso">Download the Clonezilla ISO</a>

If you need an image writer you can <a href="http://wiki.rosalab.ru/ru/images/2/24/RosaImageWriter-2.6.1-lin-x86_64.txz">download</a> RosaImageWriter.

It is recommended that you use Clonezilla as it's the OS where the script is tested on. This way you can be sure the system has all the required dependencies.

If you have a version of Clonezilla already, <b>make sure it's at least version `2.6.1-25`</b>. Earlier versions have a problem with chrooting that causes a <i>bus error</i> to be thrown.

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


