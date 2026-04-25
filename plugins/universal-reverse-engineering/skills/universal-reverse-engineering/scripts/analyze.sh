#!/usr/bin/env bash
# analyze.sh — Universal RE dispatcher
# Usage: analyze.sh <platform|auto> <target> [-o <output-dir>] [OPTIONS]
# Platform: auto|android|ios|windows|linux|macos|dotnet|vuln
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: analyze.sh <platform> <target> [OPTIONS]

Platforms:
  auto       Auto-detect target type (default)
  android    Android APK/XAPK/JAR/AAR/DEX
  ios        iOS IPA or Mach-O binary
  windows    Windows PE (EXE/DLL/SYS)
  linux      Linux ELF binary
  macos      macOS Mach-O binary
  dotnet     .NET assembly (EXE/DLL/nupkg)
  vuln       Vulnerability scan only (source or binary)

Options:
  -o DIR     Output directory (default: <target>-analysis)
  --deobf    Enable deobfuscation (Android only, passed to jadx)
  --no-res   Skip resource decoding (Android only)
  --deep     Enable deeper analysis (slower: radare2/Ghidra)
  --vuln     Also run vulnerability scan after RE
  -h, --help Show this help

Examples:
  analyze.sh auto   app.apk
  analyze.sh android app.apk -o ./output --deobf
  analyze.sh linux  ./target_binary -o ./report --vuln
  analyze.sh vuln   ./src/
EOF
  exit 0
}

[[ $# -lt 1 ]] && usage

PLATFORM="$1"; shift
TARGET=""
OUTPUT_DIR=""
DEOBF=false
NO_RES=false
DEEP=false
ALSO_VULN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
    --deobf)     DEOBF=true; shift ;;
    --no-res)    NO_RES=true; shift ;;
    --deep)      DEEP=true; shift ;;
    --vuln)      ALSO_VULN=true; shift ;;
    -h|--help)   usage ;;
    -*)          echo "Unknown option: $1" >&2; usage ;;
    *)
      if [[ -z "$TARGET" ]]; then TARGET="$1"
      else echo "Error: unexpected argument '$1'" >&2; usage
      fi
      shift ;;
  esac
done

[[ -z "$TARGET" ]] && { echo "Error: no target specified." >&2; usage; }
[[ ! -e "$TARGET" ]] && { echo "Error: '$TARGET' not found." >&2; exit 1; }

TARGET_ABS=$(realpath "$TARGET")
BASENAME=$(basename "$TARGET_ABS")

[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="${BASENAME}-analysis"
mkdir -p "$OUTPUT_DIR"
OUTPUT_ABS=$(realpath "$OUTPUT_DIR")
LOG_FILE="$OUTPUT_ABS/analyze.log"

log() { echo "$*" | tee -a "$LOG_FILE"; }

log "=== Universal RE Analysis ==="
log "Target:   $TARGET_ABS"
log "Output:   $OUTPUT_ABS"
log "Date:     $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
log ""

# Auto-detect if needed
if [[ "$PLATFORM" == "auto" ]]; then
  log "--- Auto-detecting target type ---"
  DETECT_OUT=$("$SCRIPT_DIR/detect-target.sh" "$TARGET_ABS" 2>&1 | tee -a "$LOG_FILE")
  TYPE=$(echo "$DETECT_OUT" | grep '^TARGET_TYPE:' | head -1 | cut -d: -f2)
  ARCH=$(echo "$DETECT_OUT" | grep '^TARGET_ARCH:' | head -1 | cut -d: -f2)
  log "Detected: TYPE=$TYPE  ARCH=$ARCH"
  log ""

  case "$TYPE" in
    android-*)     PLATFORM="android" ;;
    ios-*)         PLATFORM="ios" ;;
    windows-pe*|windows-dotnet) PLATFORM="windows" ;;
    linux-elf*)    PLATFORM="linux" ;;
    macos-*)       PLATFORM="macos" ;;
    dotnet-*)      PLATFORM="dotnet" ;;
    source-*)      PLATFORM="vuln" ;;
    *)             log "Could not auto-detect type. Falling back to generic analysis."; PLATFORM="generic" ;;
  esac
  log "Selected platform: $PLATFORM"
  log ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# ANDROID
