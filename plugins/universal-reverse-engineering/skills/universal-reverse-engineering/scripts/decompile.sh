#!/usr/bin/env bash
# decompile.sh — Cross-platform decompiler + PoC script generator
# Usage: decompile.sh <target> [-o <output-dir>] [--engine jadx|fernflower|ilspy|r2|both]
#        [--deobf] [--no-res] [--poc] [--platform android|dotnet|linux|windows|ios|auto]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: decompile.sh <target> [OPTIONS]

Decompile any binary/app and optionally generate PoC exploit scripts.

Targets:
  Android APK/XAPK/JAR/AAR/DEX  — jadx, fernflower
  Windows PE / .NET EXE/DLL      — ilspycmd, monodis
  Linux ELF                       — radare2 (r2), objdump
  iOS IPA / Mach-O                — otool, class-dump
  macOS Mach-O                    — otool
  Source dirs (Java/C/Python/C#)  — direct analysis

Options:
  -o DIR          Output directory (default: <target>-decompiled)
  --platform P    Force platform: android|dotnet|linux|windows|ios|macos|auto (default: auto)
  --engine E      Decompile engine: jadx|fernflower|ilspy|monodis|r2|both (default: best-available)
  --deobf         Enable deobfuscation (Android jadx / .NET de4dot)
  --no-res        Skip resource decoding (Android only)
  --poc           Generate PoC exploit scripts after decompile
  -h, --help      Show this help

Examples:
  decompile.sh app.apk --poc
  decompile.sh malware.exe --platform dotnet --poc
  decompile.sh target_bin --platform linux --poc
  decompile.sh app.ipa --poc
EOF
  exit 0
}

TARGET=""
OUTPUT_DIR=""
PLATFORM="auto"
ENGINE=""
DEOBF=false
NO_RES=false
GEN_POC=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)    OUTPUT_DIR="$2"; shift 2 ;;
    --platform)     PLATFORM="$2"; shift 2 ;;
    --engine)       ENGINE="$2"; shift 2 ;;
    --deobf)        DEOBF=true; shift ;;
    --no-res)       NO_RES=true; shift ;;
    --poc)          GEN_POC=true; shift ;;
    -h|--help)      usage ;;
    -*)             echo "Unknown option: $1" >&2; usage ;;
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
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="${BASENAME}-decompiled"
mkdir -p "$OUTPUT_DIR"
OUTPUT_ABS=$(realpath "$OUTPUT_DIR")
LOG_FILE="$OUTPUT_ABS/decompile.log"
META_FILE="$OUTPUT_ABS/.decompile-meta"
POC_DIR="$OUTPUT_ABS/poc-scripts"

log()  { echo "$*" | tee -a "$LOG_FILE"; }
info() { echo "[INFO]  $*" | tee -a "$LOG_FILE"; }
warn() { echo "[WARN]  $*" | tee -a "$LOG_FILE"; }
ok()   { echo "[OK]    $*" | tee -a "$LOG_FILE"; }

log "=== Universal Decompiler ==="
log "Target:   $TARGET_ABS"
log "Output:   $OUTPUT_ABS"
log "Date:     $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
log ""

# ── Auto-detect platform ─────────────────────────────────────────────────────
if [[ "$PLATFORM" == "auto" ]]; then
  if [[ -f "$SCRIPT_DIR/detect-target.sh" ]]; then
    TYPE=$("$SCRIPT_DIR/detect-target.sh" "$TARGET_ABS" 2>/dev/null | grep '^TARGET_TYPE:' | cut -d: -f2)
  else
    TYPE=$(file -b "$TARGET_ABS" 2>/dev/null)
  fi

  case "$TYPE" in
    android-*)               PLATFORM="android" ;;
    windows-dotnet|dotnet-*) PLATFORM="dotnet" ;;
    windows-pe*)             PLATFORM="windows" ;;
    linux-elf*)              PLATFORM="linux" ;;
    ios-*)                   PLATFORM="ios" ;;
    macos-*)                 PLATFORM="macos" ;;
    source-*)                PLATFORM="source" ;;
    *)
      FILE_OUT=$(file -b "$TARGET_ABS" 2>/dev/null)
      if echo "$FILE_OUT" | grep -qi 'Mono/.Net\|CIL\|CLR'; then PLATFORM="dotnet"
      elif echo "$FILE_OUT" | grep -qi 'PE32\|MS-DOS'; then PLATFORM="windows"
      elif echo "$FILE_OUT" | grep -qi 'ELF'; then PLATFORM="linux"
      elif echo "$FILE_OUT" | grep -qi 'Mach-O'; then PLATFORM="macos"
      elif echo "$FILE_OUT" | grep -qi 'Zip\|Java archive'; then PLATFORM="android"
      else PLATFORM="linux"
      fi ;;
  esac
  log "Auto-detected platform: $PLATFORM"
  log ""
