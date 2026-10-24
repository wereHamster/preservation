{ config, lib, ... }:

let
  cfg = config.preservation;

  inherit (import ./lib.nix { inherit lib; })
    mkRegularMountUnits
    mkInitrdMountUnits
    mkRegularTmpfilesRules
    mkInitrdTmpfilesRules
    ;
in
{
  imports = [
    ./options.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # newer nixpkgs removed scripted initrd and with it this option,
        # reading the removed option throws, which means systemd is used
        assertion =
          let
            r = builtins.tryEval config.boot.initrd.systemd.enable;
          in
          !r.success || r.value;
        message = "This module cannot be used with scripted initrd.";
      }
    ];

    boot.initrd.systemd = {
      targets.initrd-preservation = {
        description = "Initrd Preservation Mounts";
        before = [ "initrd.target" ];
        wantedBy = [ "initrd.target" ];
      };
      tmpfiles.settings.preservation = lib.mkMerge (
        lib.flatten (lib.mapAttrsToList mkInitrdTmpfilesRules cfg.preserveAt)
      );
      mounts = lib.flatten (lib.mapAttrsToList mkInitrdMountUnits cfg.preserveAt);
    };

    systemd = {
      targets.preservation = {
        description = "Preservation Mounts";
        before = [ "sysinit.target" ];
        wantedBy = [ "sysinit.target" ];
      };
      tmpfiles.settings.preservation = lib.mkMerge (
        lib.flatten (lib.mapAttrsToList mkRegularTmpfilesRules cfg.preserveAt)
      );
      mounts = lib.flatten (lib.mapAttrsToList mkRegularMountUnits cfg.preserveAt);
    };

  };
}
