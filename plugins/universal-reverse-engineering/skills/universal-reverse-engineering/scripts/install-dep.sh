#!/usr/bin/env bash
# install-dep.sh — Install a single dependency for universal RE skill
# Usage: install-dep.sh <dependency>
# Exit codes: 0=success  1=failed  2=needs manual action
set -euo pipefail

AVAILABLE_DEPS="java jadx vineflower dex2jar apktool adb \
                class-dump ipsw frida \
                ilspycmd dotnet monodis de4dot \
                ghidra cutter retdec \
                gdb pwndbg gef peda lldb \
                pwntools ropgadget ropper one-gadget angr \
                valgrind volatility3 patchelf seccomp-tools afl \
                checksec semgrep cppcheck flawfinder bandit gitleaks trufflehog gosec \
                radare2 binwalk upx \
                strace ltrace \
                strings-bin objdump readelf nm xxd unzip file-cmd \
                xcode-cli"

usage() {
  cat <<EOF
Usage: install-dep.sh <dependency>

Android:        java, jadx, vineflower, dex2jar, apktool, adb
iOS / macOS:    class-dump, ipsw, frida, xcode-cli, lldb
.NET:           ilspycmd, dotnet, monodis, de4dot
Decompilers:    ghidra, cutter, retdec
Debuggers:      gdb, pwndbg, gef, peda, lldb
Exploit Dev:    pwntools, ropgadget, ropper, one-gadget, angr
Memory/Fuzz:    valgrind, volatility3, patchelf, seccomp-tools, afl
SAST / Vuln:    checksec, semgrep, cppcheck, flawfinder, bandit,
                gitleaks, trufflehog, gosec
Binary utils:   radare2, binwalk, upx, strings-bin, objdump, readelf,
                nm, xxd, unzip, file-cmd, strace, ltrace

Windows-only tools (install manually on Windows):
  Immunity Debugger — https://www.immunityinc.com/products/debugger/
  x64dbg / x32dbg   — https://x64dbg.com
  WinDbg             — Microsoft Store or Windows SDK
iOS / macOS:  class-dump, ipsw, frida, xcode-cli (otool/nm/lipo/codesign)
.NET:         ilspycmd, dotnet, monodis, de4dot
SAST / Vuln:  checksec, semgrep, cppcheck, flawfinder, bandit,
              gitleaks, trufflehog, gosec
Binary utils: radare2, binwalk, upx, strings-bin, objdump, readelf, nm, xxd, unzip, file-cmd
Linux tracing: strace, ltrace
EOF
  exit 0
}

[[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]] && usage

DEP="$1"

# ── Environment ──────────────────────────────────────────────────────────────
OS="unknown"
PKG_MANAGER="none"
HAS_SUDO=false
ARCH=$(uname -m)

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
manual() { echo "[MANUAL] $*" >&2; exit 2; }

pkg_install() {
  local pkg="$1"
  case "$PKG_MANAGER" in
    brew)
      brew install "$pkg" ;;
    apt)
      if [[ "$HAS_SUDO" == true ]]; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
      else
        manual "Run: sudo apt-get install -y $pkg"
      fi ;;
    dnf)
      if [[ "$HAS_SUDO" == true ]]; then sudo dnf install -y "$pkg"
      else manual "Run: sudo dnf install -y $pkg"; fi ;;
    pacman)
      if [[ "$HAS_SUDO" == true ]]; then sudo pacman -S --noconfirm "$pkg"
      else manual "Run: sudo pacman -S $pkg"; fi ;;
    apk)
      if [[ "$HAS_SUDO" == true ]]; then sudo apk add --no-cache "$pkg"
      else apk add --no-cache "$pkg"; fi ;;
    *)
      manual "No supported package manager found. Install $pkg manually." ;;
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
  [[ -z "$profile" && -f "$HOME/.bashrc"  ]] && profile="$HOME/.bashrc"
  [[ -z "$profile" && -f "$HOME/.profile" ]] && profile="$HOME/.profile"
  if [[ -n "$profile" ]]; then
    grep -qF "$line" "$profile" 2>/dev/null || echo "$line" >> "$profile"
    info "Added to $profile — run: source $profile"
  else
    info "Add to your shell profile: $line"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# ANDROID
# ═════════════════════════════════════════════════════════════════════════════

install_java() {
  if command -v java &>/dev/null; then
    local v; v=$(java -version 2>&1 | head -1 | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
    if [[ -n "$v" ]] && (( v >= 17 )); then
      ok "Java $v already installed"; return 0
    fi
    info "Java $v found but <17, upgrading..."
  fi
  info "Installing Java JDK 17..."
  case "$PKG_MANAGER" in
    brew)
      brew install openjdk@17
      add_to_profile 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"' ;;
    apt)    pkg_install "openjdk-17-jdk" ;;
    dnf)    pkg_install "java-17-openjdk-devel" ;;
    pacman) pkg_install "jdk17-openjdk" ;;
    apk)    pkg_install "openjdk17" ;;
    *)      manual "Download Java 17 from https://adoptium.net/" ;;
  esac
  command -v java &>/dev/null && ok "Java installed: $(java -version 2>&1 | head -1)" || \
    { fail "Java install may need PATH update. Re-open terminal and retry."; exit 1; }
}

install_jadx() {
  command -v jadx &>/dev/null && { ok "jadx already installed: $(jadx --version 2>/dev/null)"; return 0; }
  if [[ "$PKG_MANAGER" == "brew" ]]; then brew install jadx; ok "jadx installed via Homebrew"; return 0; fi
  info "Downloading jadx from GitHub releases..."
  local tag; tag=$(gh_latest_tag "skylot/jadx")
  local version="${tag#v}"
  local url="https://github.com/skylot/jadx/releases/download/${tag}/jadx-${version}.zip"
  local tmp; tmp=$(mktemp /tmp/jadx-XXXXXX.zip)
  download "$url" "$tmp"
  local dir="$HOME/.local/share/jadx"
  rm -rf "$dir"; mkdir -p "$dir"
  unzip -qo "$tmp" -d "$dir"; rm -f "$tmp"
  chmod +x "$dir/bin/jadx" "$dir/bin/jadx-gui" 2>/dev/null || true
  mkdir -p "$HOME/.local/bin"
  ln -sf "$dir/bin/jadx"     "$HOME/.local/bin/jadx"
  ln -sf "$dir/bin/jadx-gui" "$HOME/.local/bin/jadx-gui"
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  ok "jadx $version installed"
}