fi

# ── ANDROID ──────────────────────────────────────────────────────────────────
decompile_android() {
  local out="$OUTPUT_ABS/sources"
  mkdir -p "$out"
  log "=== Android Decompile ==="

  local ext="${TARGET_ABS##*.}"
  local is_xapk=false
  [[ "${ext,,}" == "xapk" ]] && is_xapk=true

  # XAPK: extract inner APKs first
  local actual_target="$TARGET_ABS"
  if [[ "$is_xapk" == true ]]; then
    local xapk_dir="$OUTPUT_ABS/xapk-extracted"
    mkdir -p "$xapk_dir"
    log "Extracting XAPK..."
    unzip -qo "$TARGET_ABS" -d "$xapk_dir" 2>/dev/null || true
    # Prefer base APK
    actual_target=$(find "$xapk_dir" -maxdepth 1 -name "*.apk" | grep -v split | head -1)
    if [[ -z "$actual_target" ]]; then
      actual_target=$(find "$xapk_dir" -name "*.apk" | head -1)
    fi
    [[ -z "$actual_target" ]] && { warn "No APK found inside XAPK"; actual_target="$TARGET_ABS"; }
    log "Base APK: $actual_target"
    # Extract manifest from xapk-manifest if present
    if [[ -f "$xapk_dir/manifest.json" ]]; then
      cp "$xapk_dir/manifest.json" "$OUTPUT_ABS/xapk-manifest.json"
      log "XAPK manifest saved → $OUTPUT_ABS/xapk-manifest.json"
    fi
    log ""
  fi

  local use_engine="${ENGINE:-jadx}"

  # Try jadx
  if [[ "$use_engine" == "jadx" || "$use_engine" == "both" ]] && command -v jadx &>/dev/null; then
    log "--- Decompiling with jadx ---"
    local jadx_args=("-d" "$out" "--show-bad-code")
    [[ "$DEOBF"  == true ]] && jadx_args+=("--deobf")
    [[ "$NO_RES" == true ]] && jadx_args+=("--no-res")
    jadx "${jadx_args[@]}" "$actual_target" 2>&1 | tee -a "$LOG_FILE" \
      || warn "jadx had errors — partial output may still be useful"
    ok "jadx output → $out/"
  elif ! command -v jadx &>/dev/null; then
    warn "jadx not found. Run: bash $SCRIPT_DIR/install-dep.sh jadx"
  fi

  # Try fernflower (via dex2jar intermediate)
  if [[ "$use_engine" == "fernflower" || "$use_engine" == "both" ]]; then
    local ff_jar=""
    for c in "${FERNFLOWER_JAR_PATH:-}" \
              "$HOME/.local/share/vineflower/vineflower.jar" \
              "$HOME/vineflower/vineflower.jar" \
              "$HOME/fernflower/build/libs/fernflower.jar"; do
      [[ -n "$c" && -f "$c" ]] && { ff_jar="$c"; break; }
    done
    command -v vineflower &>/dev/null && ff_jar="$(command -v vineflower)"
    command -v fernflower &>/dev/null && ff_jar="$(command -v fernflower)"

    if [[ -n "$ff_jar" ]] && command -v d2j-dex2jar &>/dev/null; then
      log ""
      log "--- Converting APK → JAR (dex2jar) ---"
      local jar_out="$OUTPUT_ABS/app.jar"
      d2j-dex2jar "$actual_target" -o "$jar_out" --force 2>&1 | tee -a "$LOG_FILE" || warn "dex2jar had errors"

      log ""
      log "--- Decompiling JAR with fernflower/vineflower ---"
      local ff_out="$OUTPUT_ABS/fernflower-sources"
      mkdir -p "$ff_out"
      if [[ "$ff_jar" == *.jar ]]; then
        java -jar "$ff_jar" "$jar_out" "$ff_out" 2>&1 | tee -a "$LOG_FILE" || warn "fernflower had errors"
      else
        "$ff_jar" "$jar_out" "$ff_out" 2>&1 | tee -a "$LOG_FILE" || warn "fernflower had errors"
      fi
      ok "fernflower output → $ff_out/"
    elif [[ "$use_engine" == "fernflower" ]]; then
      warn "fernflower/vineflower or dex2jar not found. Run: install-dep.sh vineflower dex2jar"
    fi
  fi

  # Manifest excerpt
  local manifest=""
  for mp in "$out/resources/AndroidManifest.xml" \
             "$out/AndroidManifest.xml" \
             "$(find "$out" -name 'AndroidManifest.xml' 2>/dev/null | head -1)"; do
    [[ -f "$mp" ]] && { manifest="$mp"; break; }
  done

  if [[ -n "$manifest" ]]; then
    log ""
    log "--- AndroidManifest.xml (key entries) ---"
    grep -E '(package=|activity|service|receiver|provider|permission|uses-permission|exported|android:name)' \
      "$manifest" 2>/dev/null | head -50 | tee -a "$LOG_FILE" || true
    cp "$manifest" "$OUTPUT_ABS/AndroidManifest.xml"
  fi

  # Package structure
  log ""
  log "--- Package Structure ---"
  find "$out" -type d 2>/dev/null | head -30 | sed "s|$out/||" | tee -a "$LOG_FILE" || true

  # API patterns
  log ""
  log "--- API / Network Patterns (for PoC targeting) ---"
  grep -rn --include="*.java" --include="*.kt" \
    -E '@(GET|POST|PUT|DELETE|PATCH)\s*\(|"https?://|baseUrl|OkHttpClient|Retrofit|api[_-]?key|bearer|Authorization|SSLContext|TrustManager|HostnameVerifier|setSSLSocketFactory|X509TrustManager' \
    "$out" 2>/dev/null | head -80 | tee -a "$LOG_FILE" || true

  log ""
  ok "Android decompile complete → $out/"
  echo "DECOMPILE_OUT:$out" >> "$META_FILE"
  echo "DECOMPILE_PLATFORM:android" >> "$META_FILE"
  [[ -n "$manifest" ]] && echo "MANIFEST:$manifest" >> "$META_FILE"
}

