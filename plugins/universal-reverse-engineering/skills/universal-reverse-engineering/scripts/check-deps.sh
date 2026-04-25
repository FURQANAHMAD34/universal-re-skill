#!/usr/bin/env bash
# check-deps.sh — Check all dependencies for universal RE skill
# Usage: check-deps.sh [platform]
# Platform: android|ios|windows|linux|macos|dotnet|vuln|all (default: all)
set -euo pipefail

PLATFORM="${1:-all}"
errors=0
missing_required=()
missing_optional=()

ok()   { printf "  [OK]      %-20s %s\n" "$1" "$2"; }
miss() { printf "  [MISSING] %-20s %s\n" "$1" "$2"; }
warn() { printf "  [WARN]    %-20s %s\n" "$1" "$2"; }
info() { echo  "  [INFO]    $*"; }

check_cmd() {
  local cmd="$1" label="$2" required="${3:-required}" install_hint="${4:-$cmd}"
  if command -v "$cmd" &>/dev/null; then
    local ver
    ver=$( "$cmd" --version 2>/dev/null | head -1 \
        || "$cmd" -version 2>/dev/null | head -1 \
        || "$cmd" -V 2>/dev/null | head -1 \
        || echo "found" ) 2>/dev/null || ver="found"
    ok "$cmd" "${ver:0:60}"
    return 0
  else
    miss "$cmd" "(install: install-dep.sh $install_hint)"
    if [[ "$required" == "required" ]]; then
      errors=$((errors + 1))
      missing_required+=("$install_hint")
    else
      missing_optional+=("$install_hint")
    fi
    return 1
  fi
}

echo "=== Universal RE Skill: Dependency Check ==="
echo "Platform: $PLATFORM"
echo ""

# ── UNIVERSAL BASE (always checked) ──────────────────────────────────────────
echo "--- Base Tools (required everywhere) ---"
check_cmd "file"   "file — type detection"     "required" "file-cmd"
check_cmd "strings" "strings — string extract" "required" "strings-bin"
check_cmd "unzip"  "unzip — archive extract"   "required" "unzip"
check_cmd "xxd"    "xxd — hex dump"            "optional" "xxd"
echo ""

