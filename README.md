# Arch-Gkuba

This is my customization for fresh Arch based installs.

## Download Arch live or CachyOS
- [Arch Download][Arch ISO]

[Arch ISO]:https://archlinux.org/download/

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