# ── .NET / WINDOWS PE ────────────────────────────────────────────────────────
decompile_dotnet() {
  local out="$OUTPUT_ABS/sources"
  mkdir -p "$out"
  log "=== .NET Decompile ==="

  local use_engine="${ENGINE:-ilspy}"

  # de4dot deobfuscation
  if [[ "$DEOBF" == true ]] && command -v de4dot &>/dev/null; then
    log "--- de4dot deobfuscation ---"
    local clean="$OUTPUT_ABS/deobf-$(basename "$TARGET_ABS")"
    de4dot "$TARGET_ABS" -o "$clean" 2>&1 | tee -a "$LOG_FILE" || warn "de4dot had errors"
    [[ -f "$clean" ]] && TARGET_ABS="$clean" && log "Deobfuscated: $clean"
    log ""
  fi

  if [[ "$use_engine" == "ilspy" || "$use_engine" == "both" ]] && command -v ilspycmd &>/dev/null; then
    log "--- Decompiling with ilspycmd ---"
    ilspycmd -p -o "$out" "$TARGET_ABS" 2>&1 | tee -a "$LOG_FILE" \
      || warn "ilspycmd had errors — partial output may still be useful"
    local ccount; ccount=$(find "$out" -name "*.cs" 2>/dev/null | wc -l)
    ok "ilspycmd: $ccount C# files → $out/"
  elif [[ "$use_engine" == "monodis" || "$use_engine" == "both" ]] || ! command -v ilspycmd &>/dev/null; then
    if command -v monodis &>/dev/null; then
      log "--- monodis IL disassembly ---"
      local il_file="$OUTPUT_ABS/$(basename "$TARGET_ABS" .dll).il"
      monodis "$TARGET_ABS" > "$il_file" 2>&1 | tee -a "$LOG_FILE" || warn "monodis had errors"
      ok "monodis IL → $il_file"
    else
      warn "ilspycmd and monodis not found. Run: bash $SCRIPT_DIR/install-dep.sh ilspycmd"
      log "--- Strings fallback ---"
      strings -a -n 6 "$TARGET_ABS" 2>/dev/null | \
        grep -E '([A-Z][a-z]+[A-Z]|namespace |class |void |public |private |string |int |bool )' | \
        head -80 | tee -a "$LOG_FILE" || true
    fi
  fi

  # Scan for dangerous patterns
  local cs_count; cs_count=$(find "$out" -name "*.cs" 2>/dev/null | wc -l)
  if [[ $cs_count -gt 0 ]]; then
    log ""
    log "--- Security-Relevant Patterns ---"
    grep -rn --include="*.cs" \
      -E '(SqlCommand|OleDbCommand|ExecuteReader|ExecuteNonQuery|HttpClient|WebRequest|Process\.Start|DllImport|Marshal\.|BinaryFormatter|JsonConvert.*TypeName|Environment\.GetEnvironmentVariable|AppSettings|connectionString|password|secret|api[_-]?key|SSLPolicyErrors|ServerCertificateValidationCallback|AllowAllCertificates|TrustAllCertificates)' \
      "$out" 2>/dev/null | head -80 | tee -a "$LOG_FILE" || true
  fi

  log ""
  ok ".NET decompile complete → $out/"
  echo "DECOMPILE_OUT:$out" >> "$META_FILE"
  echo "DECOMPILE_PLATFORM:dotnet" >> "$META_FILE"
}

