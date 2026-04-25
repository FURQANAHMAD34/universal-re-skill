#!/usr/bin/env bash
# check-deps.sh — Check dependencies for universal RE skill
# Usage: check-deps.sh [platform]
# Platform: android|ios|windows|linux|macos|dotnet|vuln|all (default: all)
set -euo pipefail

PLATFORM="${1:-all}"
errors=0
missing_required=()
missing_optional=()

ok()   { echo "[OK]      $*"; }
miss() { echo "[MISSING] $*"; }
warn() { echo "[WARN]    $*"; }
info() { echo "[INFO]    $*"; }

check_cmd() {
  local cmd="$1" label="$2" required="${3:-required}"
  if command -v "$cmd" &>/dev/null; then
    local ver
    ver=$("$cmd" --version 2>/dev/null | head -1 || "$cmd" -version 2>/dev/null | head -1 || echo "found")
    ok "$label — $ver"
    return 0
  else
    miss "$label ($cmd not in PATH)"
    if [[ "$required" == "required" ]]; then
      errors=$((errors + 1))
      missing_required+=("$cmd")
    else
      missing_optional+=("$cmd")
    fi
    return 1
  fi
}

echo "=== Universal RE Skill: Dependency Check (platform: $PLATFORM) ==="
echo

# ── UNIVERSAL (always checked) ────────────────────────────────────────────────
echo "--- Universal Tools ---"
check_cmd "file"    "file(1) — type detection"      "required"
check_cmd "strings" "strings — string extraction"   "required"
check_cmd "grep"    "grep"                           "required"
check_cmd "unzip"   "unzip — archive extraction"     "required"
echo

