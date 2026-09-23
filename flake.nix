{
  description = "ESP-IDF commands as a package, usable from an ordinary shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      defaultIdfVersion = "v6.1";
      eimVersion = "0.19.0";

      # Prebuilt eim releases: https://github.com/espressif/idf-im-ui/releases
      eimDist = {
        x86_64-linux = {
          arch = "linux-x64";
          hash = "sha256-bg/k1536xfO3apYvcBRqkLTK3fL4i1CWwFhuoTJsH30=";
        };
        aarch64-linux = {
          arch = "linux-aarch64";
          hash = "sha256-kGqO0kP6NnV8YifL4oxhAa0BNV+zTMWOFCcm4zaPKnk=";
        };
      };

      # Commands the package puts on PATH, extend with extraTools.
      defaultTools = [
        "idf.py"
        "idf-install"
        "esptool.py"
        "espefuse.py"
        "espsecure.py"
        "esp-coredump"
        "openocd"
        "eim"
      ];

      forAllSystems = lib.genAttrs (builtins.attrNames eimDist);

      mkEspIdf =
        {
          pkgs ? nixpkgs.legacyPackages.${system},
          system ? pkgs.stdenv.hostPlatform.system,
          idfVersion ? defaultIdfVersion,
          idfTargets ? "all",
          extraPkgs ? (pkgs: [ ]),
          extraTools ? [ ],
        }:
        let
          dist = eimDist.${system} or (throw "espidf-nix: no eim release for ${system}");

          # eim creates the ESP-IDF virtualenv with this python. Pin the version,
          # because the virtualenv is bound to it, and keep the interpreter
          # plain: a withPackages env resolves to a wrapper on some nixpkgs
          # revisions, and a wrapper loses the virtualenv it is called through.
          python = pkgs.python313;

          eim = pkgs.fetchzip {
            url = "https://github.com/espressif/idf-im-ui/releases/download/v${eimVersion}/eim-cli-${dist.arch}.zip";
            hash = dist.hash;
            stripRoot = false;
          };

          # The toolchains eim installs are prebuilt, dynamically linked
          # binaries, so they need an FHS layout to run.
          fhs = pkgs.buildFHSEnv {
            name = "esp-idf-env";

            targetPkgs =
              pkgs:
              (with pkgs; [
                stdenv.cc.cc.lib
                zlib
                ncurses5
                libusb1
                udev
                openssl
                libffi
                dbus
                glib

                git
                cmake
                ninja
                gnumake
                curl
                wget
                unzip
                gnutar
                xz
                which
                flex
                bison
                gperf
                ccache
                dfu-util
              ])
              ++ [ python ]
              ++ extraPkgs pkgs;

            profile = ''
              export PATH="${eim}:$PATH"
              export ESP_IDF_SANDBOX=1
              export IDF_PYTHON_VERSION=${python.pythonVersion}
              export IDF_VERSION="''${IDF_VERSION:-${idfVersion}}"
              export IDF_TARGETS="''${IDF_TARGETS:-${idfTargets}}"
            '';

            # buildFHSEnv passes everything after the executable name on to
            # runScript, so `esp-idf-env idf.py build` runs idf.py in here.
            runScript = pkgs.writeShellScript "esp-idf-dispatch" ''
              source ${./setup.sh}

              # Installing must not activate another version first.
              if [ "''${1:-}" = idf-install ]; then
                version="''${2:-$IDF_VERSION}"
                idf-install "$version" || exit 1
                echo "ESP-IDF $version is installed under ~/.espressif."
                exit 0
              fi

              if ! idf-use "$IDF_VERSION"; then
                echo "[esp-idf] could not set up $IDF_VERSION" >&2
                exit 1
              fi

              [ "$#" -eq 0 ] && exec bash
              exec "$@"
            '';
          };

          bashrc = pkgs.writeText "esp-idf-bashrc" ''
            [ -f /etc/bashrc ] && . /etc/bashrc
            [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
            . ${./setup.sh}

            echo "ESP-IDF $IDF_VERSION, idf.py is on PATH."
            echo "  idf-use v6.0.3   # install and switch to another version"
          '';

          shell = pkgs.writeShellScriptBin "esp-idf-shell" ''
            [ "$#" -eq 0 ] && exec ${fhs}/bin/esp-idf-env bash --init-file ${bashrc}
            exec ${fhs}/bin/esp-idf-env bash "$@"
          '';

          # The sandbox inherits our PATH, so a wrapper for a tool this install
          # does not have would otherwise find itself again and recurse.
          wrap =
            name:
            pkgs.writeShellScriptBin name ''
              if [ -n "''${ESP_IDF_SANDBOX:-}" ]; then
                echo "esp-idf: ESP-IDF ''${IDF_VERSION:-${idfVersion}} has no ${name}" >&2
                exit 127
              fi
              exec ${fhs}/bin/esp-idf-env ${lib.escapeShellArg name} "$@"
            '';
        in
        pkgs.symlinkJoin {
          name = "esp-idf-${idfVersion}";

          # fhs contributes bin/esp-idf-env.
          paths = [
            fhs
            shell
          ]
          ++ map wrap (lib.unique (defaultTools ++ extraTools));

          meta = {
            description = "ESP-IDF ${idfVersion} commands, each running inside an FHS sandbox";
            homepage = "https://github.com/hnaderi/espidf-nix";
            platforms = builtins.attrNames eimDist;
            mainProgram = "esp-idf-shell";
          };
        };

      mkDevShell =
        args:
        let
          pkgs = args.pkgs or nixpkgs.legacyPackages.${args.system};
          idfVersion = args.idfVersion or defaultIdfVersion;
        in
        pkgs.mkShell {
          packages = [ (mkEspIdf args) ];

          shellHook = ''
            echo "ESP-IDF ${idfVersion}: idf.py is on PATH, the first command installs the toolchains."
          '';
        };
    in
    {
      lib = { inherit mkEspIdf mkDevShell; };

      overlays.default = final: _prev: {
        esp-idf = mkEspIdf { pkgs = final; };
      };

      packages = forAllSystems (system: rec {
        esp-idf = mkEspIdf { inherit system; };
        default = esp-idf;
      });

      devShells = forAllSystems (system: {
        default = mkDevShell { inherit system; };
      });
    };
}