# ── LINUX ELF ────────────────────────────────────────────────────────────────
decompile_linux() {
  local out="$OUTPUT_ABS/disasm"
  mkdir -p "$out"
  log "=== Linux ELF Decompile / Disassemble ==="

  local use_engine="${ENGINE:-r2}"

  log "--- File Info ---"
  file "$TARGET_ABS" | tee -a "$LOG_FILE"
  local arch; arch=$(file -b "$TARGET_ABS" | grep -oE 'x86-64|80386|ARM|aarch64|MIPS|PowerPC' | head -1 || echo "unknown")
  log "Architecture: $arch"

  if [[ "$use_engine" == "r2" || "$use_engine" == "both" ]] && command -v r2 &>/dev/null; then
    log ""
    log "--- radare2: Full Function List ---"
    r2 -A -q -c 'afl' "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" > "$out/functions.txt" || warn "r2 afl failed"

    log ""
    log "--- radare2: Decompile main() ---"
    r2 -A -q -c 'pdf @ main' "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" > "$out/main.disasm" 2>/dev/null || true

    log ""
    log "--- radare2: Dangerous Function Call Sites ---"
    r2 -A -q -c 'axt sym.imp.gets; axt sym.imp.strcpy; axt sym.imp.system; axt sym.imp.sprintf; axt sym.imp.scanf' \
      "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" > "$out/dangerous-xrefs.txt" || true

    ok "r2 output → $out/"
  fi

  if [[ "$use_engine" == "objdump" || "$use_engine" == "both" ]] || ! command -v r2 &>/dev/null; then
    log ""
    log "--- objdump: Full Disassembly ---"
    if command -v objdump &>/dev/null; then
      objdump -d -M intel "$TARGET_ABS" 2>/dev/null > "$out/disasm.asm" \
        && ok "objdump disasm → $out/disasm.asm" \
        || warn "objdump failed"
      objdump -d -M intel "$TARGET_ABS" 2>/dev/null | head -200 | tee -a "$LOG_FILE" || true
    else
      warn "objdump not found. Run: install-dep.sh objdump"
    fi
  fi

  # Symbol table
  log ""
  log "--- Symbol Table ---"
  if command -v nm &>/dev/null; then
    nm -D "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" > "$out/symbols.txt" || true
    nm -D "$TARGET_ABS" 2>/dev/null | head -60 | tee -a "$LOG_FILE" || true
  fi

  # Security mitigations
  log ""
  log "--- Security Mitigations ---"
  if command -v checksec &>/dev/null; then
    checksec --file="$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" || true
  else
    readelf -l "$TARGET_ABS" 2>/dev/null | grep -E '(GNU_STACK|GNU_RELRO)' | tee -a "$LOG_FILE" || true
    readelf -d "$TARGET_ABS" 2>/dev/null | grep -E '(BIND_NOW|FLAGS)' | tee -a "$LOG_FILE" || true
  fi

  # Dangerous functions
  log ""
  log "--- Dangerous Imported Functions ---"
  nm -D "$TARGET_ABS" 2>/dev/null | \
    grep -E ' U .*(gets|strcpy|strcat|sprintf|vsprintf|scanf|system|popen|exec[vl])' | \
    tee -a "$LOG_FILE" > "$out/dangerous-imports.txt" || true

  log ""
  ok "Linux ELF decompile complete → $out/"
  echo "DECOMPILE_OUT:$out" >> "$META_FILE"
  echo "DECOMPILE_PLATFORM:linux" >> "$META_FILE"
  echo "ARCH:$arch" >> "$META_FILE"
}

