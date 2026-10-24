{ config, lib, ... }:

let
  cfg = config.preservation;

  inherit (import ./lib.nix { inherit lib; })
    mkRegularMountUnits
    mkInitrdMountUnits
    mkRegularTmpfilesRules
    mkInitrdTmpfilesRules
    getAllFiles
    isMachineId
    concatPaths
    ;

  # persistent storage paths that preserve the machine-id in the initrd
  machineIdStoragePaths = lib.mapAttrsToList (_: stateConfig: stateConfig.persistentStoragePath) (
    lib.filterAttrs (_: stateConfig: lib.any isMachineId (getAllFiles stateConfig)) cfg.preserveAt
  );
  preservesMachineId = machineIdStoragePaths != [ ];
  machineIdCommitSuppressed = builtins.elem "systemd-machine-id-commit.service" config.systemd.suppressedSystemUnits;
  commitsMachineId = preservesMachineId && !machineIdCommitSuppressed;
in
{
  imports = [
    ./options.nix
  ];

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (preservesMachineId && machineIdCommitSuppressed) ''
      preservation: /etc/machine-id is preserved but systemd-machine-id-commit.service is suppressed,
      the machine-id is written to the persistent file directly and `ConditionFirstBoot` is never met.
      Remove it from `systemd.suppressedSystemUnits` to let preservation commit the machine-id on first boot.
    '';

    boot.initrd.systemd = {
      targets.initrd-preservation = {
        description = "Initrd Preservation Mounts";
        before = [ "initrd.target" ];
        wantedBy = [ "initrd.target" ];
      };
      tmpfiles.settings.preservation = lib.mkMerge (
        lib.flatten (lib.mapAttrsToList mkInitrdTmpfilesRules cfg.preserveAt)
        # systemd only detects first boot if /etc/machine-id is missing or contains
        # "uninitialized", an empty file is treated as initialized
        #
        # tmpfiles writes the argument only when it creates the file, an existing
        # machine-id is never touched
        ++ lib.optionals commitsMachineId (
          map (persistentStoragePath: {
            "${concatPaths [
              "/sysroot"
              persistentStoragePath
              "/etc/machine-id"
            ]}".f.argument =
              "uninitialized";
          }) machineIdStoragePaths
        )
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

      # on first boot systemd mounts a transient machine-id over the "uninitialized"
      # persistent file, which is then committed through the bind-mount or symlink,
      # on every other boot there is nothing to commit
      #
      # an empty assignment resets *all* conditions, including the upstream
      # `ConditionPathIsReadWrite=/etc`, the attrset is serialised in key order
      # so `ConditionPathIsMountPoint` is re-added after the reset
      services.systemd-machine-id-commit.unitConfig = lib.mkIf commitsMachineId {
        ConditionFirstBoot = [
          ""
          "true"
        ];
        ConditionPathIsMountPoint = "/etc/machine-id";
      };
    };

  };
}
