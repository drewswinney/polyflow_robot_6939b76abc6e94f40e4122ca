{ config, pkgs, lib, pyEnv, robotConsole, robotApi, rosWorkspace, rosRuntimeEnv, systemRosWorkspace, systemRosRuntimeEnv, launchReplacements, ... }:

let
  user      = "admin";
  # Use values from launchReplacements (loaded from SOPS metadata.json, env vars, or template placeholders)
  password  = launchReplacements.password;
  hostname  = launchReplacements.robotId;
  homeDir   = "/home/${user}";
  githubUser = launchReplacements.githubUser;

  py  = pkgs.python3;   # pinned to 3.12 by flake overlay

  rosPkgs = pkgs.rosPackages.humble;
  ros2pkg = rosPkgs.ros2pkg;
  ros2cli = rosPkgs.ros2cli;
  ros2launch = rosPkgs.ros2launch;
  launch = rosPkgs.launch;
  launch-ros = rosPkgs.launch-ros;
  rclpy = rosPkgs.rclpy;
  ament-index-python = rosPkgs.ament-index-python;
  rosidl-parser = rosPkgs.rosidl-parser;
  rosidl-runtime-py = rosPkgs.rosidl-runtime-py;
  composition-interfaces = rosPkgs.composition-interfaces;
  osrf-pycommon = rosPkgs.osrf-pycommon;
  rpyutils = rosPkgs.rpyutils;
  rcl-interfaces = rosPkgs.rcl-interfaces;
  builtin-interfaces = rosPkgs.builtin-interfaces;
  rmwImplementation = rosPkgs."rmw-implementation";
  rmwCycloneDDS = rosPkgs."rmw-cyclonedds-cpp";
  rmwDdsCommon = rosPkgs."rmw-dds-common";
  rosidlTypesupportCpp = rosPkgs."rosidl-typesupport-cpp";
  rosidlTypesupportC = rosPkgs."rosidl-typesupport-c";
  rosidlTypesupportIntrospectionCpp = rosPkgs."rosidl-typesupport-introspection-cpp";
  rosidlTypesupportIntrospectionC = rosPkgs."rosidl-typesupport-introspection-c";
  rosidlGeneratorPy = rosPkgs."rosidl-generator-py";
  yaml = pkgs.python3Packages."pyyaml";
  empy = pkgs.python3Packages."empy";
  catkin-pkg = pkgs.python3Packages."catkin-pkg";
  rosgraphMsgs = rosPkgs."rosgraph-msgs";
  stdMsgs = rosPkgs."std-msgs";
  sensorMsgs = rosPkgs."sensor-msgs";

  rosRuntimePackages = [
    ros2pkg
    ros2cli
    ros2launch
    launch
    launch-ros
    rclpy
    ament-index-python
    rosidl-parser
    rosidl-runtime-py
    composition-interfaces
    osrf-pycommon
    rpyutils
    builtin-interfaces
    rcl-interfaces
    rmwImplementation
    rmwCycloneDDS
    rmwDdsCommon
    rosidlTypesupportCpp
    rosidlTypesupportC
    rosidlTypesupportIntrospectionCpp
    rosidlTypesupportIntrospectionC
    rosidlGeneratorPy
    rosgraphMsgs
    stdMsgs
    yaml
    sensorMsgs
  ];

  rosPy = pkgs.rosPackages.humble.python3;

  # Use hardcoded site-packages path to avoid Python version object evaluation issues
  pySitePackages = "lib/python3.12/site-packages";

  workspacePythonPath = lib.concatStringsSep ":" (lib.filter (p: p != "") [
    (lib.makeSearchPath rosPy.sitePackages rosRuntimePackages)
    (lib.makeSearchPath rosPy.sitePackages [ rosWorkspace rosRuntimeEnv ])
  ]);

  systemPythonPath = lib.concatStringsSep ":" (lib.filter (p: p != "") [
    (lib.makeSearchPath rosPy.sitePackages rosRuntimePackages)
    (lib.makeSearchPath rosPy.sitePackages [ systemRosWorkspace systemRosRuntimeEnv ])
  ]);

  amentRoots = rosRuntimePackages ++ [ rosWorkspace ];
  systemAmentRoots = rosRuntimePackages ++ [ systemRosWorkspace ];

  amentPrefixPath = lib.concatStringsSep ":" (map (pkg: "${pkg}") amentRoots);
  systemAmentPrefixPath = lib.concatStringsSep ":" (map (pkg: "${pkg}") systemAmentRoots);

  workspaceRuntimeInputs = rosRuntimePackages ++ [ rosWorkspace rosRuntimeEnv ];
  systemRuntimeInputs = rosRuntimePackages ++ [ systemRosWorkspace systemRosRuntimeEnv ];

  workspaceRuntimePrefixes = lib.concatStringsSep " " (map (pkg: "${pkg}") workspaceRuntimeInputs);
  systemRuntimePrefixes = lib.concatStringsSep " " (map (pkg: "${pkg}") systemRuntimeInputs);

  workspaceLibraryPath = lib.makeLibraryPath workspaceRuntimeInputs;
  systemWorkspaceLibraryPath = lib.makeLibraryPath systemRuntimeInputs;

  rosServicesList = lib.concatMapStringsSep "\n" (svc: "  \"${svc}\"") rosServicesToRestart;

  workspaceLauncher = pkgs.writeShellApplication {
    name = "polyflow-workspace-launch";
    runtimeInputs = workspaceRuntimeInputs;
    text = builtins.replaceStrings
      [ "@pythonPath@" "@amentPrefixPath@" "@workspaceLibraryPath@" "@workspaceRuntimePrefixes@" "@rosWorkspace@" ]
      [ workspacePythonPath amentPrefixPath workspaceLibraryPath workspaceRuntimePrefixes (toString rosWorkspace) ]
      (builtins.readFile ./scripts/workspace-launch.sh);
    checkPhase = "echo 'Skipping shellcheck for polyflow-workspace-launch'";
  };

  webrtcLauncher = pkgs.writeShellApplication {
    name = "webrtc-launch";
    runtimeInputs = systemRuntimeInputs;
    text = builtins.replaceStrings
      [ "@pythonPath@" "@amentPrefixPath@" "@workspaceLibraryPath@" "@workspaceRuntimePrefixes@" ]
      [ systemPythonPath systemAmentPrefixPath systemWorkspaceLibraryPath systemRuntimePrefixes ]
      (builtins.readFile ./scripts/webrtc-launch.sh);
  };

  wifiConfPath = "/var/lib/polyflow/wifi.conf";
  rosServicesToRestart = [
    "polyflow-webrtc.service"
  ];

  polyflowRebuildRunner = pkgs.writeShellApplication {
    name = "polyflow-rebuild";
    runtimeInputs = [ pkgs.nixos-rebuild pkgs.git pkgs.nix ];
    text = builtins.replaceStrings
      [ "@githubUser@" "@hostname@" ]
      [ githubUser hostname ]
      (builtins.readFile ./scripts/polyflow-rebuild.sh);
  };

  # SocketCAN (Waveshare 2-CH CAN FD HAT, MCP2517/8FD) defaults; adjust to match wiring.
  canOscillatorHz = 40000000;
  can0InterruptGpio = 25;
  can1InterruptGpio = 24;
  canSpiMaxFrequency = 8000000;
  canBaseBitRate = 500000;
  canFdDataBitRate = 2000000;

  # Switch between hotspot (AP) and client (STA) depending on presence of saved Wi-Fi credentials.
  # Credentials file: /var/lib/polyflow/wifi.conf with lines:
  #   WIFI_SSID="MyNetwork"
  #   WIFI_PSK="supersecret"
  wifiModeSwitch = pkgs.writeShellApplication {
    name = "polyflow-wifi-mode";
    runtimeInputs = [ pkgs.networkmanager pkgs.gawk pkgs.coreutils pkgs.systemd ];
    text = builtins.replaceStrings
      [ "@hostname@" "@wifiConfPath@" "@password@" "@rosServices@" ]
      [ hostname wifiConfPath password rosServicesList ]
      (builtins.readFile ./scripts/wifi-mode.sh);
  };

