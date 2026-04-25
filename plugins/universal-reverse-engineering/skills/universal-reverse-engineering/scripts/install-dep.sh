#!/usr/bin/env bash
# install-dep.sh — Install a single dependency for universal RE skill
# Usage: install-dep.sh <dependency>
# Exit codes: 0=success  1=failed  2=needs manual action
set -euo pipefail

AVAILABLE_DEPS="java jadx vineflower dex2jar apktool adb class-dump ilspycmd \
                checksec semgrep cppcheck flawfinder bandit gitleaks trufflehog \
                gosec radare2 binwalk strings-bin objdump readelf nm"

usage() {
  cat <<EOF
Usage: install-dep.sh <dependency>

Available dependencies:
  Android:      java, jadx, vineflower, dex2jar, apktool, adb
  iOS/macOS:    class-dump
  .NET:         ilspycmd
  Vuln/SAST:    checksec, semgrep, cppcheck, flawfinder, bandit, gitleaks, trufflehog, gosec
  Binary utils: radare2, binwalk, strings-bin, objdump, readelf, nm
EOF
  exit 0
}

[[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]] && usage

DEP="$1"

# ── Environment ──────────────────────────────────────────────────────────────
OS="unknown"
PKG_MANAGER="none"
HAS_SUDO=false

case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="macos" ;;
esac

if   command -v brew    &>/dev/null; then PKG_MANAGER="brew"
elif command -v apt-get &>/dev/null; then PKG_MANAGER="apt"
elif command -v dnf     &>/dev/null; then PKG_MANAGER="dnf"
elif command -v pacman  &>/dev/null; then PKG_MANAGER="pacman"
elif command -v apk     &>/dev/null; then PKG_MANAGER="apk"
fi

command -v sudo &>/dev/null && HAS_SUDO=true

info()   { echo "[INFO]   $*"; }
ok()     { echo "[OK]     $*"; }
fail()   { echo "[FAIL]   $*" >&2; }
manual() { echo "[MANUAL] Manual step required:" >&2; echo "         $*" >&2; exit 2; }

pkg_install() {
  local pkg="$1"
  case "$PKG_MANAGER" in
    brew)   brew install "$pkg" ;;
    apt)    $( [[ "$HAS_SUDO" == true ]] && echo sudo || echo "" ) apt-get install -y -qq "$pkg" ;;
    dnf)    $( [[ "$HAS_SUDO" == true ]] && echo sudo || echo "" ) dnf install -y "$pkg" ;;
    pacman) $( [[ "$HAS_SUDO" == true ]] && echo sudo || echo "" ) pacman -S --noconfirm "$pkg" ;;
    apk)    $( [[ "$HAS_SUDO" == true ]] && echo sudo || echo "" ) apk add --no-cache "$pkg" ;;
    *)      manual "No package manager found. Install $pkg manually." ;;
  esac
}

download() {
  local url="$1" dest="$2"
  if   command -v curl  &>/dev/null; then curl -fsSL -o "$dest" "$url"
  elif command -v wget  &>/dev/null; then wget -q -O "$dest" "$url"
  else fail "Neither curl nor wget found."; return 1
  fi
}

gh_latest_tag() {
  local repo="$1"
  local api="https://api.github.com/repos/$repo/releases/latest"
  if command -v curl &>/dev/null; then
    curl -fsSL "$api" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
  else
    wget -q -O- "$api" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
  fi
}

add_to_profile() {
  local line="$1"
  local profile=""
  [[ -f "$HOME/.zshrc"   ]] && profile="$HOME/.zshrc"
  [[ -f "$HOME/.bashrc"  ]] && profile="$HOME/.bashrc"
  [[ -z "$profile" && -f "$HOME/.profile" ]] && profile="$HOME/.profile"
  if [[ -n "$profile" ]]; then
    grep -qF "$line" "$profile" 2>/dev/null || echo "$line" >> "$profile"
    info "Added to $profile — run: source $profile"
  else
    info "Add to your shell profile: $line"
  fi
}

# ── Installers ────────────────────────────────────────────────────────────────

install_java() {
  command -v java &>/dev/null && {
    local v; v=$(java -version 2>&1 | head -1 | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
    (( v >= 17 )) && { ok "Java $v already installed"; return; }
  }
  info "Installing Java 17..."
  case "$PKG_MANAGER" in
    brew)   brew install openjdk@17
            add_to_profile 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"' ;;
    apt)    pkg_install "openjdk-17-jdk" ;;
    dnf)    pkg_install "java-17-openjdk-devel" ;;
    pacman) pkg_install "jdk17-openjdk" ;;
    apk)    pkg_install "openjdk17" ;;
    *)      manual "Download Java 17 from https://adoptium.net/" ;;
  esac
}