# ── ANDROID ──────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
  echo "--- Android ---"

  # Java version check
  java_ok=false
  if command -v java &>/dev/null; then
    java_ver=$(java -version 2>&1 | head -1 | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
    [[ -z "$java_ver" ]] && java_ver=$(java -version 2>&1 | grep -oP '\d+' | head -1)
    [[ "$java_ver" == "1" ]] && java_ver=$(java -version 2>&1 | head -1 | sed -n 's/.*"1\.\([0-9]*\)\..*/\1/p')
    if [[ -n "$java_ver" ]] && (( java_ver >= 17 )); then
      ok "java" "JDK $java_ver (≥17 required)"; java_ok=true
    else
      warn "java" "Found version $java_ver — need ≥17  (install: install-dep.sh java)"
      errors=$((errors + 1)); missing_required+=("java")
    fi
  else
    miss "java" "(install: install-dep.sh java)"
    errors=$((errors + 1)); missing_required+=("java")
  fi

  check_cmd "jadx"          "jadx — APK/JAR decompiler"      "required" "jadx"
  check_cmd "apktool"       "apktool — resource decoder"      "optional" "apktool"
  check_cmd "d2j-dex2jar"   "dex2jar — DEX→JAR converter"    "optional" "dex2jar"
  check_cmd "adb"           "adb — Android Debug Bridge"      "optional" "adb"

  # Fernflower/Vineflower JAR check
  ff_ok=false
  for c in "${FERNFLOWER_JAR_PATH:-}" \
            "$HOME/.local/share/vineflower/vineflower.jar" \
            "$HOME/vineflower/vineflower.jar" \
            "$HOME/fernflower/build/libs/fernflower.jar"; do
    [[ -n "$c" && -f "$c" ]] && { ok "vineflower" "JAR: $c"; ff_ok=true; break; }
  done
  command -v vineflower &>/dev/null && { ok "vineflower" "CLI found"; ff_ok=true; }
  command -v fernflower &>/dev/null && { ok "fernflower" "CLI found"; ff_ok=true; }
  [[ "$ff_ok" == false ]] && { miss "vineflower" "(install: install-dep.sh vineflower)"; missing_optional+=("vineflower"); }
  echo ""
fi

# ── iOS ──────────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
  echo "--- iOS ---"
  check_cmd "otool"      "otool — Mach-O analysis"          "required" "xcode-cli"
  check_cmd "nm"         "nm — symbol table"                "required" "nm"
  check_cmd "lipo"       "lipo — fat binary slicing"        "optional" "xcode-cli"
  check_cmd "codesign"   "codesign — entitlements"          "optional" "xcode-cli"
  check_cmd "class-dump" "class-dump — ObjC headers"        "optional" "class-dump"
  check_cmd "ipsw"       "ipsw — IPSW/dyld analysis"        "optional" "ipsw"
  check_cmd "frida"      "frida — dynamic instrumentation"  "optional" "frida"
  echo ""
fi

# ── WINDOWS PE ───────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "windows" || "$PLATFORM" == "all" ]]; then
  echo "--- Windows PE ---"
  check_cmd "objdump"  "objdump — PE headers/disassembly"  "required" "objdump"
  check_cmd "strings"  "strings — string extraction"       "required" "strings-bin"
  check_cmd "upx"      "upx — packing detection/unpack"    "optional" "upx"
  check_cmd "checksec" "checksec — security mitigations"   "optional" "checksec"
  check_cmd "r2"       "radare2 — advanced RE"             "optional" "radare2"
  echo ""
fi

# ── LINUX ELF ────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "all" ]]; then
  echo "--- Linux ELF ---"
  check_cmd "readelf"   "readelf — ELF headers/sections"   "required" "readelf"
  check_cmd "objdump"   "objdump — ELF disassembly"        "required" "objdump"
  check_cmd "nm"        "nm — symbol table"                "required" "nm"
  check_cmd "checksec"  "checksec — security mitigations"  "optional" "checksec"
  check_cmd "strace"    "strace — syscall tracing"         "optional" "strace"
  check_cmd "ltrace"    "ltrace — library call tracing"    "optional" "ltrace"
  check_cmd "r2"        "radare2 — advanced RE"            "optional" "radare2"
  echo ""
fi

# ── macOS MACH-O ─────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
  echo "--- macOS Mach-O ---"
  check_cmd "otool"     "otool — Mach-O analysis"          "required" "xcode-cli"
  check_cmd "nm"        "nm — symbol table"                "required" "nm"
  check_cmd "lipo"      "lipo — fat binary handling"       "optional" "xcode-cli"
  check_cmd "codesign"  "codesign — signing/entitlements"  "optional" "xcode-cli"
  check_cmd "r2"        "radare2 — advanced RE"            "optional" "radare2"
  echo ""
fi

# ── .NET ─────────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "dotnet" || "$PLATFORM" == "all" ]]; then
  echo "--- .NET ---"
  check_cmd "dotnet"    "dotnet SDK — required for ilspycmd" "optional" "dotnet"
  check_cmd "ilspycmd"  "ilspycmd — .NET decompiler"         "required" "ilspycmd"
  check_cmd "monodis"   "monodis — Mono IL disassembler"     "optional" "monodis"
  check_cmd "de4dot"    "de4dot — .NET deobfuscator"         "optional" "de4dot"
  echo ""
fi

# ── VULNERABILITY / SAST ─────────────────────────────────────────────────────
if [[ "$PLATFORM" == "vuln" || "$PLATFORM" == "all" ]]; then
  echo "--- Vulnerability / SAST Tools ---"
  check_cmd "semgrep"    "semgrep — multi-language SAST"     "optional" "semgrep"
  check_cmd "cppcheck"   "cppcheck — C/C++ analysis"         "optional" "cppcheck"
  check_cmd "flawfinder" "flawfinder — C/C++ dangerous fns"  "optional" "flawfinder"
  check_cmd "bandit"     "bandit — Python security linter"   "optional" "bandit"
  check_cmd "gitleaks"   "gitleaks — secret scanning"        "optional" "gitleaks"
  check_cmd "trufflehog" "trufflehog — deep secret scan"     "optional" "trufflehog"
  check_cmd "gosec"      "gosec — Go security scanner"       "optional" "gosec"
  check_cmd "checksec"   "checksec — binary hardening"       "optional" "checksec"
  echo ""
fi

# ── CROSS-PLATFORM / ADVANCED ────────────────────────────────────────────────
if [[ "$PLATFORM" == "all" ]]; then
  echo "--- Cross-Platform / Advanced ---"
  check_cmd "r2"       "radare2 — advanced binary analysis" "optional" "radare2"
  check_cmd "binwalk"  "binwalk — firmware/embedded RE"     "optional" "binwalk"
  check_cmd "upx"      "upx — packer detection/unpacking"  "optional" "upx"
  check_cmd "frida"    "frida — dynamic instrumentation"   "optional" "frida"
  echo ""
fi

# ── SUMMARY ──────────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────"
if [[ ${#missing_required[@]} -gt 0 ]]; then
  echo ""
  echo "Required (must install before analysis):"
  for dep in "${missing_required[@]}"; do
    echo "  bash scripts/install-dep.sh $dep"
    echo "INSTALL_REQUIRED:$dep"
  done
fi
if [[ ${#missing_optional[@]} -gt 0 ]]; then
  echo ""
  echo "Optional (improves results):"
  for dep in "${missing_optional[@]}"; do
    echo "  bash scripts/install-dep.sh $dep"
    echo "INSTALL_OPTIONAL:$dep"
  done
fi
echo ""
if (( errors > 0 )); then
  echo "*** ${#missing_required[@]} required dep(s) missing — install them before running analysis. ***"
  exit 1
else
  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    echo "All required tools present. ${#missing_optional[@]} optional dep(s) missing (run install-dep.sh <name> to add)."
  else
    echo "All dependencies installed. Ready for full analysis."
  fi
  exit 0
fi
