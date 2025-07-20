# nixos-scripts

NixOS utility scripts.

## `./install.sh`

This install script will handle running through the install process for the NixOS minimal ISO. This is primarily intended to get a minimal setup up and running so it can then be taken over by Colmena or some other management utility.

```shell
curl -O https://raw.githubusercontent.com/logandonley/nixos-scripts/refs/heads/main/install.sh
chmod +x ./install.sh

# Review it to see if you want to pass in any other flags
HOSTNAME="myhostname" ./install.sh
```

*Note: This will set up ssh authorized keys from your github.com/<your username>.keys file. So if you aren't me, be sure to set GITHUB_USER=<your user>.*