install_jadx() {
  command -v jadx &>/dev/null && { ok "jadx already installed"; return; }
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install jadx; ok "jadx installed via Homebrew"; return
  fi
  local tag; tag=$(gh_latest_tag "skylot/jadx")
  local version="${tag#v}"
  local url="https://github.com/skylot/jadx/releases/download/${tag}/jadx-${version}.zip"
  local tmp; tmp=$(mktemp /tmp/jadx-XXXXXX.zip)
  info "Downloading jadx $version..."
  download "$url" "$tmp"
  local dir="$HOME/.local/share/jadx"
  rm -rf "$dir"; mkdir -p "$dir"
  unzip -qo "$tmp" -d "$dir"; rm -f "$tmp"
  chmod +x "$dir/bin/jadx" "$dir/bin/jadx-gui" 2>/dev/null || true
  mkdir -p "$HOME/.local/bin"
  ln -sf "$dir/bin/jadx"     "$HOME/.local/bin/jadx"
  ln -sf "$dir/bin/jadx-gui" "$HOME/.local/bin/jadx-gui"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  export PATH="$HOME/.local/bin:$PATH"
  ok "jadx $version installed"
}

install_vineflower() {
  command -v vineflower &>/dev/null && { ok "vineflower already installed"; return; }
  [[ -f "${FERNFLOWER_JAR_PATH:-}" ]] && { ok "Fernflower JAR exists"; return; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install vineflower 2>/dev/null && { ok "vineflower via Homebrew"; return; }
  local tag; tag=$(gh_latest_tag "Vineflower/vineflower")
  local version="${tag#v}"
  local url="https://github.com/Vineflower/vineflower/releases/download/${tag}/vineflower-${version}.jar"
  local dir="$HOME/.local/share/vineflower"
  mkdir -p "$dir"
  info "Downloading Vineflower $version..."
  download "$url" "$dir/vineflower.jar"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/vineflower" <<'WRAP'
#!/usr/bin/env bash
exec java -jar "$HOME/.local/share/vineflower/vineflower.jar" "$@"
WRAP
  chmod +x "$HOME/.local/bin/vineflower"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  add_to_profile "export FERNFLOWER_JAR_PATH=\"$dir/vineflower.jar\""
  ok "Vineflower $version installed"
}

install_dex2jar() {
  command -v d2j-dex2jar &>/dev/null && { ok "dex2jar already installed"; return; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install dex2jar 2>/dev/null && return
  local tag; tag=$(gh_latest_tag "pxb1988/dex2jar") || tag="v2.4"
  local version="${tag#v}"
  local url="https://github.com/pxb1988/dex2jar/releases/download/${tag}/dex-tools-${version}.zip"
  local tmp; tmp=$(mktemp /tmp/dex2jar-XXXXXX.zip)
  info "Downloading dex2jar $version..."
  download "$url" "$tmp" || { url="https://github.com/pxb1988/dex2jar/releases/download/${tag}/dex-tools-v${version}.zip"; download "$url" "$tmp"; }
  local dir="$HOME/.local/share/dex2jar"
  rm -rf "$dir"; mkdir -p "$dir"
  unzip -qo "$tmp" -d "$dir"; rm -f "$tmp"
  local bin_dir; bin_dir=$(find "$dir" -name "d2j-dex2jar.sh" -exec dirname {} \; | head -1)
  [[ -z "$bin_dir" ]] && manual "Extract dex2jar manually: https://github.com/pxb1988/dex2jar/releases"
  chmod +x "$bin_dir"/*.sh 2>/dev/null || true
  mkdir -p "$HOME/.local/bin"
  for s in "$bin_dir"/d2j-*.sh; do ln -sf "$s" "$HOME/.local/bin/$(basename "$s" .sh)"; done
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  ok "dex2jar $version installed"
}

install_apktool() {
  command -v apktool &>/dev/null && { ok "apktool already installed"; return; }
  case "$PKG_MANAGER" in
    brew)   brew install apktool ;;
    apt)    pkg_install "apktool" ;;
    *)      manual "Install apktool: https://apktool.org/docs/install" ;;
  esac
}

install_adb() {
  command -v adb &>/dev/null && { ok "adb already installed"; return; }
  case "$PKG_MANAGER" in
    brew)   brew install android-platform-tools ;;
    apt)    pkg_install "adb" ;;
    dnf)    pkg_install "android-tools" ;;
    pacman) pkg_install "android-tools" ;;
    *)      manual "Install Android Platform Tools: https://developer.android.com/tools/releases/platform-tools" ;;
  esac
}

install_class_dump() {
  command -v class-dump &>/dev/null && { ok "class-dump already installed"; return; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install class-dump 2>/dev/null && return
  local tag; tag=$(gh_latest_tag "nygard/class-dump") || tag="3.5"
  manual "Download class-dump from https://github.com/nygard/class-dump/releases — copy to /usr/local/bin"
}

install_ilspycmd() {
  command -v ilspycmd &>/dev/null && { ok "ilspycmd already installed"; return; }
  if command -v dotnet &>/dev/null; then
    info "Installing ilspycmd via dotnet tool..."
    dotnet tool install -g ilspycmd
    add_to_profile 'export PATH="$HOME/.dotnet/tools:$PATH"'
    ok "ilspycmd installed"
  else
    manual "Install .NET SDK first: https://dotnet.microsoft.com/download  Then: dotnet tool install -g ilspycmd"
  fi
}

install_checksec() {
  command -v checksec &>/dev/null && { ok "checksec already installed"; return; }
  case "$PKG_MANAGER" in
    brew)   brew install checksec ;;
    apt)    pkg_install "checksec" ;;
    *)
      info "Installing checksec via pip..."
      if command -v pip3 &>/dev/null; then pip3 install checksec
      elif command -v pip &>/dev/null; then pip install checksec
      else manual "pip install checksec  OR  https://github.com/slimm609/checksec.sh"
      fi ;;
  esac
}

install_semgrep() {
  command -v semgrep &>/dev/null && { ok "semgrep already installed"; return; }
  if command -v pip3 &>/dev/null; then pip3 install semgrep
  elif command -v pip &>/dev/null; then pip install semgrep
  else manual "pip install semgrep  OR  https://semgrep.dev/docs/getting-started"
  fi
}

install_cppcheck() {
  command -v cppcheck &>/dev/null && { ok "cppcheck already installed"; return; }
  case "$PKG_MANAGER" in
    brew)   brew install cppcheck ;;
    apt)    pkg_install "cppcheck" ;;
    dnf)    pkg_install "cppcheck" ;;
    pacman) pkg_install "cppcheck" ;;
    *)      manual "https://cppcheck.sourceforge.io/" ;;
  esac
}

install_flawfinder() {
  command -v flawfinder &>/dev/null && { ok "flawfinder already installed"; return; }
  if command -v pip3 &>/dev/null; then pip3 install flawfinder
  elif command -v pip &>/dev/null; then pip install flawfinder
  else
    case "$PKG_MANAGER" in
      brew)   brew install flawfinder ;;
      apt)    pkg_install "flawfinder" ;;
      *)      manual "pip install flawfinder" ;;
    esac
  fi
}

install_bandit() {
  command -v bandit &>/dev/null && { ok "bandit already installed"; return; }
  if command -v pip3 &>/dev/null; then pip3 install bandit
  elif command -v pip &>/dev/null; then pip install bandit
  else manual "pip install bandit"
  fi
}

install_gitleaks() {
  command -v gitleaks &>/dev/null && { ok "gitleaks already installed"; return; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install gitleaks && return
  local tag; tag=$(gh_latest_tag "gitleaks/gitleaks")
  local version="${tag#v}"
  local arch; arch=$(uname -m)
  [[ "$arch" == "x86_64" ]] && arch="x64"
  [[ "$arch" == "aarch64" ]] && arch="arm64"
  local url="https://github.com/gitleaks/gitleaks/releases/download/${tag}/gitleaks_${version}_linux_${arch}.tar.gz"
  local tmp; tmp=$(mktemp /tmp/gitleaks-XXXXXX.tar.gz)
  info "Downloading gitleaks $version..."
  download "$url" "$tmp"
  mkdir -p "$HOME/.local/bin"
  tar -xzf "$tmp" -C "$HOME/.local/bin" gitleaks 2>/dev/null || tar -xzf "$tmp" -C "$HOME/.local/bin"
  chmod +x "$HOME/.local/bin/gitleaks"
  rm -f "$tmp"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  ok "gitleaks $version installed"
}

install_trufflehog() {
  command -v trufflehog &>/dev/null && { ok "trufflehog already installed"; return; }
  if command -v pip3 &>/dev/null; then pip3 install trufflehog
  elif command -v pip &>/dev/null; then pip install trufflehog
  else
    [[ "$PKG_MANAGER" == "brew" ]] && brew install trufflehog && return
    manual "pip install trufflehog  OR  https://github.com/trufflesecurity/trufflehog"
  fi
}

install_gosec() {
  command -v gosec &>/dev/null && { ok "gosec already installed"; return; }
  if command -v go &>/dev/null; then
    go install github.com/securego/gosec/v2/cmd/gosec@latest
    add_to_profile 'export PATH="$(go env GOPATH)/bin:$PATH"'
    ok "gosec installed"
  else
    [[ "$PKG_MANAGER" == "brew" ]] && brew install gosec && return
    manual "Install Go first, then: go install github.com/securego/gosec/v2/cmd/gosec@latest"
  fi
}

install_radare2() {
  command -v r2 &>/dev/null && { ok "radare2 already installed"; return; }
  case "$PKG_MANAGER" in
    brew)   brew install radare2 ;;
    apt)    pkg_install "radare2" ;;
    dnf)    pkg_install "radare2" ;;
    pacman) pkg_install "radare2" ;;
    *)      manual "https://rada.re/n/radare2.html — compile from source or download release" ;;
  esac
}

install_binwalk() {
  command -v binwalk &>/dev/null && { ok "binwalk already installed"; return; }
  case "$PKG_MANAGER" in
    brew)   brew install binwalk ;;
    apt)    pkg_install "binwalk" ;;
    *)
      if command -v pip3 &>/dev/null; then pip3 install binwalk
      else manual "pip install binwalk  OR  https://github.com/ReFirmLabs/binwalk"
      fi ;;
  esac
}

install_strings_bin() {
  command -v strings &>/dev/null && { ok "strings already installed"; return; }
  case "$PKG_MANAGER" in
    apt)    pkg_install "binutils" ;;
    dnf)    pkg_install "binutils" ;;
    pacman) pkg_install "binutils" ;;
    brew)   ok "strings comes with Xcode Command Line Tools — run: xcode-select --install" ;;
    *)      manual "Install binutils for your OS" ;;
  esac
}

install_objdump() {
  command -v objdump &>/dev/null && { ok "objdump already installed"; return; }
  case "$PKG_MANAGER" in
    apt|dnf|pacman) pkg_install "binutils" ;;
    brew)           brew install binutils; add_to_profile 'export PATH="/opt/homebrew/opt/binutils/bin:$PATH"' ;;
    *)              manual "Install binutils for your OS" ;;
  esac
}

install_readelf() {
  command -v readelf &>/dev/null && { ok "readelf already installed"; return; }
  case "$PKG_MANAGER" in
    apt|dnf|pacman) pkg_install "binutils" ;;
    brew)           brew install binutils ;;
    *)              manual "Install binutils" ;;
  esac
}

install_nm() {
  command -v nm &>/dev/null && { ok "nm already installed"; return; }
  case "$PKG_MANAGER" in
    apt|dnf|pacman) pkg_install "binutils" ;;
    brew)           ok "nm is part of Xcode Command Line Tools" ;;
    *)              manual "Install binutils" ;;
  esac
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$DEP" in
  java)          install_java ;;
  jadx)          install_jadx ;;
  vineflower|fernflower) install_vineflower ;;
  dex2jar)       install_dex2jar ;;
  apktool)       install_apktool ;;
  adb)           install_adb ;;
  class-dump)    install_class_dump ;;
  ilspycmd)      install_ilspycmd ;;
  checksec)      install_checksec ;;
  semgrep)       install_semgrep ;;
  cppcheck)      install_cppcheck ;;
  flawfinder)    install_flawfinder ;;
  bandit)        install_bandit ;;
  gitleaks)      install_gitleaks ;;
  trufflehog)    install_trufflehog ;;
  gosec)         install_gosec ;;
  radare2)       install_radare2 ;;
  binwalk)       install_binwalk ;;
  strings-bin)   install_strings_bin ;;
  objdump)       install_objdump ;;
  readelf)       install_readelf ;;
  nm)            install_nm ;;
  *)
    echo "Error: Unknown dependency '$DEP'" >&2
    echo "Available: $AVAILABLE_DEPS" >&2
    exit 1 ;;
esac
