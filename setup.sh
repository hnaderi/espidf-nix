# Sourced inside the FHS sandbox. Installs ESP-IDF through eim on demand and
# loads a version into the current shell. eim keeps everything under
# ~/.espressif, with one activation script per version.

_idf_activate_script() {
  printf '%s\n' "$HOME/.espressif/tools/activate_idf_$1.sh"
}

# Output goes to stderr so that wrappers such as idf.py keep a clean stdout.
idf-install() {
  local version="${1:-$IDF_VERSION}"
  local activate

  if [ -z "$version" ]; then
    echo "[esp-idf] no version given and IDF_VERSION is unset" >&2
    return 1
  fi

  activate="$(_idf_activate_script "$version")"
  [ -f "$activate" ] && return 0

  echo "[esp-idf] installing $version, this downloads several GB" >&2
  # The FHS env already provides the prerequisites, and eim cannot detect a
  # package manager inside it.
  # eim insists on pip being importable by the sandbox python, which carries
  # none, so lend it one for the install alone.
  PYTHONPATH="$IDF_PIP_PATH" eim install \
    --non-interactive true \
    --skip-prerequisites-check true \
    --idf-versions "$version" \
    --target "${IDF_TARGETS:-all}" \
    --config-file-save-path "$HOME/.espressif/eim_config.toml" >&2 || return 1

  [ -f "$activate" ]
}

# Sourcing an activation script defines the tools as shell functions, which do
# not survive an exec. Its -e mode prints the same environment as KEY=VALUE
# lines, so cache that and export it instead. Prints the cache file.
_idf_env_snapshot() {
  local activate cache tmp
  activate="$(_idf_activate_script "$1")"
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/espidf-nix/env-$1"

  if [ ! -s "$cache" ] || [ "$activate" -nt "$cache" ]; then
    tmp="$cache.$$"
    mkdir -p "${cache%/*}" || return 1
    if ! sh "$activate" -e >"$tmp" 2>/dev/null || ! grep -q '^IDF_PATH=' "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    mv "$tmp" "$cache" || return 1
  fi

  printf '%s\n' "$cache"
}

# idf_tools.py lists the directory before it fills it.
_idf_make_python_env() {
  echo "[esp-idf] creating a python $IDF_PYTHON_VERSION env for $1, this takes a minute" >&2
  mkdir -p "$IDF_PYTHON_ENV_PATH"
  /usr/bin/python3 "$IDF_PATH/tools/idf_tools.py" install-python-env >&2
}

idf-use() {
  local version="${1:-$IDF_VERSION}"
  local cache key value idf_path=

  idf-install "$version" || return 1
  cache="$(_idf_env_snapshot "$version")" || return 1

  while IFS='=' read -r key value; do
    case "$key" in
      PATH) idf_path="$value" ;;
      # SYSTEM_PATH is the PATH eim saw at install time and IDF_VERSION its
      # numeric form, ours win over both.
      SYSTEM_PATH | IDF_VERSION | '') ;;
      *) export "$key=$value" ;;
    esac
  done <"$cache"

  [ -f "$IDF_PATH/tools/idf.py" ] || return 1

  # A virtualenv keeps its packages in lib/python<version> and only the python
  # that created it looks there. eim built one with the python of whoever
  # installed this version, so when ours differs keep a second one beside it,
  # instead of two projects rebuilding a single venv in turn.
  if [ ! -d "$IDF_PYTHON_ENV_PATH/lib/python$IDF_PYTHON_VERSION" ]; then
    export IDF_PYTHON_ENV_PATH="$IDF_PYTHON_ENV_PATH-py$IDF_PYTHON_VERSION"
    [ -d "$IDF_PYTHON_ENV_PATH/lib/python$IDF_PYTHON_VERSION" ] ||
      _idf_make_python_env "$version" ||
      return 1
  fi

  # The activation script exposes idf.py as a shell function, so put the real
  # script on PATH instead.
  export PATH="$IDF_PATH/tools:$IDF_PYTHON_ENV_PATH/bin:$idf_path:$PATH"
  export VIRTUAL_ENV="$IDF_PYTHON_ENV_PATH"
  export IDF_VERSION="$version"
  unset PYTHONHOME
}