# ─────────────────────────────────────────────────────────────────────────────
analyze_android() {
  log "=== Android Analysis ==="
  local out="$OUTPUT_ABS/android"
  mkdir -p "$out"

  # Hash
  log "--- File Info ---"
  log "Size: $(du -h "$TARGET_ABS" | cut -f1)"
  command -v md5sum  &>/dev/null && log "MD5:    $(md5sum "$TARGET_ABS" | cut -d' ' -f1)"
  command -v sha256sum &>/dev/null && log "SHA256: $(sha256sum "$TARGET_ABS" | cut -d' ' -f1)"
  log ""

  # Check deps
  if ! command -v jadx &>/dev/null; then
    log "[WARN] jadx not found. Run: install-dep.sh jadx"
    return 1
  fi

  # Decompile
  log "--- Decompile (jadx) ---"
  local jadx_args=("-d" "$out/sources" "--show-bad-code")
  [[ "$DEOBF"  == true ]] && jadx_args+=("--deobf")
  [[ "$NO_RES" == true ]] && jadx_args+=("--no-res")
  jadx "${jadx_args[@]}" "$TARGET_ABS" 2>&1 | tee -a "$LOG_FILE" || log "[WARN] jadx exited with errors — partial output may still be useful"

  # Manifest
  if [[ -f "$out/sources/resources/AndroidManifest.xml" ]]; then
    log ""
    log "--- AndroidManifest.xml (excerpt) ---"
    grep -E '(package=|activity|service|receiver|provider|permission|uses-permission|exported)' \
      "$out/sources/resources/AndroidManifest.xml" 2>/dev/null | head -40 | tee -a "$LOG_FILE" || true
  fi

  # Package structure
  log ""
  log "--- Package Structure (top 20) ---"
  find "$out/sources" -type d 2>/dev/null | head -20 | sed "s|$out/sources/||" | tee -a "$LOG_FILE" || true

  # API scan
  log ""
  log "--- API / Network Patterns ---"
  grep -rn --include="*.java" --include="*.kt" \
    -E '@(GET|POST|PUT|DELETE|PATCH)\s*\(|"https?://|baseUrl|OkHttpClient|Volley|api[_-]?key|bearer|Authorization' \
    "$out/sources" 2>/dev/null | head -60 | tee -a "$LOG_FILE" || true

  log ""
  log "Android analysis complete → $out/"
}