# ── ANDROID ───────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
  echo "--- Android ---"

  # Java (required for jadx)
  java_ok=false
  if command -v java &>/dev/null; then
    java_ver=$(java -version 2>&1 | head -1 | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
    [[ -z "$java_ver" ]] && java_ver=$(java -version 2>&1 | grep -oP '\d+' | head -1)
    [[ "$java_ver" == "1" ]] && java_ver=$(java -version 2>&1 | head -1 | sed -n 's/.*"1\.\([0-9]*\)\..*/\1/p')
    if [[ -n "$java_ver" ]] && (( java_ver >= 17 )); then
      ok "Java $java_ver (required for jadx)"
      java_ok=true
    else
      warn "Java $java_ver detected but version ≥17 required"
      errors=$((errors + 1)); missing_required+=("java")
    fi
  else
    miss "Java JDK 17+ (required for jadx)"
    errors=$((errors + 1)); missing_required+=("java")
  fi

  check_cmd "jadx"      "jadx — APK/JAR decompiler"    "required"
  check_cmd "apktool"   "apktool — resource decoder"   "optional"
  check_cmd "d2j-dex2jar" "dex2jar — DEX→JAR converter" "optional"

  # Fernflower/Vineflower
  ff_ok=false
  for c in "${FERNFLOWER_JAR_PATH:-}" "$HOME/.local/share/vineflower/vineflower.jar" \
            "$HOME/vineflower/vineflower.jar" "$HOME/fernflower/build/libs/fernflower.jar"; do
    [[ -n "$c" && -f "$c" ]] && { ok "Vineflower JAR: $c"; ff_ok=true; break; }
  done
  command -v vineflower &>/dev/null && { ok "vineflower CLI"; ff_ok=true; }
  command -v fernflower &>/dev/null && { ok "fernflower CLI"; ff_ok=true; }
  [[ "$ff_ok" == false ]] && { miss "Fernflower/Vineflower (optional — better Java decompile)"; missing_optional+=("vineflower"); }
  echo
fi

# ── iOS ───────────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
  echo "--- iOS ---"
  check_cmd "otool"      "otool — Mach-O analysis"        "required"
  check_cmd "nm"         "nm — symbol table"              "required"
  check_cmd "class-dump" "class-dump — ObjC headers"      "optional"
  check_cmd "codesign"   "codesign — entitlement check"   "optional"
  check_cmd "lipo"       "lipo — fat binary slicing"      "optional"
  check_cmd "ipsw"       "ipsw — IPSW/dyld analysis"      "optional"
  echo
fi

# ── WINDOWS PE ────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "windows" || "$PLATFORM" == "all" ]]; then
  echo "--- Windows PE ---"
  check_cmd "objdump"  "objdump — PE disassembly/headers"  "required"
  check_cmd "strings"  "strings — string extraction"       "required"
  check_cmd "readpe"   "readpe (pev) — PE headers"         "optional"
  check_cmd "capa"     "capa — malware capability detection" "optional"
  check_cmd "upx"      "upx — packer detection/unpacking"  "optional"
  echo
fi

# ── LINUX ELF ─────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "all" ]]; then
  echo "--- Linux ELF ---"
  check_cmd "readelf"   "readelf — ELF headers/sections"  "required"
  check_cmd "objdump"   "objdump — ELF disassembly"       "required"
  check_cmd "nm"        "nm — symbol table"               "required"
  check_cmd "strace"    "strace — syscall tracing"        "optional"
  check_cmd "ltrace"    "ltrace — library call tracing"   "optional"
  check_cmd "checksec"  "checksec — binary hardening"     "optional"
  echo
fi

# ── macOS MACH-O ──────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
  echo "--- macOS Mach-O ---"
  check_cmd "otool"     "otool — Mach-O analysis"         "required"
  check_cmd "nm"        "nm — symbol table"               "required"
  check_cmd "codesign"  "codesign — signing/entitlements" "optional"
  check_cmd "lipo"      "lipo — fat binary handling"      "optional"
  check_cmd "dyldinfo"  "dyldinfo — dyld info"            "optional"
  echo
fi

# ── .NET ─────────────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "dotnet" || "$PLATFORM" == "all" ]]; then
  echo "--- .NET ---"
  check_cmd "ilspycmd"  "ilspycmd — .NET decompiler"  "required"
  check_cmd "monodis"   "monodis — Mono disassembler" "optional"
  check_cmd "dotnet"    "dotnet SDK"                  "optional"
  echo
fi

# ── VULNERABILITY SCANNING ───────────────────────────────────────────────────
if [[ "$PLATFORM" == "vuln" || "$PLATFORM" == "all" ]]; then
  echo "--- Vulnerability / SAST Tools ---"
  check_cmd "semgrep"      "semgrep — multi-language SAST"  "optional"
  check_cmd "cppcheck"     "cppcheck — C/C++ analysis"      "optional"
  check_cmd "flawfinder"   "flawfinder — C/C++ dangerous functions" "optional"
  check_cmd "bandit"       "bandit — Python security linter" "optional"
  check_cmd "gitleaks"     "gitleaks — secret scanning"     "optional"
  check_cmd "trufflehog"   "trufflehog — secret scanning"   "optional"
  check_cmd "gosec"        "gosec — Go security scanner"    "optional"
  check_cmd "checksec"     "checksec — binary hardening"    "optional"
  echo
fi

# ── CROSS-PLATFORM ────────────────────────────────────────────────────────────
if [[ "$PLATFORM" == "all" ]]; then
  echo "--- Cross-Platform / Advanced ---"
  check_cmd "r2"       "radare2 — advanced binary analysis"   "optional"
  check_cmd "ghidra"   "Ghidra — NSA RE suite"                "optional"
  check_cmd "binwalk"  "binwalk — firmware/embedded analysis" "optional"
  check_cmd "xxd"      "xxd — hex dump"                       "optional"
  check_cmd "hexdump"  "hexdump — hex dump"                   "optional"
  echo
fi

# ── SUMMARY ──────────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────"
if [[ ${#missing_required[@]} -gt 0 ]]; then
  for dep in "${missing_required[@]}"; do echo "INSTALL_REQUIRED:$dep"; done
fi
if [[ ${#missing_optional[@]} -gt 0 ]]; then
  for dep in "${missing_optional[@]}"; do echo "INSTALL_OPTIONAL:$dep"; done
fi
echo
if (( errors > 0 )); then
  echo "*** ${#missing_required[@]} required tool(s) missing. Run install-dep.sh <name> ***"
  exit 1
else
  echo "Required tools OK. ${#missing_optional[@]} optional tool(s) missing."
  [[ ${#missing_optional[@]} -gt 0 ]] && echo "Run install-dep.sh <name> to add optional tools."
  exit 0
fi