in
{
  imports = [
    (import ./modules/hardware.nix { inherit lib pkgs; })
    (import ./modules/system-basics.nix { inherit lib pkgs hostname robotConsole user; })
    (import ./modules/packages.nix { inherit pkgs rosPkgs pyEnv; })
    (import ./modules/users.nix { inherit lib user password homeDir; })
    (import ./modules/services.nix {
      inherit lib pkgs hostname wifiConfPath wifiModeSwitch robotApi robotConsole webrtcLauncher
        workspaceLauncher rosWorkspace rosRuntimeEnv systemRosWorkspace systemRosRuntimeEnv polyflowRebuildRunner user homeDir
        rosServicesToRestart password;
    })
  ];

  # SOPS configuration for runtime secrets
  # This allows the system to decrypt secrets at runtime using the age key
  sops = {
    defaultSopsFile = ./metadata.json;
    defaultSopsFormat = "json";

    # Age key file location (should be placed on the robot filesystem)
    age.keyFile = "/var/lib/sops-nix/key.txt";

    # Define secrets that will be decrypted at runtime
    # These are available in /run/secrets/ when the system boots
    secrets = lib.mkIf (builtins.pathExists ./metadata.json) {
      robot-id = { };
      signaling-url = { };
      password = { };
      github-user = { };
      turn-server-url = { };
      turn-server-username = { };
      turn-server-password = { };
    };
  };
}