# ─────────────────────────────────────────────────────────────────────────────
# iOS
# ─────────────────────────────────────────────────────────────────────────────
analyze_ios() {
  log "=== iOS Analysis ==="
  local out="$OUTPUT_ABS/ios"
  mkdir -p "$out"

  local binary="$TARGET_ABS"

  # If IPA, extract it
  if [[ "${TARGET_ABS##*.}" =~ ^[Ii][Pp][Aa]$ ]]; then
    log "--- Extracting IPA ---"
    local ipa_dir="$out/ipa-extracted"
    mkdir -p "$ipa_dir"
    unzip -qo "$TARGET_ABS" -d "$ipa_dir"
    binary=$(find "$ipa_dir/Payload" -maxdepth 2 -type f ! -name "*.plist" ! -name "*.png" \
             | xargs file 2>/dev/null | grep -i 'Mach-O' | head -1 | cut -d: -f1 || echo "")
    if [[ -z "$binary" ]]; then
      log "[WARN] Could not find main binary inside IPA"
      return 1
    fi
    log "Main binary: $binary"
  fi

  log ""
  log "--- File Info ---"
  file "$binary" | tee -a "$LOG_FILE"
  log "Size: $(du -h "$binary" | cut -f1)"
  command -v md5sum    &>/dev/null && log "MD5:    $(md5sum "$binary" | cut -d' ' -f1)"
  command -v sha256sum &>/dev/null && log "SHA256: $(sha256sum "$binary" | cut -d' ' -f1)"

  # Architecture
  log ""
  log "--- Architecture ---"
  if command -v lipo &>/dev/null; then
    lipo -info "$binary" 2>/dev/null | tee -a "$LOG_FILE" || true
  fi
  if command -v otool &>/dev/null; then
    otool -h "$binary" 2>/dev/null | tee -a "$LOG_FILE" | head -10 || true
  fi

  # Linked libraries
  log ""
  log "--- Linked Libraries ---"
  if command -v otool &>/dev/null; then
    otool -L "$binary" 2>/dev/null | tee -a "$LOG_FILE" || true
  fi

  # Symbols
  log ""
  log "--- Exported Symbols (top 40) ---"
  if command -v nm &>/dev/null; then
    nm -gU "$binary" 2>/dev/null | head -40 | tee -a "$LOG_FILE" || true
  fi

  # ObjC class dump
  log ""
  log "--- Objective-C Class Dump ---"
  if command -v class-dump &>/dev/null; then
    local headers_dir="$out/headers"
    mkdir -p "$headers_dir"
    class-dump -H "$binary" -o "$headers_dir" 2>&1 | tee -a "$LOG_FILE" || log "[WARN] class-dump failed (may be Swift-only binary)"
    local hcount; hcount=$(find "$headers_dir" -name "*.h" | wc -l)
    log "Headers extracted: $hcount → $headers_dir/"
  else
    log "[SKIP] class-dump not installed (install with: install-dep.sh class-dump)"
  fi

  # Strings of interest
  log ""
  log "--- Interesting Strings ---"
  strings "$binary" 2>/dev/null | \
    grep -E '(https?://|api[_-]?key|token|secret|password|BEGIN.*PRIVATE|aws_|AKIA|\.pem)' | \
    sort -u | head -50 | tee -a "$LOG_FILE" || true

  # Entitlements
  log ""
  log "--- Entitlements ---"
  if command -v codesign &>/dev/null; then
    codesign -d --entitlements :- "$binary" 2>/dev/null | tee -a "$LOG_FILE" || true
  fi

  # Info.plist security checks
  local plist
  plist=$(find "$(dirname "$binary")" -name "Info.plist" 2>/dev/null | head -1)
  if [[ -n "$plist" ]]; then
    log ""
    log "--- Info.plist Security Flags ---"
    grep -E '(NSAllowsArbitraryLoads|NSAppTransportSecurity|NSLocationWhen|NSPhotoLibrary|NSCamera|NSMicro)' \
      "$plist" 2>/dev/null | tee -a "$LOG_FILE" || true
  fi

  log ""
  log "iOS analysis complete → $out/"
}

