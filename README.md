# Debian-Gkuba

This is my customization for fresh Debian installs.

## Download Debian non-free netinstall

Use the following Debian ISO as the base:

- [Debian 11.5 Stable non-free][Debian ISO]

[Debian ISO]: https://cdimage.debian.org/cdimage/unofficial/non-free/cd-including-firmware/11.5.0+nonfree/amd64/iso-cd/

__NOTE:__ _do NOT grab the EDU download. This image includes non-free and firmware_

### To Install
This must be run as the `root` user.

```bash
bash <(wget -qO- https://raw.githubusercontent.com/gkuba/Debian-Gkuba/main/install.sh)
```

#### Install script information

The `install.sh` script has been written in a modular way. This allows you to run parts of this or the whole thing.
Full list of these functions below just append the one you want at the end of the command listed.

This example will check for updates:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/gkuba/Debian-Gkuba/main/install.sh) checkUpdates
```

##### Functions

- Check for package updates

```text
checkUpdates
```

- Install Wanted Packages

```text
installPackages
```

This will install the packages listed under the `$WANTED_PACKAGES` variable

###### Misc Info

My bash prompt and settings can be found here [gkuba/dotfiles][gkuba/dotfiles]

[gkuba/dotfiles]: https://github.com/gkuba/dotfiles
