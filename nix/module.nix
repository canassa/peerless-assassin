self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.peerless-assassin;
  user = "peerless-assassin";
in
{
  options.services.peerless-assassin = {
    enable = lib.mkEnableOption "the Peerless Assassin cooler display";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "peerless-assassin.packages.\${system}.default";
      description = "The peerless-assassin package to run.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${user} = {
      isSystemUser = true;
      group = user;
    };
    users.groups.${user} = { };

    services.udev.packages = [
      (pkgs.writeTextDir "lib/udev/rules.d/70-peerless-assassin.rules" ''
        # The display. An ACL rather than a group, so other rules can still
        # hand the device to a user group.
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0416", ATTRS{idProduct}=="8001", RUN+="${pkgs.acl}/bin/setfacl -m g:${user}:rw $env{DEVNAME}"
        # CPU package energy, root-only by default. sysfs has no ACLs.
        SUBSYSTEM=="powercap", KERNEL=="intel-rapl:*", RUN+="${pkgs.coreutils}/bin/chgrp ${user} /sys%p/energy_uj", RUN+="${pkgs.coreutils}/bin/chmod g+r /sys%p/energy_uj"
      '')
    ];

    systemd.services.peerless-assassin = {
      description = "Peerless Assassin cooler display";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} run";
        User = user;
        Group = user;
        Restart = "always";
        RestartSec = 2;

        # Needs /dev/hidraw*, and /dev/nvidia* for GPU power, so no
        # PrivateDevices.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = "none";
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
      };
    };
  };
}