# ─────────────────────────────────────────────────────────────────────────────
# WINDOWS PE
# ─────────────────────────────────────────────────────────────────────────────
analyze_windows() {
  log "=== Windows PE Analysis ==="
  local out="$OUTPUT_ABS/windows"
  mkdir -p "$out"

  log "--- File Info ---"
  file "$TARGET_ABS" | tee -a "$LOG_FILE"
  log "Size: $(du -h "$TARGET_ABS" | cut -f1)"
  command -v md5sum    &>/dev/null && log "MD5:    $(md5sum "$TARGET_ABS" | cut -d' ' -f1)"
  command -v sha256sum &>/dev/null && log "SHA256: $(sha256sum "$TARGET_ABS" | cut -d' ' -f1)"

  if ! command -v objdump &>/dev/null; then
    log "[WARN] objdump not found. Run: install-dep.sh objdump"; return 1
  fi

  log ""
  log "--- PE Headers ---"
  objdump -f "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" | head -20 || true

  log ""
  log "--- DLL Imports ---"
  objdump -p "$TARGET_ABS" 2>/dev/null | grep -A2 'DLL Name' | tee -a "$LOG_FILE" || true

  log ""
  log "--- Exports (DLL) ---"
  objdump -x "$TARGET_ABS" 2>/dev/null | grep -A3 '^Export' | head -50 | tee -a "$LOG_FILE" || true

  log ""
  log "--- Dangerous Imports (red flags) ---"
  objdump -p "$TARGET_ABS" 2>/dev/null | \
    grep -iE '(VirtualAlloc|CreateRemoteThread|WriteProcessMemory|LoadLibrary|GetProcAddress|ShellExecute|WinExec|CreateProcess|URLDownloadToFile|InternetOpen)' | \
    tee -a "$LOG_FILE" || true

  log ""
  log "--- Interesting Strings ---"
  strings -a -n 6 "$TARGET_ABS" 2>/dev/null | \
    grep -E '(https?://|password|secret|api[_-]?key|token|BEGIN.*PRIVATE|AKIA|\.onion|cmd\.exe|powershell|regsvr32)' | \
    sort -u | head -60 | tee -a "$LOG_FILE" || true

  # Packing detection
  log ""
  log "--- Packing / Obfuscation Check ---"
  if command -v upx &>/dev/null; then
    upx -t "$TARGET_ABS" 2>&1 | tee -a "$LOG_FILE" || log "Not UPX-packed"
  fi
  strings -a "$TARGET_ABS" 2>/dev/null | grep -iE '^(UPX|MPRESS|PECompact|ASPack|Themida)' | tee -a "$LOG_FILE" || true

  # Binary hardening
  log ""
  log "--- Security Mitigations ---"
  if command -v checksec &>/dev/null; then
    checksec --file="$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" || true
  else
    objdump -p "$TARGET_ABS" 2>/dev/null | grep -iE '(DllCharacteristics|GUARD_CF|DYNAMIC_BASE|NX_COMPAT|HIGH_ENTROPY_VA|NO_SEH)' | tee -a "$LOG_FILE" || true
  fi

  # radare2 deep analysis
  if [[ "$DEEP" == true ]] && command -v r2 &>/dev/null; then
    log ""
    log "--- radare2 Function List (deep) ---"
    r2 -A -q -c 'afl' "$TARGET_ABS" 2>/dev/null | head -80 | tee -a "$LOG_FILE" || true
  fi

  log ""
  log "Windows PE analysis complete → $out/"
}

