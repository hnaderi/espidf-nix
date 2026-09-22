# Sourced by the FHS shell profile. Installs ESP-IDF through eim on first use,
# then activates it in the current shell. eim keeps everything under
# ~/.espressif, with one activation script per version.

idf-use() {
  local version="${1:-$IDF_VERSION}"
  local activate="$HOME/.espressif/tools/activate_idf_$version.sh"

  if [ ! -f "$activate" ]; then
    echo "[esp-idf] installing $version, this downloads several GB"
    # The FHS env already provides the prerequisites, and eim cannot detect a
    # package manager inside it.
    eim install \
      --non-interactive true \
      --skip-prerequisites-check true \
      --idf-versions "$version" \
      --target "${IDF_TARGETS:-all}" || return 1
  fi

  # The activation script decides whether it was sourced by inspecting $0,
  # which is the FHS init script here, so present ourselves as plain bash.
  BASH_ARGV0=bash
  source "$activate" >/dev/null

  [ -x "$IDF_PATH/tools/idf.py" ] || return 1

  # The activation script exposes idf.py as a shell function, which does not
  # survive the exec into the shell, so put the real script on PATH instead.
  export PATH="$IDF_PATH/tools:$PATH"
  export IDF_VERSION="$version"
}

if idf-use "$IDF_VERSION"; then
  echo "ESP-IDF $IDF_VERSION ready, idf.py is on PATH."
  echo "  idf.py set-target esp32"
  echo "  idf.py build"
  echo "  idf.py -p /dev/ttyUSB0 flash monitor"
  echo "  idf-use v6.0.3   # install and switch to another version"
else
  echo "[esp-idf] setup failed, retry with: idf-use $IDF_VERSION" >&2
fi