# ── WINDOWS PE (non-.NET) ────────────────────────────────────────────────────
decompile_windows() {
  local out="$OUTPUT_ABS/disasm"
  mkdir -p "$out"
  log "=== Windows PE Disassemble ==="

  log "--- File Info ---"
  file "$TARGET_ABS" | tee -a "$LOG_FILE"

  if command -v r2 &>/dev/null; then
    log ""
    log "--- radare2: Function List ---"
    r2 -A -q -c 'afl' "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" > "$out/functions.txt" || warn "r2 afl failed"
    log ""
    log "--- radare2: entry point disasm ---"
    r2 -A -q -c 'pdf @ entry0' "$TARGET_ABS" 2>/dev/null | head -100 | tee -a "$LOG_FILE" > "$out/entry0.disasm" || true
  fi

  if command -v objdump &>/dev/null; then
    log ""
    log "--- PE Headers (objdump) ---"
    objdump -f "$TARGET_ABS" 2>/dev/null | tee -a "$LOG_FILE" | head -20 || true
    log ""
    log "--- DLL Imports ---"
    objdump -p "$TARGET_ABS" 2>/dev/null | grep -A3 'DLL Name' | tee -a "$LOG_FILE" || true
    log ""
    log "--- Security Flags (DllCharacteristics) ---"
    objdump -p "$TARGET_ABS" 2>/dev/null | grep -E '(DllCharacteristics|DYNAMIC_BASE|NX_COMPAT|HIGH_ENTROPY_VA|NO_SEH|CFG)' | tee -a "$LOG_FILE" || true
  fi

  log ""
  ok "Windows PE disassemble complete → $out/"
  echo "DECOMPILE_OUT:$out" >> "$META_FILE"
  echo "DECOMPILE_PLATFORM:windows" >> "$META_FILE"
}

# ── iOS / macOS ───────────────────────────────────────────────────────────────
decompile_ios() {
  local out="$OUTPUT_ABS/disasm"
  mkdir -p "$out"
  log "=== iOS / macOS Mach-O Decompile ==="

  local binary="$TARGET_ABS"

  # IPA extraction
  if [[ "${TARGET_ABS##*.}" =~ ^[Ii][Pp][Aa]$ ]]; then
    log "--- Extracting IPA ---"
    local ipa_dir="$OUTPUT_ABS/ipa-extracted"
    mkdir -p "$ipa_dir"
    unzip -qo "$TARGET_ABS" -d "$ipa_dir"
    binary=$(find "$ipa_dir/Payload" -maxdepth 2 -type f ! -name "*.plist" ! -name "*.png" \
             2>/dev/null | xargs file 2>/dev/null | grep -i 'Mach-O' | head -1 | cut -d: -f1 || echo "")
    [[ -z "$binary" ]] && binary="$TARGET_ABS"
    log "Main binary: $binary"
  fi

  if command -v class-dump &>/dev/null; then
    log ""
    log "--- class-dump: Objective-C headers ---"
    local headers_dir="$out/headers"
    mkdir -p "$headers_dir"
    class-dump -H "$binary" -o "$headers_dir" 2>&1 | tee -a "$LOG_FILE" \
      || warn "class-dump failed (may be Swift-only binary)"
    ok "Headers → $headers_dir/"
  fi

  if command -v otool &>/dev/null; then
    log ""
    log "--- Linked Libraries ---"
    otool -L "$binary" 2>/dev/null | tee -a "$LOG_FILE" || true
    log ""
    log "--- Disassembly (entry, first 100 instructions) ---"
    otool -tV "$binary" 2>/dev/null | head -100 | tee -a "$LOG_FILE" > "$out/entry.disasm" || true
  fi

  log ""
  ok "iOS/macOS decompile complete → $out/"
  echo "DECOMPILE_OUT:$out" >> "$META_FILE"
  echo "DECOMPILE_PLATFORM:ios" >> "$META_FILE"
}