# ─────────────────────────────────────────────────────────────────────────────
# LINUX ELF
# ─────────────────────────────────────────────────────────────────────────────
analyze_linux() {
  log "=== Linux ELF Analysis ==="
  local out="$OUTPUT_ABS/linux"
  mkdir -p "$out"

  log "--- File Info ---"
  file "$TARGET_ABS" | tee -a "$LOG_FILE"
  log "Size: $(du -h "$TARGET_ABS" | cut -f1)"
  command -v md5sum    &>/dev/null && log "MD5:    $(md5sum "$TARGET_ABS" | cut -d' ' -f1)"
  command -v sha256sum &>/dev/null && log "SHA256: $(sha256sum "$TARGET_ABS" | cut -d' ' -f1)"

  if ! command -v readelf &>/dev/null; then
    log "[WARN] readelf not found. Run: install-dep.sh readelf"; return 1
  fi

  log ""
  log "--- ELF Header ---"
  readelf -h "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" | head -25 || true

  log ""
  log "--- Sections ---"
  readelf -S "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" | head -35 || true

  log ""
  log "--- Dynamic Dependencies ---"
  readelf -d "$TARGET_ABS" 2>/dev/null | grep -E '(NEEDED|RPATH|RUNPATH)' | tee -a "$LOG_FILE" || true

  log ""
  log "--- Dynamic Symbols (imports/exports) ---"
  if command -v nm &>/dev/null; then
    nm -D "$TARGET_ABS" 2>/dev/null | head -60 | tee -a "$LOG_FILE" || true
  fi

  log ""
  log "--- Dangerous Imported Functions ---"
  nm -D "$TARGET_ABS" 2>/dev/null | \
    grep -E ' U .*(gets|strcpy|strcat|sprintf|vsprintf|scanf|system|popen|exec[vl]|fgets_unlocked|memcpy|memmove)$' | \
    tee -a "$LOG_FILE" || true

  log ""
  log "--- Disassembly (entry point + first 50 instructions) ---"
  if command -v objdump &>/dev/null; then
    objdump -d "$TARGET_ABS" 2>/dev/null | head -80 | tee -a "$LOG_FILE" || true
  fi

  log ""
  log "--- Interesting Strings ---"
  strings -a -n 6 "$TARGET_ABS" 2>/dev/null | \
    grep -E '(https?://|/etc/passwd|/etc/shadow|/bin/sh|/bin/bash|password|secret|api[_-]?key|token|BEGIN.*PRIVATE|AKIA|\.so\.)' | \
    sort -u | head -60 | tee -a "$LOG_FILE" || true

  log ""
  log "--- Security Mitigations (checksec) ---"
  if command -v checksec &>/dev/null; then
    checksec --file="$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" || true
  else
    log "[SKIP] checksec not installed. Run: install-dep.sh checksec"
    log "Manual check:"
    readelf -l "$TARGET_ABS" 2>/dev/null | grep -E '(GNU_STACK|GNU_RELRO)' | tee -a "$LOG_FILE" || true
    readelf -d "$TARGET_ABS" 2>/dev/null | grep -E '(BIND_NOW|FLAGS)' | tee -a "$LOG_FILE" || true
    file "$TARGET_ABS" | grep -i 'pie\|shared object' | tee -a "$LOG_FILE" || true
  fi

  # radare2 deep
  if [[ "$DEEP" == true ]] && command -v r2 &>/dev/null; then
    log ""
    log "--- radare2 Function List (deep) ---"
    r2 -A -q -c 'afl' "$TARGET_ABS" 2>/dev/null | head -100 | tee -a "$LOG_FILE" || true
    log "--- radare2 Calls to Dangerous Functions ---"
    r2 -A -q -c 'axt sym.imp.gets; axt sym.imp.strcpy; axt sym.imp.system' "$TARGET_ABS" 2>/dev/null | \
      tee -a "$LOG_FILE" || true
  fi

  log ""
  log "Linux ELF analysis complete → $out/"
}

# ─────────────────────────────────────────────────────────────────────────────
# macOS MACH-O
# ─────────────────────────────────────────────────────────────────────────────
analyze_macos() {
  log "=== macOS Mach-O Analysis ==="
  local out="$OUTPUT_ABS/macos"
  mkdir -p "$out"

  log "--- File Info ---"
  file "$TARGET_ABS" | tee -a "$LOG_FILE"
  log "Size: $(du -h "$TARGET_ABS" | cut -f1)"
  command -v md5sum    &>/dev/null && log "MD5:    $(md5sum "$TARGET_ABS" | cut -d' ' -f1)"
  command -v sha256sum &>/dev/null && log "SHA256: $(sha256sum "$TARGET_ABS" | cut -d' ' -f1)"

  if ! command -v otool &>/dev/null; then
    log "[WARN] otool not installed (Xcode Command Line Tools required on macOS)"
    return 1
  fi

  log ""
  log "--- Mach-O Header ---"
  otool -h "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" || true

  log ""
  log "--- Architectures (fat binary) ---"
  if command -v lipo &>/dev/null; then
    lipo -info "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" || true
  fi

  log ""
  log "--- Load Commands ---"
  otool -l "$TARGET_ABS" 2>/dev/null | head -60 | tee -a "$LOG_FILE" || true

  log ""
  log "--- Linked Libraries ---"
  otool -L "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" || true

  log ""
  log "--- RPATH Entries ---"
  otool -l "$TARGET_ABS" 2>/dev/null | grep -A3 'LC_RPATH' | tee -a "$LOG_FILE" || true

  log ""
  log "--- Exported Symbols (top 50) ---"
  nm -gU "$TARGET_ABS" 2>/dev/null | head -50 | tee -a "$LOG_FILE" || true

  log ""
  log "--- Disassembly (first 60 lines) ---"
  otool -tV "$TARGET_ABS" 2>/dev/null | head -60 | tee -a "$LOG_FILE" || true

  log ""
  log "--- Interesting Strings ---"
  strings "$TARGET_ABS" 2>/dev/null | \
    grep -E '(https?://|password|secret|api[_-]?key|token|BEGIN.*PRIVATE|AKIA|\.onion)' | \
    sort -u | head -50 | tee -a "$LOG_FILE" || true

  log ""
  log "--- Code Signing Info ---"
  if command -v codesign &>/dev/null; then
    codesign -dvv "$TARGET_ABS" 2>&1 | tee -a "$LOG_FILE" || true
    log ""
    log "--- Entitlements ---"
    codesign -d --entitlements :- "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" || true
  fi

  log ""
  log "macOS Mach-O analysis complete → $out/"
}

