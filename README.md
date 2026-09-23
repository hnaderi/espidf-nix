# espidf-nix

A Nix package that gives you `idf.py` and the rest of ESP-IDF on PATH, in an
ordinary shell.

It uses the official prebuilt binaries from the espressif using 
[eim](https://github.com/espressif/idf-im-ui), Espressif's own installer, 
in an FHS sandbox and providing wrapper scripts instead. 
So you can run whatever official versions available through eim on nixos.

## Requirements

- Linux on x86_64 or aarch64. `buildFHSEnv` is Linux only.
- Nix with `nix-command` and `flakes` enabled.

## Use it in your own flake

Through the overlay, in a shell of your own:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.espidf.url = "github:hnaderi/espidf-nix";

  outputs =
    { nixpkgs, espidf, ... }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ espidf.overlays.default ];
      };
    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [
          pkgs.esp-idf
          pkgs.clang-tools
          pkgs.just
        ];
      };
    };
}
```

`espidf.packages.${system}.default` is the same package if you would rather not
use the overlay. To pick a version or add commands, build it with `lib.mkEspIdf`:

```nix
packages = [
  (espidf.lib.mkEspIdf {
    inherit pkgs;
    idfVersion = "v6.0.3";
    extraTools = [ "xtensa-esp32-elf-gdb" ];
    extraPkgs = pkgs: [ pkgs.qemu ];
  })
];
```

| Argument | Default | Meaning |
| --- | --- | --- |
| `pkgs` | none | Nixpkgs to build against, or pass `system` instead |
| `idfVersion` | `v6.1` | ESP-IDF tag to install |
| `idfTargets` | `all` | Comma separated chip targets |
| `extraTools` | `[ ]` | More commands to put on PATH |
| `extraPkgs` | `pkgs: [ ]` | More packages inside the sandbox |

There is also `espidf.lib.mkDevShell`, taking the same arguments, for a ready
made `mkShell` around the package, and `devShells.${system}.default` for the
one it builds with the defaults.

## What the package puts on PATH

`idf.py`, `esptool.py`, `espefuse.py`, `espsecure.py`, `esp-coredump`,
`openocd`, `eim`, and:

- `idf-install [version]` installs a version without switching to it.
- `esp-idf-env <command> [args]` runs any command from the ESP-IDF
  environment, wrapper or not: `esp-idf-env riscv32-esp-elf-gdb`,
  `esp-idf-env printenv IDF_PATH`.
- `esp-idf-shell` opens an interactive shell inside the sandbox, where the
  whole environment is on PATH at once. `nix run github:hnaderi/espidf-nix --
  -c 'idf.py build'` is the same shell.

Anything you reach for often is better added through `extraTools`, which gives
it a wrapper of its own, so your editor or `Makefile` can call it directly.

## Everyday use

```bash
cd your-esp-project
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/ttyUSB0 flash monitor
```

The first command installs ESP-IDF and its toolchains into `~/.espressif`,
which takes a while and a few GB. Run `idf-install` to get it over with.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `IDF_VERSION` | `v6.1` | ESP-IDF tag to use |
| `IDF_TARGETS` | `all` | Comma separated chip targets to install |

Both default to whatever the package was built with, and both can be set per
command:

```bash
IDF_VERSION=v6.0.3 idf.py build
```

Installs are keyed by version, so several can coexist and projects can pin
different ones. Tags come from
[esp-idf releases](https://github.com/espressif/esp-idf/releases); eim covers
v5.0 and newer. Inside `esp-idf-shell`, `idf-use v6.0.3` switches the running
shell over.

## How it works

`eim` installs each ESP-IDF version under `~/.espressif` and writes an
activation script per version. A wrapper such as `idf.py` runs
`esp-idf-env idf.py`, which enters the bwrap sandbox, exports that version's
environment and execs the real `idf.py`. That environment is cached under
`~/.cache/espidf-nix` rather than sourced every time, so a command run stays fast.

The sandbox keeps the environment it was called with and binds `/nix`, so the
packages of your surrounding shell stay visible and usable inside it. The
reverse does not hold: the binaries under `~/.espressif` are the ones that need
the FHS layout, so they only run through a wrapper, `esp-idf-env`, or
`esp-idf-shell`.