# ── SOURCE DIR ───────────────────────────────────────────────────────────────
decompile_source() {
  log "=== Source Code Analysis ==="
  log "Directory: $TARGET_ABS"
  log ""
  log "--- Language Detection ---"
  declare -A lang_counts
  while IFS= read -r ext; do
    lang_counts["$ext"]=$(( ${lang_counts["$ext"]:-0} + 1 ))
  done < <(find "$TARGET_ABS" -type f 2>/dev/null | grep -oE '\.[a-zA-Z0-9]+$' | sort)
  for ext in "${!lang_counts[@]}"; do
    printf "  %-10s %d files\n" "$ext" "${lang_counts[$ext]}"
  done | sort -k2 -rn | head -15 | tee -a "$LOG_FILE"

  log ""
  log "--- Security-Relevant Patterns ---"
  grep -rn \
    -E '(password\s*=\s*["\047][^\047"]{3,}|api[_-]?key\s*=\s*["\047][^\047"]{6,}|BEGIN.*PRIVATE KEY|AKIA[0-9A-Z]{16}|token\s*=\s*["\047][^\047"]{6,})' \
    "$TARGET_ABS" 2>/dev/null | head -30 | tee -a "$LOG_FILE" || true

  echo "DECOMPILE_OUT:$TARGET_ABS" >> "$META_FILE"
  echo "DECOMPILE_PLATFORM:source" >> "$META_FILE"
}

# ── DISPATCH ─────────────────────────────────────────────────────────────────
DECOMPILE_OUT=""
DECOMPILE_PLATFORM=""

case "$PLATFORM" in
  android)       decompile_android ;;
  dotnet)        decompile_dotnet ;;
  linux)         decompile_linux ;;
  windows)       decompile_windows ;;
  ios|macos)     decompile_ios ;;
  source)        decompile_source ;;
  *)             warn "Unknown platform '$PLATFORM'"; decompile_source ;;
esac

# Capture output path from meta file
DECOMPILE_OUT=$(grep '^DECOMPILE_OUT:' "$META_FILE" 2>/dev/null | tail -1 | cut -d: -f2-)
DECOMPILE_PLATFORM=$(grep '^DECOMPILE_PLATFORM:' "$META_FILE" 2>/dev/null | tail -1 | cut -d: -f2-)
[[ -z "$DECOMPILE_PLATFORM" ]] && DECOMPILE_PLATFORM="$PLATFORM"

# ── PoC GENERATION ───────────────────────────────────────────────────────────
if [[ "$GEN_POC" == true ]]; then
  log ""
  log "=== PoC Script Generation ==="
  mkdir -p "$POC_DIR"

  POC_SCRIPT="$SCRIPT_DIR/vuln-poc.sh"
  if [[ -f "$POC_SCRIPT" ]]; then
    local effective_src="${DECOMPILE_OUT:-$OUTPUT_ABS}"
    # For android, prefer the sources dir if it exists
    [[ "$DECOMPILE_PLATFORM" == "android" && -d "$OUTPUT_ABS/sources" ]] && effective_src="$OUTPUT_ABS/sources"
    bash "$POC_SCRIPT" "$TARGET_ABS" \
      --platform "$DECOMPILE_PLATFORM" \
      --source-dir "$effective_src" \
      -o "$POC_DIR" 2>&1 | tee -a "$LOG_FILE"
    ok "PoC scripts → $POC_DIR/"
  else
    warn "vuln-poc.sh not found at $POC_SCRIPT"
  fi
fi

log ""
log "=== Decompile complete ==="
log "Output: $OUTPUT_ABS"
log "Log:    $LOG_FILE"
[[ "$GEN_POC" == true ]] && log "PoC:    $POC_DIR/"