# ─────────────────────────────────────────────────────────────────────────────
# .NET
# ─────────────────────────────────────────────────────────────────────────────
analyze_dotnet() {
  log "=== .NET Assembly Analysis ==="
  local out="$OUTPUT_ABS/dotnet"
  mkdir -p "$out"

  log "--- File Info ---"
  file "$TARGET_ABS" | tee -a "$LOG_FILE"
  log "Size: $(du -h "$TARGET_ABS" | cut -f1)"
  command -v sha256sum &>/dev/null && log "SHA256: $(sha256sum "$TARGET_ABS" | cut -d' ' -f1)"

  # Handle nupkg
  if [[ "${TARGET_ABS##*.}" =~ ^nupkg$ ]]; then
    log ""
    log "--- NuGet Package Contents ---"
    unzip -l "$TARGET_ABS" | tee -a "$LOG_FILE" | head -30 || true
    log "Extracting assemblies..."
    unzip -qo "$TARGET_ABS" -d "$out/nupkg-extracted"
    while IFS= read -r dll; do
      log "Found assembly: $dll"
    done < <(find "$out/nupkg-extracted" -name "*.dll" 2>/dev/null)
    return 0
  fi

  if command -v ilspycmd &>/dev/null; then
    log ""
    log "--- Decompiling with ilspycmd ---"
    local src_dir="$out/sources"
    mkdir -p "$src_dir"
    ilspycmd -p -o "$src_dir" "$TARGET_ABS" 2>&1 | tee -a "$LOG_FILE" || log "[WARN] ilspycmd decompilation had errors"
    local ccount; ccount=$(find "$src_dir" -name "*.cs" | wc -l)
    log "C# files decompiled: $ccount → $src_dir/"

    if [[ $ccount -gt 0 ]]; then
      log ""
      log "--- Interesting .NET Patterns ---"
      grep -rn --include="*.cs" \
        -E '(SqlCommand|OleDbCommand|HttpClient|WebRequest|Process\.Start|DllImport|Marshal|BinaryFormatter|JsonConvert.*TypeName|Environment\.GetEnvironmentVariable|AppSettings)' \
        "$src_dir" 2>/dev/null | head -50 | tee -a "$LOG_FILE" || true
    fi
  else
    log "[WARN] ilspycmd not installed. Run: install-dep.sh ilspycmd"
    if command -v monodis &>/dev/null; then
      log ""
      log "--- monodis typedef ---"
      monodis --typedef "$TARGET_ABS" 2>/dev/null | head -60 | tee -a "$LOG_FILE" || true
    fi
  fi

  log ""
  log "--- Interesting Strings in Assembly ---"
  strings -a -n 6 "$TARGET_ABS" 2>/dev/null | \
    grep -E '(https?://|password|secret|api[_-]?key|token|BEGIN.*PRIVATE|AKIA|connectionString|Data Source)' | \
    sort -u | head -50 | tee -a "$LOG_FILE" || true

  log ""
  log ".NET analysis complete → $out/"
}

