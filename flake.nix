{
  description = "ESP-IDF development shell using eim inside an FHS environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
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

      forAllSystems = nixpkgs.lib.genAttrs (builtins.attrNames eimDist);

      mkFhs =
        {
          system,
          idfVersion ? defaultIdfVersion,
          extraPkgs ? (pkgs: [ ]),
        }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          dist = eimDist.${system};

          eim = pkgs.fetchzip {
            url = "https://github.com/espressif/idf-im-ui/releases/download/v${eimVersion}/eim-cli-${dist.arch}.zip";
            hash = dist.hash;
            stripRoot = false;
          };
        in
        pkgs.buildFHSEnv {
          name = "esp-idf-shell";

          # The toolchains eim installs are prebuilt, dynamically linked
          # binaries, so they need an FHS layout to run.
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

              (python3.withPackages (ps: [
                ps.pip
                ps.virtualenv
              ]))
            ])
            ++ extraPkgs pkgs;

          profile = ''
            export PATH="${eim}:$PATH"
            export IDF_VERSION="''${IDF_VERSION:-${idfVersion}}"
            source ${./setup.sh}
          '';

          runScript = "bash";
        };
    in
    {
      # For other flakes: espidf.lib.mkDevShell { system = ...; ... }
      lib.mkDevShell = args: (mkFhs args).env;

      packages = forAllSystems (system: { default = mkFhs { inherit system; }; });
      devShells = forAllSystems (system: { default = (mkFhs { inherit system; }).env; });
    };
}