install_vineflower() {
  command -v vineflower &>/dev/null && { ok "vineflower already installed"; return 0; }
  command -v fernflower &>/dev/null && { ok "fernflower already installed"; return 0; }
  for c in "${FERNFLOWER_JAR_PATH:-}" "$HOME/.local/share/vineflower/vineflower.jar" \
            "$HOME/vineflower/vineflower.jar" "$HOME/fernflower/build/libs/fernflower.jar"; do
    [[ -n "$c" && -f "$c" ]] && { ok "Fernflower JAR found: $c"; return 0; }
  done
  [[ "$PKG_MANAGER" == "brew" ]] && brew install vineflower 2>/dev/null && { ok "vineflower via Homebrew"; return 0; } || true
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
  export PATH="$HOME/.local/bin:$PATH"
  export FERNFLOWER_JAR_PATH="$dir/vineflower.jar"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  add_to_profile "export FERNFLOWER_JAR_PATH=\"$dir/vineflower.jar\""
  ok "Vineflower $version installed"
}

install_dex2jar() {
  command -v d2j-dex2jar &>/dev/null && { ok "dex2jar already installed"; return 0; }
  command -v d2j-dex2jar.sh &>/dev/null && { ok "dex2jar already installed"; return 0; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install dex2jar 2>/dev/null && return 0 || true
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
  [[ -z "$bin_dir" ]] && manual "Extract dex2jar manually from https://github.com/pxb1988/dex2jar/releases"
  chmod +x "$bin_dir"/*.sh 2>/dev/null || true
  mkdir -p "$HOME/.local/bin"
  for s in "$bin_dir"/d2j-*.sh; do ln -sf "$s" "$HOME/.local/bin/$(basename "$s" .sh)"; done
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  ok "dex2jar $version installed"
}

install_apktool() {
  command -v apktool &>/dev/null && { ok "apktool already installed"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install apktool ;;
    apt)    pkg_install "apktool" ;;
    dnf)    pkg_install "apktool" ;;
    *)      manual "Install apktool from https://apktool.org/docs/install" ;;
  esac
  ok "apktool installed"
}

install_adb() {
  command -v adb &>/dev/null && { ok "adb already installed"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install android-platform-tools ;;
    apt)    pkg_install "adb" ;;
    dnf)    pkg_install "android-tools" ;;
    pacman) pkg_install "android-tools" ;;
    *)      manual "Install Android Platform Tools: https://developer.android.com/tools/releases/platform-tools" ;;
  esac
}

# ═════════════════════════════════════════════════════════════════════════════
# iOS / macOS
# ═════════════════════════════════════════════════════════════════════════════

install_xcode_cli() {
  # otool, nm, lipo, codesign, strings, file, ar all come from Xcode CLI Tools
  if [[ "$OS" != "macos" ]]; then
    info "xcode-cli is macOS-only. On Linux, these tools come from binutils."
    install_strings_bin; install_nm; install_objdump
    return 0
  fi
  if command -v otool &>/dev/null; then
    ok "Xcode Command Line Tools already installed (otool found)"
    return 0
  fi
  info "Installing Xcode Command Line Tools..."
  info "A dialog will appear — click 'Install' and wait for it to finish."
  xcode-select --install 2>/dev/null || true
  info "Re-run after installation completes. Waiting 5s..."
  sleep 5
  command -v otool &>/dev/null && ok "Xcode CLI Tools installed" || \
    info "If the dialog didn't appear, run: sudo xcode-select --reset"
}

install_class_dump() {
  command -v class-dump &>/dev/null && { ok "class-dump already installed"; return 0; }
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install class-dump 2>/dev/null && { ok "class-dump via Homebrew"; return 0; } || true
  fi
  info "Downloading class-dump from GitHub..."
  local tag; tag=$(gh_latest_tag "nygard/class-dump") || tag="3.5"
  # class-dump releases are macOS binaries
  if [[ "$OS" == "macos" ]]; then
    local url="https://github.com/nygard/class-dump/releases/download/v${tag#v}/class-dump-${tag#v}.tar.gz"
    local tmp; tmp=$(mktemp -d /tmp/class-dump-XXXXXX)
    download "$url" "$tmp/class-dump.tar.gz" 2>/dev/null || \
      manual "Download class-dump from https://github.com/nygard/class-dump/releases and place in /usr/local/bin"
    tar -xzf "$tmp/class-dump.tar.gz" -C "$tmp" 2>/dev/null || true
    local bin; bin=$(find "$tmp" -name "class-dump" -type f | head -1)
    if [[ -n "$bin" ]]; then
      mkdir -p "$HOME/.local/bin"
      cp "$bin" "$HOME/.local/bin/class-dump"
      chmod +x "$HOME/.local/bin/class-dump"
      add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
      ok "class-dump installed"
    else
      manual "Download class-dump from https://github.com/nygard/class-dump/releases"
    fi
    rm -rf "$tmp"
  else
    manual "class-dump is macOS-only. On Linux use readelf/nm for ELF binaries."
  fi
}

install_ipsw() {
  command -v ipsw &>/dev/null && { ok "ipsw already installed"; return 0; }
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install blacktop/tap/ipsw && { ok "ipsw installed via Homebrew"; return 0; }
  fi
  info "Downloading ipsw from GitHub releases..."
  local tag; tag=$(gh_latest_tag "blacktop/ipsw")
  local version="${tag#v}"
  local arch_str=""
  case "$ARCH" in
    x86_64)  arch_str="amd64" ;;
    aarch64|arm64) arch_str="arm64" ;;
    *) manual "Unsupported architecture: $ARCH — download from https://github.com/blacktop/ipsw/releases" ;;
  esac
  local os_str="Linux"
  [[ "$OS" == "macos" ]] && os_str="macOS"
  local url="https://github.com/blacktop/ipsw/releases/download/${tag}/ipsw_${version}_${os_str}_${arch_str}.tar.gz"
  local tmp; tmp=$(mktemp /tmp/ipsw-XXXXXX.tar.gz)
  download "$url" "$tmp"
  mkdir -p "$HOME/.local/bin"
  tar -xzf "$tmp" -C "$HOME/.local/bin" ipsw 2>/dev/null || tar -xzf "$tmp" -C "$HOME/.local/bin"
  chmod +x "$HOME/.local/bin/ipsw"
  rm -f "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  ok "ipsw $version installed"
}

install_frida() {
  command -v frida &>/dev/null && { ok "frida already installed: $(frida --version 2>/dev/null)"; return 0; }
  info "Installing frida-tools via pip..."
  if command -v pip3 &>/dev/null; then
    pip3 install frida-tools
  elif command -v pip &>/dev/null; then
    pip install frida-tools
  else
    manual "Install pip first, then: pip install frida-tools  See: https://frida.re/docs/installation/"
  fi
  command -v frida &>/dev/null && ok "frida installed: $(frida --version 2>/dev/null)" || \
    add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
}

# ═════════════════════════════════════════════════════════════════════════════
# .NET
# ═════════════════════════════════════════════════════════════════════════════

install_dotnet() {
  command -v dotnet &>/dev/null && { ok ".NET SDK already installed: $(dotnet --version 2>/dev/null)"; return 0; }
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install --cask dotnet-sdk && { ok ".NET SDK installed via Homebrew"; return 0; }
  fi
  info "Installing .NET SDK via Microsoft script..."
  if [[ "$OS" == "linux" ]]; then
    local tmp; tmp=$(mktemp /tmp/dotnet-install-XXXXXX.sh)
    download "https://dot.net/v1/dotnet-install.sh" "$tmp"
    chmod +x "$tmp"
    bash "$tmp" --channel LTS --install-dir "$HOME/.dotnet"
    rm -f "$tmp"
    export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
    add_to_profile 'export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"'
    ok ".NET SDK installed to ~/.dotnet"
  else
    manual "Download .NET SDK from https://dotnet.microsoft.com/download"
  fi
}

install_ilspycmd() {
  command -v ilspycmd &>/dev/null && { ok "ilspycmd already installed"; return 0; }
  if ! command -v dotnet &>/dev/null; then
    info "dotnet SDK not found — installing it first..."
    install_dotnet
  fi
  if command -v dotnet &>/dev/null; then
    info "Installing ilspycmd via dotnet tool..."
    dotnet tool install -g ilspycmd 2>/dev/null || dotnet tool update -g ilspycmd
    export PATH="$HOME/.dotnet/tools:$PATH"
    add_to_profile 'export PATH="$HOME/.dotnet/tools:$PATH"'
    command -v ilspycmd &>/dev/null && ok "ilspycmd installed" || \
      manual "Run: dotnet tool install -g ilspycmd   (then restart terminal)"
  else
    manual "Install .NET SDK first: https://dotnet.microsoft.com/download  Then: dotnet tool install -g ilspycmd"
  fi
}

install_monodis() {
  command -v monodis &>/dev/null && { ok "monodis already installed"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install mono && ok "mono (monodis) installed via Homebrew" ;;
    apt)    pkg_install "mono-utils" && ok "monodis installed" ;;
    dnf)    pkg_install "mono-core" && ok "monodis installed" ;;
    pacman) pkg_install "mono" && ok "monodis installed" ;;
    *)      manual "Install Mono from https://www.mono-project.com/download/stable/" ;;
  esac
}

install_de4dot() {
  command -v de4dot &>/dev/null && { ok "de4dot already installed"; return 0; }
  info "Downloading de4dot from GitHub releases..."
  local tag; tag=$(gh_latest_tag "de4dot/de4dot") || tag="v3.1.41592.3405"
  local os_str="linux"
  [[ "$OS" == "macos" ]] && os_str="osx"
  local arch_str="x64"
  [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && arch_str="arm64"
  local url="https://github.com/de4dot/de4dot/releases/download/${tag}/de4dot-${os_str}-${arch_str}.tar.gz"
  local tmp; tmp=$(mktemp /tmp/de4dot-XXXXXX.tar.gz)
  download "$url" "$tmp" 2>/dev/null || \
    manual "Download de4dot from https://github.com/de4dot/de4dot/releases and place in ~/.local/bin"
  mkdir -p "$HOME/.local/bin"
  tar -xzf "$tmp" -C "$HOME/.local/bin" 2>/dev/null || true
  chmod +x "$HOME/.local/bin/de4dot" 2>/dev/null || true
  rm -f "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  command -v de4dot &>/dev/null && ok "de4dot installed" || \
    manual "Place de4dot binary in ~/.local/bin/ from https://github.com/de4dot/de4dot/releases"
}

# ═════════════════════════════════════════════════════════════════════════════
# VULNERABILITY / SAST
# ═════════════════════════════════════════════════════════════════════════════

install_checksec() {
  command -v checksec &>/dev/null && { ok "checksec already installed"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install checksec && return 0 ;;
    apt)    pkg_install "checksec" 2>/dev/null && return 0 || true ;;
    *)      true ;;
  esac
  info "Installing checksec via pip..."
  if command -v pip3 &>/dev/null; then pip3 install checksec
  elif command -v pip &>/dev/null; then pip install checksec
  else
    info "Trying direct install from GitHub..."
    local url="https://raw.githubusercontent.com/slimm609/checksec.sh/2.7.1/checksec"
    mkdir -p "$HOME/.local/bin"
    download "$url" "$HOME/.local/bin/checksec"
    chmod +x "$HOME/.local/bin/checksec"
    export PATH="$HOME/.local/bin:$PATH"
    add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  fi
  ok "checksec installed"
}

install_semgrep() {
  command -v semgrep &>/dev/null && { ok "semgrep already installed: $(semgrep --version 2>/dev/null)"; return 0; }
  if command -v pip3 &>/dev/null; then pip3 install semgrep
  elif command -v pip &>/dev/null; then pip install semgrep
  else manual "pip install semgrep  OR  https://semgrep.dev/docs/getting-started"
  fi
  ok "semgrep installed"
}

install_cppcheck() {
  command -v cppcheck &>/dev/null && { ok "cppcheck already installed"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install cppcheck ;;
    apt)    pkg_install "cppcheck" ;;
    dnf)    pkg_install "cppcheck" ;;
    pacman) pkg_install "cppcheck" ;;
    *)      manual "https://cppcheck.sourceforge.io/" ;;
  esac
  ok "cppcheck installed"
}

install_flawfinder() {
  command -v flawfinder &>/dev/null && { ok "flawfinder already installed"; return 0; }
  if command -v pip3 &>/dev/null; then pip3 install flawfinder
  elif command -v pip &>/dev/null; then pip install flawfinder
  else
    case "$PKG_MANAGER" in
      brew)   brew install flawfinder ;;
      apt)    pkg_install "flawfinder" ;;
      *)      manual "pip install flawfinder" ;;
    esac
  fi
  ok "flawfinder installed"
}

install_bandit() {
  command -v bandit &>/dev/null && { ok "bandit already installed"; return 0; }
  if command -v pip3 &>/dev/null; then pip3 install bandit
  elif command -v pip &>/dev/null; then pip install bandit
  else manual "pip install bandit"
  fi
  ok "bandit installed"
}

install_gitleaks() {
  command -v gitleaks &>/dev/null && { ok "gitleaks already installed"; return 0; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install gitleaks && return 0
  local tag; tag=$(gh_latest_tag "gitleaks/gitleaks")
  local version="${tag#v}"
  local arch_str="x64"
  [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && arch_str="arm64"
  local os_str="linux"
  [[ "$OS" == "macos" ]] && os_str="darwin"
  local url="https://github.com/gitleaks/gitleaks/releases/download/${tag}/gitleaks_${version}_${os_str}_${arch_str}.tar.gz"
  local tmp; tmp=$(mktemp /tmp/gitleaks-XXXXXX.tar.gz)
  info "Downloading gitleaks $version..."
  download "$url" "$tmp"
  mkdir -p "$HOME/.local/bin"
  tar -xzf "$tmp" -C "$HOME/.local/bin" gitleaks 2>/dev/null || tar -xzf "$tmp" -C "$HOME/.local/bin"
  chmod +x "$HOME/.local/bin/gitleaks"
  rm -f "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  ok "gitleaks $version installed"
}

install_trufflehog() {
  command -v trufflehog &>/dev/null && { ok "trufflehog already installed"; return 0; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install trufflehog 2>/dev/null && return 0 || true
  # Try pip first
  if command -v pip3 &>/dev/null; then pip3 install trufflehog 2>/dev/null && { ok "trufflehog installed via pip"; return 0; } || true
  fi
  # GitHub binary release
  local tag; tag=$(gh_latest_tag "trufflesecurity/trufflehog")
  local version="${tag#v}"
  local arch_str="amd64"
  [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && arch_str="arm64"
  local os_str="linux"
  [[ "$OS" == "macos" ]] && os_str="darwin"
  local url="https://github.com/trufflesecurity/trufflehog/releases/download/${tag}/trufflehog_${version}_${os_str}_${arch_str}.tar.gz"
  local tmp; tmp=$(mktemp /tmp/trufflehog-XXXXXX.tar.gz)
  info "Downloading trufflehog $version..."
  download "$url" "$tmp"
  mkdir -p "$HOME/.local/bin"
  tar -xzf "$tmp" -C "$HOME/.local/bin" trufflehog 2>/dev/null || tar -xzf "$tmp" -C "$HOME/.local/bin"
  chmod +x "$HOME/.local/bin/trufflehog"
  rm -f "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  ok "trufflehog $version installed"
}

install_gosec() {
  command -v gosec &>/dev/null && { ok "gosec already installed"; return 0; }
  if command -v go &>/dev/null; then
    go install github.com/securego/gosec/v2/cmd/gosec@latest
    add_to_profile 'export PATH="$(go env GOPATH)/bin:$PATH"'
    ok "gosec installed via go install"
    return 0
  fi
  [[ "$PKG_MANAGER" == "brew" ]] && brew install gosec 2>/dev/null && return 0 || true
  # GitHub binary release
  local tag; tag=$(gh_latest_tag "securego/gosec")
  local version="${tag#v}"
  local arch_str="amd64"
  [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && arch_str="arm64"
  local os_str="linux"
  [[ "$OS" == "macos" ]] && os_str="darwin"
  local url="https://github.com/securego/gosec/releases/download/${tag}/gosec_${version}_${os_str}_${arch_str}.tar.gz"
  local tmp; tmp=$(mktemp /tmp/gosec-XXXXXX.tar.gz)
  info "Downloading gosec $version..."
  download "$url" "$tmp"
  mkdir -p "$HOME/.local/bin"
  tar -xzf "$tmp" -C "$HOME/.local/bin" gosec 2>/dev/null || tar -xzf "$tmp" -C "$HOME/.local/bin"
  chmod +x "$HOME/.local/bin/gosec"
  rm -f "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  ok "gosec $version installed"
}

# ═════════════════════════════════════════════════════════════════════════════
# BINARY UTILS
# ═════════════════════════════════════════════════════════════════════════════

install_radare2() {
  command -v r2 &>/dev/null && { ok "radare2 already installed: $(r2 -v 2>/dev/null | head -1)"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install radare2 ;;
    apt)    pkg_install "radare2" ;;
    dnf)    pkg_install "radare2" ;;
    pacman) pkg_install "radare2" ;;
    apk)    pkg_install "radare2" ;;
    *)
      info "Attempting radare2 install via r2env script..."
      local tmp; tmp=$(mktemp /tmp/r2install-XXXXXX.sh)
      download "https://raw.githubusercontent.com/radareorg/radare2/master/sys/install.sh" "$tmp" && \
        bash "$tmp" && rm -f "$tmp" || \
        manual "Install radare2 from https://rada.re/n/radare2.html" ;;
  esac
  command -v r2 &>/dev/null && ok "radare2 installed" || fail "radare2 install may have failed"
}

install_binwalk() {
  command -v binwalk &>/dev/null && { ok "binwalk already installed"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install binwalk ;;
    apt)    pkg_install "binwalk" ;;
    dnf)    pkg_install "binwalk" ;;
    *)
      if command -v pip3 &>/dev/null; then pip3 install binwalk
      else manual "pip install binwalk  OR  https://github.com/ReFirmLabs/binwalk"
      fi ;;
  esac
  ok "binwalk installed"
}

install_upx() {
  command -v upx &>/dev/null && { ok "upx already installed: $(upx --version 2>/dev/null | head -1)"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install upx ;;
    apt)    pkg_install "upx" ;;
    dnf)    pkg_install "upx" ;;
    pacman) pkg_install "upx" ;;
    apk)    pkg_install "upx" ;;
    *)
      local tag; tag=$(gh_latest_tag "upx/upx")
      local version="${tag#v}"
      local arch_str="amd64"
      [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && arch_str="arm64"
      local os_str="linux"
      [[ "$OS" == "macos" ]] && { manual "Download upx from https://github.com/upx/upx/releases"; return; }
      local url="https://github.com/upx/upx/releases/download/${tag}/upx-${version}-${arch_str}_${os_str}.tar.xz"
      local tmp; tmp=$(mktemp /tmp/upx-XXXXXX.tar.xz)
      download "$url" "$tmp"
      local extract_dir; extract_dir=$(mktemp -d)
      tar -xJf "$tmp" -C "$extract_dir" 2>/dev/null || tar -xf "$tmp" -C "$extract_dir"
      local bin; bin=$(find "$extract_dir" -name "upx" -type f | head -1)
      mkdir -p "$HOME/.local/bin"
      cp "$bin" "$HOME/.local/bin/upx" && chmod +x "$HOME/.local/bin/upx"
      rm -rf "$tmp" "$extract_dir"
      add_to_profile 'export PATH="$HOME/.local/bin:$PATH"' ;;
  esac
  ok "upx installed"
}

install_strace() {
  command -v strace &>/dev/null && { ok "strace already installed"; return 0; }
  if [[ "$OS" == "macos" ]]; then
    info "strace is Linux-only. On macOS use: dtruss (sudo dtruss <binary>)"
    return 0
  fi
  case "$PKG_MANAGER" in
    apt)    pkg_install "strace" ;;
    dnf)    pkg_install "strace" ;;
    pacman) pkg_install "strace" ;;
    apk)    pkg_install "strace" ;;
    *)      manual "Install strace via your package manager" ;;
  esac
  ok "strace installed"
}

install_ltrace() {
  command -v ltrace &>/dev/null && { ok "ltrace already installed"; return 0; }
  if [[ "$OS" == "macos" ]]; then
    info "ltrace is Linux-only. On macOS use: dtrace or frida for library tracing"
    return 0
  fi
  case "$PKG_MANAGER" in
    apt)    pkg_install "ltrace" ;;
    dnf)    pkg_install "ltrace" ;;
    pacman) pkg_install "ltrace" ;;
    *)      manual "Install ltrace via your package manager" ;;
  esac
  ok "ltrace installed"
}

install_strings_bin() {
  command -v strings &>/dev/null && { ok "strings already installed"; return 0; }
  case "$PKG_MANAGER" in
    apt|dnf|pacman|apk) pkg_install "binutils" ;;
    brew)   info "strings is part of Xcode Command Line Tools — run: install-dep.sh xcode-cli" ;;
    *)      manual "Install binutils for your OS" ;;
  esac
}

install_objdump() {
  command -v objdump &>/dev/null && { ok "objdump already installed"; return 0; }
  case "$PKG_MANAGER" in
    apt|dnf|pacman|apk) pkg_install "binutils" ;;
    brew)
      brew install binutils
      add_to_profile 'export PATH="/opt/homebrew/opt/binutils/bin:$PATH"' ;;
    *)      manual "Install binutils for your OS" ;;
  esac
}

install_readelf() {
  command -v readelf &>/dev/null && { ok "readelf already installed"; return 0; }
  case "$PKG_MANAGER" in
    apt|dnf|pacman|apk) pkg_install "binutils" ;;
    brew)   brew install binutils ;;
    *)      manual "Install binutils" ;;
  esac
}

install_nm() {
  command -v nm &>/dev/null && { ok "nm already installed"; return 0; }
  case "$PKG_MANAGER" in
    apt|dnf|pacman|apk) pkg_install "binutils" ;;
    brew)   info "nm is part of Xcode Command Line Tools — run: install-dep.sh xcode-cli" ;;
    *)      manual "Install binutils" ;;
  esac
}

install_xxd() {
  command -v xxd &>/dev/null && { ok "xxd already installed"; return 0; }
  case "$PKG_MANAGER" in
    brew)   ok "xxd is included with macOS Vim — should already be present" ;;
    apt)    pkg_install "xxd" 2>/dev/null || pkg_install "vim-common" ;;
    dnf)    pkg_install "vim-common" ;;
    pacman) pkg_install "vim" ;;
    apk)    pkg_install "vim" ;;
    *)      manual "Install xxd (part of vim-common on most distros)" ;;
  esac
  command -v xxd &>/dev/null && ok "xxd installed"
}

install_unzip() {
  command -v unzip &>/dev/null && { ok "unzip already installed"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install unzip ;;
    apt)    pkg_install "unzip" ;;
    dnf)    pkg_install "unzip" ;;
    pacman) pkg_install "unzip" ;;
    apk)    pkg_install "unzip" ;;
    *)      manual "Install unzip for your OS" ;;
  esac
  ok "unzip installed"
}

install_file_cmd() {
  command -v file &>/dev/null && { ok "file already installed"; return 0; }
  case "$PKG_MANAGER" in
    apt)    pkg_install "file" ;;
    dnf)    pkg_install "file" ;;
    pacman) pkg_install "file" ;;
    apk)    pkg_install "file" ;;
    brew)   ok "file is built-in on macOS" ;;
    *)      manual "Install the 'file' command for your OS" ;;
  esac
}

# ═════════════════════════════════════════════════════════════════════════════
# DECOMPILERS / RE SUITES
# ═════════════════════════════════════════════════════════════════════════════

install_ghidra() {
  command -v ghidra &>/dev/null && { ok "ghidra already installed"; return 0; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install ghidra 2>/dev/null && { ok "Ghidra installed via Homebrew"; return 0; } || true
  info "Downloading Ghidra from GitHub releases..."
  local tag; tag=$(gh_latest_tag "NationalSecurityAgency/ghidra")
  local version="${tag#Ghidra_}"; version="${version%_build}"
  # Ghidra releases use format: ghidra_VERSION_PUBLIC_YYYYMMDD.zip
  local date_part
  date_part=$(curl -fsSL "https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest" 2>/dev/null | \
    grep '"browser_download_url"' | grep '\.zip' | head -1 | grep -oP 'ghidra_[^"]+\.zip' | head -1)
  if [[ -z "$date_part" ]]; then
    manual "Download Ghidra from https://ghidra-sre.org and extract to ~/ghidra — requires Java 17+"
  fi
  local url="https://github.com/NationalSecurityAgency/ghidra/releases/download/${tag}/${date_part}"
  local install_dir="$HOME/.local/share/ghidra"
  local tmp; tmp=$(mktemp /tmp/ghidra-XXXXXX.zip)
  info "Downloading Ghidra (large file — may take a moment)..."
  download "$url" "$tmp"
  rm -rf "$install_dir"; mkdir -p "$install_dir"
  unzip -qo "$tmp" -d "$install_dir"; rm -f "$tmp"
  # Find the ghidraRun script
  local run_script; run_script=$(find "$install_dir" -name "ghidraRun" | head -1)
  if [[ -n "$run_script" ]]; then
    chmod +x "$run_script"
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/ghidra" <<EOF
#!/usr/bin/env bash
exec "$run_script" "\$@"
EOF
    chmod +x "$HOME/.local/bin/ghidra"
    add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
    ok "Ghidra installed → $install_dir  (launch: ghidra)"
  else
    manual "Ghidra extracted to $install_dir — run ghidraRun manually"
  fi
}

install_cutter() {
  command -v cutter &>/dev/null && { ok "cutter already installed"; return 0; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install --cask cutter 2>/dev/null && return 0 || true
  info "Downloading Cutter (radare2 GUI) from GitHub releases..."
  local tag; tag=$(gh_latest_tag "rizinorg/cutter")
  local version="${tag#v}"
  local arch_str="x86_64"
  [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && arch_str="arm64"
  local url=""
  if [[ "$OS" == "linux" ]]; then
    url="https://github.com/rizinorg/cutter/releases/download/${tag}/Cutter-v${version}-Linux-${arch_str}.AppImage"
    mkdir -p "$HOME/.local/bin"
    download "$url" "$HOME/.local/bin/cutter"
    chmod +x "$HOME/.local/bin/cutter"
    add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
    ok "Cutter $version installed as AppImage: ~/.local/bin/cutter"
  elif [[ "$OS" == "macos" ]]; then
    url="https://github.com/rizinorg/cutter/releases/download/${tag}/Cutter-v${version}-macOS-${arch_str}.dmg"
    local tmp; tmp=$(mktemp /tmp/cutter-XXXXXX.dmg)
    download "$url" "$tmp"
    info "Mounting Cutter DMG..."
    hdiutil attach "$tmp" -nobrowse -quiet
    cp -r /Volumes/Cutter/Cutter.app /Applications/ 2>/dev/null || true
    hdiutil detach /Volumes/Cutter 2>/dev/null || true
    rm -f "$tmp"
    ok "Cutter installed to /Applications/Cutter.app"
  else
    manual "Download Cutter from https://cutter.re"
  fi
}

install_retdec() {
  command -v retdec-decompiler &>/dev/null && { ok "retdec already installed"; return 0; }
  [[ "$PKG_MANAGER" == "brew" ]] && brew install retdec 2>/dev/null && { ok "retdec via Homebrew"; return 0; } || true
  info "Downloading RetDec from GitHub releases..."
  local tag; tag=$(gh_latest_tag "avast/retdec")
  local version="${tag#v}"
  local os_str="Linux"
  [[ "$OS" == "macos" ]] && os_str="macOS"
  local url="https://github.com/avast/retdec/releases/download/${tag}/RetDec-v${version}-${os_str}.tar.xz"
  local tmp; tmp=$(mktemp /tmp/retdec-XXXXXX.tar.xz)
  info "Downloading RetDec $version (large file)..."
  download "$url" "$tmp" || manual "Download RetDec from https://github.com/avast/retdec/releases"
  local dir="$HOME/.local/share/retdec"
  mkdir -p "$dir"
  tar -xJf "$tmp" -C "$dir" 2>/dev/null || tar -xf "$tmp" -C "$dir"
  rm -f "$tmp"
  local bin; bin=$(find "$dir" -name "retdec-decompiler*" -type f | head -1)
  if [[ -n "$bin" ]]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$bin" "$HOME/.local/bin/retdec-decompiler"
    add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
    ok "RetDec $version installed → retdec-decompiler"
  else
    manual "RetDec extracted to $dir — add its bin/ to PATH manually"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# DEBUGGERS
# ═════════════════════════════════════════════════════════════════════════════

install_gdb() {
  command -v gdb &>/dev/null && { ok "gdb already installed: $(gdb --version 2>/dev/null | head -1)"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install gdb && info "Note: on macOS, gdb requires code signing — see: https://sourceware.org/gdb/wiki/PermissionsDarwin" ;;
    apt)    pkg_install "gdb" ;;
    dnf)    pkg_install "gdb" ;;
    pacman) pkg_install "gdb" ;;
    apk)    pkg_install "gdb" ;;
    *)      manual "Install gdb from https://www.sourceware.org/gdb/" ;;
  esac
  ok "gdb installed"
}

install_pwndbg() {
  if python3 -c "import gdb" 2>/dev/null || (command -v gdb &>/dev/null && gdb -q -ex "python import pwndbg" -ex quit 2>/dev/null | grep -q pwndbg); then
    ok "pwndbg already installed"; return 0
  fi
  if ! command -v gdb &>/dev/null; then
    info "gdb not found — installing first..."
    install_gdb
  fi
  info "Installing pwndbg (GDB plugin for exploit dev)..."
  local dir="$HOME/.local/share/pwndbg"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --quiet
  else
    git clone --depth 1 https://github.com/pwndbg/pwndbg.git "$dir"
  fi
  bash "$dir/setup.sh" 2>&1 | tail -5
  ok "pwndbg installed — starts automatically with gdb"
}

install_gef() {
  # GEF (GDB Enhanced Features) — alternative to pwndbg, lighter weight
  if command -v gdb &>/dev/null && gdb -q -ex "python import gef" -ex quit 2>/dev/null | grep -q 'GEF'; then
    ok "GEF already installed"; return 0
  fi
  if ! command -v gdb &>/dev/null; then install_gdb; fi
  info "Installing GEF (GDB Enhanced Features)..."
  if command -v pip3 &>/dev/null; then
    pip3 install gef 2>/dev/null || true
  fi
  # Direct install method
  local gef_script="$HOME/.gef.py"
  download "https://gef.blah.cat/py" "$gef_script" 2>/dev/null || \
    download "https://raw.githubusercontent.com/hugsy/gef/main/gef.py" "$gef_script"
  # Add to .gdbinit
  local gdbinit="$HOME/.gdbinit"
  local gef_line="source $gef_script"
  grep -qF "source.*gef" "$gdbinit" 2>/dev/null || echo "$gef_line" >> "$gdbinit"
  ok "GEF installed → added to ~/.gdbinit"
}

install_peda() {
  # PEDA — Python Exploit Development Assistance
  if command -v gdb &>/dev/null && gdb -q -ex "python import peda" -ex quit 2>/dev/null | grep -q peda 2>/dev/null; then
    ok "PEDA already installed"; return 0
  fi
  if ! command -v gdb &>/dev/null; then install_gdb; fi
  info "Installing PEDA (Python Exploit Development Assistance for GDB)..."
  local dir="$HOME/.local/share/peda"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --quiet
  else
    git clone --depth 1 https://github.com/longld/peda.git "$dir"
  fi
  local gdbinit="$HOME/.gdbinit"
  local peda_line="source $dir/peda.py"
  grep -qF "source.*peda" "$gdbinit" 2>/dev/null || echo "$peda_line" >> "$gdbinit"
  ok "PEDA installed → added to ~/.gdbinit"
  info "Note: pwndbg/gef/peda conflict — only one can be active in ~/.gdbinit at a time"
}

install_lldb() {
  command -v lldb &>/dev/null && { ok "lldb already installed: $(lldb --version 2>/dev/null | head -1)"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install llvm && add_to_profile 'export PATH="/opt/homebrew/opt/llvm/bin:$PATH"' ;;
    apt)    pkg_install "lldb" ;;
    dnf)    pkg_install "lldb" ;;
    pacman) pkg_install "lldb" ;;
    *)
      if [[ "$OS" == "macos" ]]; then
        info "lldb comes with Xcode Command Line Tools — run: install-dep.sh xcode-cli"
      else
        manual "Install lldb from https://lldb.llvm.org/"
      fi ;;
  esac
  command -v lldb &>/dev/null && ok "lldb installed" || true
}

# ═════════════════════════════════════════════════════════════════════════════
# EXPLOIT DEVELOPMENT
# ═════════════════════════════════════════════════════════════════════════════

install_pwntools() {
  python3 -c "import pwn" 2>/dev/null && { ok "pwntools already installed"; return 0; }
  info "Installing pwntools..."
  if command -v pip3 &>/dev/null; then
    pip3 install pwntools
  elif command -v pip &>/dev/null; then
    pip install pwntools
  else
    manual "pip install pwntools  See: https://docs.pwntools.com/en/stable/install.html"
  fi
  python3 -c "import pwn" 2>/dev/null && ok "pwntools installed" || \
    info "pwntools installed — you may need to restart your shell"
}

install_ropgadget() {
  command -v ROPgadget &>/dev/null && { ok "ROPgadget already installed"; return 0; }
  info "Installing ROPgadget..."
  if command -v pip3 &>/dev/null; then pip3 install ROPgadget
  elif command -v pip &>/dev/null; then pip install ROPgadget
  else manual "pip install ROPgadget  See: https://github.com/JonathanSalwan/ROPgadget"
  fi
  command -v ROPgadget &>/dev/null && ok "ROPgadget installed" || \
    add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
}

install_ropper() {
  command -v ropper &>/dev/null && { ok "ropper already installed"; return 0; }
  info "Installing ropper..."
  if command -v pip3 &>/dev/null; then pip3 install ropper
  elif command -v pip &>/dev/null; then pip install ropper
  else manual "pip install ropper  See: https://github.com/sashs/Ropper"
  fi
  ok "ropper installed"
}

install_one_gadget() {
  command -v one_gadget &>/dev/null && { ok "one_gadget already installed"; return 0; }
  if command -v gem &>/dev/null; then
    info "Installing one_gadget via gem..."
    gem install one_gadget
    ok "one_gadget installed"
  elif [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install ruby
    gem install one_gadget
    ok "one_gadget installed via brew ruby"
  elif [[ "$PKG_MANAGER" == "apt" ]]; then
    pkg_install "ruby ruby-dev"
    gem install one_gadget
    ok "one_gadget installed"
  else
    manual "Install Ruby first, then: gem install one_gadget  See: https://github.com/david942j/one_gadget"
  fi
}

install_angr() {
  python3 -c "import angr" 2>/dev/null && { ok "angr already installed"; return 0; }
  info "Installing angr (symbolic execution framework)..."
  if command -v pip3 &>/dev/null; then
    pip3 install angr
  elif command -v pip &>/dev/null; then
    pip install angr
  else
    manual "pip install angr  See: https://angr.io/"
  fi
  python3 -c "import angr" 2>/dev/null && ok "angr installed" || \
    info "angr installed — large dependency tree, may take a few minutes"
}

# ═════════════════════════════════════════════════════════════════════════════
# MEMORY ANALYSIS / FUZZING
# ═════════════════════════════════════════════════════════════════════════════

install_valgrind() {
  command -v valgrind &>/dev/null && { ok "valgrind already installed: $(valgrind --version 2>/dev/null)"; return 0; }
  if [[ "$OS" == "macos" ]]; then
    info "Valgrind support on macOS is limited. Consider using AddressSanitizer (-fsanitize=address) instead."
    [[ "$PKG_MANAGER" == "brew" ]] && brew install valgrind 2>/dev/null && return 0 || true
    manual "Valgrind on macOS: https://valgrind.org/downloads/ (may not support latest macOS)"
  fi
  case "$PKG_MANAGER" in
    apt)    pkg_install "valgrind" ;;
    dnf)    pkg_install "valgrind" ;;
    pacman) pkg_install "valgrind" ;;
    apk)    pkg_install "valgrind" ;;
    *)      manual "Install valgrind from https://valgrind.org/" ;;
  esac
  ok "valgrind installed"
}

install_volatility3() {
  command -v vol &>/dev/null && { ok "volatility3 already installed"; return 0; }
  python3 -c "import volatility3" 2>/dev/null && { ok "volatility3 (Python module) already installed"; return 0; }
  info "Installing Volatility3 (memory forensics framework)..."
  if command -v pip3 &>/dev/null; then
    pip3 install volatility3
    ok "volatility3 installed — run with: vol -h"
  elif command -v pip &>/dev/null; then
    pip install volatility3
    ok "volatility3 installed"
  else
    info "Installing from GitHub source..."
    local dir="$HOME/.local/share/volatility3"
    git clone --depth 1 https://github.com/volatilityfoundation/volatility3.git "$dir"
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/vol" <<EOF
#!/usr/bin/env bash
exec python3 "$dir/vol.py" "\$@"
EOF
    chmod +x "$HOME/.local/bin/vol"
    add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
    ok "volatility3 installed from source → vol"
  fi
}

install_patchelf() {
  command -v patchelf &>/dev/null && { ok "patchelf already installed: $(patchelf --version 2>/dev/null)"; return 0; }
  case "$PKG_MANAGER" in
    brew)   brew install patchelf ;;
    apt)    pkg_install "patchelf" ;;
    dnf)    pkg_install "patchelf" ;;
    pacman) pkg_install "patchelf" ;;
    *)
      info "Building patchelf from source..."
      local tmp; tmp=$(mktemp -d)
      git clone --depth 1 https://github.com/NixOS/patchelf.git "$tmp"
      cd "$tmp" && ./bootstrap.sh && ./configure --prefix="$HOME/.local" && make -j"$(nproc 2>/dev/null || echo 2)" install
      cd - ; rm -rf "$tmp"
      add_to_profile 'export PATH="$HOME/.local/bin:$PATH"' ;;
  esac
  ok "patchelf installed"
}

install_seccomp_tools() {
  command -v seccomp-tools &>/dev/null && { ok "seccomp-tools already installed"; return 0; }
  if command -v gem &>/dev/null; then
    info "Installing seccomp-tools via gem..."
    gem install seccomp-tools
    ok "seccomp-tools installed"
  elif [[ "$PKG_MANAGER" == "apt" ]]; then
    pkg_install "ruby ruby-dev libseccomp-dev"
    gem install seccomp-tools
    ok "seccomp-tools installed"
  else
    manual "Install Ruby first, then: gem install seccomp-tools  See: https://github.com/david942j/seccomp-tools"
  fi
}

install_afl() {
  command -v afl-fuzz &>/dev/null && { ok "AFL++ already installed: $(afl-fuzz --version 2>/dev/null | head -1)"; return 0; }
  case "$PKG_MANAGER" in
    brew)
      brew install afl-fuzz 2>/dev/null || brew install aflplusplus 2>/dev/null
      ok "AFL++ installed via Homebrew" ;;
    apt)
      pkg_install "afl++" 2>/dev/null || pkg_install "afl" 2>/dev/null
      ok "AFL++ installed" ;;
    dnf)
      pkg_install "american-fuzzy-lop" 2>/dev/null
      ok "AFL installed" ;;
    pacman)
      pkg_install "afl++" 2>/dev/null
      ok "AFL++ installed" ;;
    *)
      info "Building AFL++ from source (requires gcc/make)..."
      local dir="$HOME/.local/share/aflplusplus"
      git clone --depth 1 https://github.com/AFLplusplus/AFLplusplus.git "$dir"
      cd "$dir" && make -j"$(nproc 2>/dev/null || echo 2)" all && \
        make PREFIX="$HOME/.local" install
      cd -
      add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
      ok "AFL++ built and installed from source" ;;
  esac
}

# ═════════════════════════════════════════════════════════════════════════════
# DISPATCH
# ═════════════════════════════════════════════════════════════════════════════
case "$DEP" in
  # Android
  java)                    install_java ;;
  jadx)                    install_jadx ;;
  vineflower|fernflower)   install_vineflower ;;
  dex2jar)                 install_dex2jar ;;
  apktool)                 install_apktool ;;
  adb)                     install_adb ;;
  # iOS / macOS
  xcode-cli|otool|codesign|lipo) install_xcode_cli ;;
  class-dump)              install_class_dump ;;
  ipsw)                    install_ipsw ;;
  frida)                   install_frida ;;
  # .NET
  dotnet)                  install_dotnet ;;
  ilspycmd)                install_ilspycmd ;;
  monodis|mono)            install_monodis ;;
  de4dot)                  install_de4dot ;;
  # SAST / Vuln
  checksec)                install_checksec ;;
  semgrep)                 install_semgrep ;;
  cppcheck)                install_cppcheck ;;
  flawfinder)              install_flawfinder ;;
  bandit)                  install_bandit ;;
  gitleaks)                install_gitleaks ;;
  trufflehog)              install_trufflehog ;;
  gosec)                   install_gosec ;;
  # Binary utils
  radare2|r2)              install_radare2 ;;
  binwalk)                 install_binwalk ;;
  upx)                     install_upx ;;
  strace)                  install_strace ;;
  ltrace)                  install_ltrace ;;
  strings|strings-bin)     install_strings_bin ;;
  objdump)                 install_objdump ;;
  readelf)                 install_readelf ;;
  nm)                      install_nm ;;
  xxd)                     install_xxd ;;
  unzip)                   install_unzip ;;
  file|file-cmd)           install_file_cmd ;;
  # Advanced RE / Exploit-Dev
  ghidra)                  install_ghidra ;;
  cutter)                  install_cutter ;;
  retdec)                  install_retdec ;;
  gdb)                     install_gdb ;;
  pwndbg)                  install_pwndbg ;;
  gef)                     install_gef ;;
  peda)                    install_peda ;;
  lldb)                    install_lldb ;;
  pwntools)                install_pwntools ;;
  ropgadget|ROPgadget)     install_ropgadget ;;
  ropper)                  install_ropper ;;
  one-gadget|one_gadget)   install_one_gadget ;;
  angr)                    install_angr ;;
  valgrind)                install_valgrind ;;
  volatility3|vol)         install_volatility3 ;;
  patchelf)                install_patchelf ;;
  seccomp-tools)           install_seccomp_tools ;;
  afl|afl++)               install_afl ;;
  *)
    echo "Error: Unknown dependency '$DEP'" >&2
    echo "Run install-dep.sh --help for available dependencies." >&2
    exit 1 ;;
esac