# ─────────────────────────────────────────────────────────────────────────────
# VULN SCAN
# ─────────────────────────────────────────────────────────────────────────────
analyze_vuln() {
  log "=== Vulnerability Scan ==="
  local out="$OUTPUT_ABS/vuln"
  mkdir -p "$out"

  local vuln_scripts="$SCRIPT_DIR/../../../vulnerability-scanner/scripts"

  if [[ -f "$vuln_scripts/vuln-scan.sh" ]]; then
    bash "$vuln_scripts/vuln-scan.sh" "$TARGET_ABS" -o "$out" 2>&1 | tee -a "$LOG_FILE"
  else
    log "[WARN] vuln-scan.sh not found at $vuln_scripts/vuln-scan.sh"
    # Inline fallback
    log ""
    log "--- Inline: Secret / Credential Scan ---"
    if [[ -d "$TARGET_ABS" ]]; then
      grep -rn --include="*.c" --include="*.cpp" --include="*.py" --include="*.java" \
           --include="*.js" --include="*.ts" --include="*.go" --include="*.cs" \
           -E '(password\s*=\s*["\x27][^\x27"]{4,}|api[_-]?key\s*=\s*["\x27][^\x27"]{8,}|secret\s*=\s*["\x27][^\x27"]{6,}|BEGIN.*PRIVATE KEY|AKIA[0-9A-Z]{16})' \
           "$TARGET_ABS" 2>/dev/null | head -40 | tee -a "$LOG_FILE" || true
    else
      strings -a -n 6 "$TARGET_ABS" 2>/dev/null | \
        grep -E '(password|secret|api[_-]?key|token|BEGIN.*PRIVATE|AKIA)' | \
        sort -u | head -40 | tee -a "$LOG_FILE" || true
    fi
  fi

  log ""
  log "Vulnerability scan complete → $out/"
}

# ─────────────────────────────────────────────────────────────────────────────
# GENERIC
# ─────────────────────────────────────────────────────────────────────────────
analyze_generic() {
  log "=== Generic Binary Analysis ==="
  local out="$OUTPUT_ABS/generic"
  mkdir -p "$out"

  log "--- file(1) Output ---"
  file "$TARGET_ABS" | tee -a "$LOG_FILE"

  log ""
  log "--- Strings of Interest ---"
  strings -a -n 6 "$TARGET_ABS" 2>/dev/null | \
    grep -E '(https?://|ftp://|password|secret|key|token|flag{|CTF|BEGIN.*PRIVATE)' | \
    sort -u | head -80 | tee -a "$LOG_FILE" || true

  if command -v binwalk &>/dev/null; then
    log ""
    log "--- binwalk Scan ---"
    binwalk "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" || true
  fi

  if command -v xxd &>/dev/null; then
    log ""
    log "--- First 256 bytes (hex) ---"
    xxd "$TARGET_ABS" 2>/dev/null | head -16 | tee -a "$LOG_FILE" || true
  fi

  log ""
  log "Generic analysis complete → $out/"
}

# ─────────────────────────────────────────────────────────────────────────────
# DISPATCH
# ─────────────────────────────────────────────────────────────────────────────
case "$PLATFORM" in
  android) analyze_android ;;
  ios)     analyze_ios ;;
  windows) analyze_windows ;;
  linux)   analyze_linux ;;
  macos)   analyze_macos ;;
  dotnet)  analyze_dotnet ;;
  vuln)    analyze_vuln ;;
  generic) analyze_generic ;;
  *)       log "Error: Unknown platform '$PLATFORM'"; usage ;;
esac

# Optional post-analysis vuln scan
if [[ "$ALSO_VULN" == true && "$PLATFORM" != "vuln" ]]; then
  log ""
  analyze_vuln
fi

log ""
log "=== Analysis complete. Full log: $LOG_FILE ==="
