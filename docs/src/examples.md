# Examples

See [Configuration Options](./configuration-options.md) for all available options.

## Simple

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      files = [
        # auto-generated machine ID
        { file = "/etc/machine-id"; inInitrd = true; }
      ];
      directories = [
        "/var/lib/systemd/timers"
        # NixOS user state
        "/var/lib/nixos"
        "/var/log"
      ];
    };
  };
}
```

## Compatibility with systemd's `ConditionFirstBoot`

When `/etc/machine-id` is preserved, the persistent file is created with the content
`uninitialized`, so systemd detects the first boot and `ConditionFirstBoot` is met.
`systemd-machine-id-commit.service` then commits the transient machine-id to the
persistent volume, on every later boot the preserved machine-id is used.
This works with both a bind-mount and a symlink.

In this example the machine-id is preserved on the persistent volume via symlink
instead of a bind-mount. The option `configureParent` causes the parent directory
of the symlink's target, i.e. `/persistent/etc/` to be created.

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      files = [
        # auto-generated machine ID
        { file = "/etc/machine-id"; inInitrd = true; how = "symlink"; configureParent = true; }
        # ...
      ];
      directories = [
        # ...
      ];
    };
  };
}
```



## Complex

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  preservation = {
    # the module doesn't do anything unless it is enabled
    enable = true;

    preserveAt."/persistent" = {

      # preserve system directories
      directories = [
        "/etc/secureboot"
        "/var/lib/bluetooth"
        "/var/lib/fprint"
        "/var/lib/fwupd"
        "/var/lib/libvirt"
        "/var/lib/power-profiles-daemon"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/rfkill"
        "/var/lib/systemd/timers"
        "/var/log"
        { directory = "/var/lib/nixos"; inInitrd = true; }
      ];

      # preserve system files
      files = [
        { file = "/etc/machine-id"; inInitrd = true; }
        { file = "/etc/ssh/ssh_host_rsa_key"; how = "symlink"; configureParent = true; }
        { file = "/etc/ssh/ssh_host_ed25519_key"; how = "symlink"; configureParent = true; }
        "/var/lib/usbguard/rules.conf"

        # creates a symlink on the volatile root
        # creates an empty directory on the persistent volume, i.e. /persistent/var/lib/systemd
        # does not create an empty file at the symlink's target (would require `createLinkTarget = true`)
        { file = "/var/lib/systemd/random-seed"; how = "symlink"; inInitrd = true; configureParent = true; }
      ];

      # preserve user-specific files, implies ownership
      users = {
        butz = {
          commonMountOptions = [
            "x-gvfs-hide"
          ];
          directories = [
            { directory = ".ssh"; mode = "0700"; }
            ".config/syncthing"
            ".config/Element"
            ".local/state/nvim"
            ".local/state/wireplumber"
            ".local/share/direnv"
            ".local/state/nix"
            ".mozilla"
          ];
          files = [
            ".histfile"
          ];
        };
        root = {
          # specify user home when it is not `/home/${user}`
          home = "/root";
          directories = [
            { directory = ".ssh"; mode = "0700"; }
          ];
        };
      };
    };
  };

  # Create some directories with custom permissions.
  #
  # In this configuration the path `/home/butz/.local` is not an immediate parent
  # of any persisted file, so it would be created with the systemd-tmpfiles default
  # ownership `root:root` and mode `0755`. This would mean that the user `butz`
  # could not create other files or directories inside `/home/butz/.local`.
  #
  # Therefore systemd-tmpfiles is used to prepare such directories with
  # appropriate permissions.
  #
  # Note that immediate parent directories of persisted files can also be
  # configured with ownership and permissions from the `parent` settings if
  # `configureParent = true` is set for the file.
  systemd.tmpfiles.settings.preservation = {
    "/home/butz/.config".d = { user = "butz"; group = "users"; mode = "0755"; };
    "/home/butz/.local".d = { user = "butz"; group = "users"; mode = "0755"; };
    "/home/butz/.local/share".d = { user = "butz"; group = "users"; mode = "0755"; };
    "/home/butz/.local/state".d = { user = "butz"; group = "users"; mode = "0755"; };
  };

}
```
