# espidf-nix

A Nix flake that gives you an ESP-IDF development shell.

It does not repackage Espressif's toolchains as Nix derivations. Those are
prebuilt, dynamically linked binaries that change with every IDF release, and
keeping derivations for them in sync is the maintenance burden that makes such
flakes rot. Instead this flake builds an FHS sandbox with `buildFHSEnv` and
runs [eim](https://github.com/espressif/idf-im-ui), Espressif's own installer,
inside it. Nix provides the environment, eim provides the toolchains.

## Requirements

- Linux on x86_64 or aarch64. `buildFHSEnv` is Linux only.
- Nix with `nix-command` and `flakes` enabled.

## Usage

```bash
cd your-esp-project
nix develop /path/to/esp-idf-flake
```

The first run installs ESP-IDF and its toolchains into `~/.espressif`, which
takes a while and a few GB. Later runs source the activation script and start
immediately.

```bash
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/ttyUSB0 flash monitor
```

The dev shell replaces itself with a `bash` running inside the FHS sandbox, so
`nix develop --command ...` and direnv's `use flake` do not work with it. For a
one-off command use `nix run`, which passes its arguments on to that bash:

```bash
nix run /path/to/esp-idf-flake -- -c 'idf.py build'
```

## Use from another flake

Add it as an input and take the shell as it comes:

```nix
{
  inputs.espidf.url = "github:hnaderi/espidf-nix";

  outputs = { self, espidf }: {
    devShells.x86_64-linux.default = espidf.devShells.x86_64-linux.default;
  };
}
```

Or build one with your own version and tools through `lib.mkDevShell`:

```nix
devShells.x86_64-linux.default = espidf.lib.mkDevShell {
  system = "x86_64-linux";
  idfVersion = "v6.0.3";
  extraPkgs = pkgs: [ pkgs.qemu pkgs.clang-tools ];
};
```

`extraPkgs` is how you add tools. The shell is an FHS sandbox rather than an
ordinary `mkShell`, so you cannot merge it with a `mkShell` of your own, and
anything not in the sandbox is invisible to the build.

## Configuration

Set these before entering the shell:

| Variable | Default | Meaning |
| --- | --- | --- |
| `IDF_VERSION` | `v6.1` | ESP-IDF tag to install |
| `IDF_TARGETS` | `all` | Comma separated chip targets |

```bash
IDF_VERSION=v5.5.5 IDF_TARGETS=esp32,esp32c6 nix develop
```

Inside the shell, `idf-use` installs a version if needed and switches to it:

```bash
idf-use v6.0.3
```

Installs are keyed by version, so several can coexist and projects can pin
different ones. Tags come from
[esp-idf releases](https://github.com/espressif/esp-idf/releases); eim covers
v5.0 and newer.

`IDF_TARGETS` targets passed to the eim install command.
