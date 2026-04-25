# Universal Reverse Engineering & Vulnerability Detection Skill

> **Author**: [FURQANAHMAD34](https://github.com/FURQANAHMAD34) — [devyforge.com](https://devyforge.com)

A universal plugin/skill for AI coding assistants that adds expert-level reverse
engineering, vulnerability detection, and **working PoC exploit generation** for
**every major binary format and source language** — auto-installs all required tools.

---

## What It Does

| Capability | Details |
|-----------|---------|
| **Decompile** | APK/XAPK → jadx/fernflower; .NET EXE/DLL → ilspycmd; ELF → radare2/objdump; IPA → otool/class-dump |
| **Vulnerability Scan** | 40+ classes: buffer overflow, SQL injection, SSL bypass, deserialization, hardcoded secrets, format string, command injection |
| **PoC Generation** | Runnable Python/Bash/C exploit scripts: SSL bypass (Frida), BOF (pwntools), SQLi, deserialization (ysoserial) |
| **Auto Tool Install** | `install-dep.sh` installs 40+ tools (jadx, checksec, radare2, pwntools, frida, ilspycmd, etc.) without manual setup |
| **Binary Hardening** | Stack canary, NX/DEP, PIE/ASLR, RELRO, FORTIFY, CFG, SafeSEH via checksec |
| **Secret Scanning** | API keys, passwords, private keys, AWS creds in source + binaries |

---

## Commands (Claude Code)

| Command | What it does |
|---------|-------------|
| `/analyze <file>` | Auto-detect + static analysis for any binary/app/source |
| `/decompile <file>` | Decompile any target → auto-installs tools → generates PoC scripts |
| `/vuln_poc <file>` | Deep scan → finds real offsets/validation gaps → generates runnable exploits |
| `/vuln-scan <file>` | Vulnerability scan only (source or binary) |

### `/decompile` — Cross-platform decompiler + PoC generator

```
/decompile app.apk              → jadx decompile + SSL bypass PoC
/decompile malware.exe          → ilspycmd .NET decompile + SQLi PoC
/decompile target_binary        → r2 disasm + buffer overflow PoC
/decompile app.ipa              → class-dump + Frida hook PoC
/decompile app.xapk             → XAPK extract → jadx + PoC
```

Auto-installs required tools before running. After decompile, generates working PoC scripts:

| Target | PoC Scripts Generated |
|--------|----------------------|
| Android APK | `poc-ssl-bypass.py` (Frida 5-layer), `poc-sms-intercept.py`, `poc-root-bypass.py`, `poc-webview-xss.html`, `poc-intent-fuzzer.sh` |
| Linux ELF | `poc-bof.py` (pwntools ret2libc/shellcode), `poc-cmd-inject.py`, `poc-fmt-string.py` |
| .NET / Windows | `poc-sqli.py`, `poc-deserialization.py` (ysoserial.net gadget chains) |

### `/vuln_poc` — Deep vulnerability scan + exploit generation

Goes beyond identification — finds actual offsets, validation control bypasses, and codebase logic flaws:

```
/vuln_poc app.apk               → MCC bypass detection, SSL audit, OTP intercept
/vuln_poc target_elf            → BOF offset, ROP gadgets, system() xrefs
/vuln_poc dotnet.dll            → SQLi endpoints, unsafe deser, auth gaps
```

---

## Supported Platforms & Tools

| Platform | Decompile Engine | Vulnerability Tools |
|----------|-----------------|---------------------|
| Android APK/XAPK | jadx, fernflower/vineflower | frida, semgrep, gitleaks |
| iOS IPA / Mach-O | class-dump, otool | frida, codesign |
| Windows PE / .NET | ilspycmd, monodis, de4dot | checksec, semgrep |
| Linux ELF | radare2, objdump | checksec, pwntools, ROPgadget |
| macOS Mach-O | otool, nm, lipo | codesign, r2 |
| Source (C/Python/Java/Go/C#) | direct | semgrep, bandit, flawfinder, gosec |

---

## Tools Integrated (40+)

| Category | Tools |
|----------|-------|
| **Android** | jadx, apktool, dex2jar, vineflower/fernflower, adb |
| **iOS / macOS** | otool, class-dump, codesign, lipo, ipsw, frida |
| **Windows PE** | objdump, checksec, upx, radare2 |
| **Linux ELF** | readelf, objdump, nm, checksec, strace, ltrace, radare2 |
| **.NET** | ilspycmd, dotnet SDK, monodis, de4dot |
| **SAST / Secrets** | semgrep, bandit, cppcheck, flawfinder, gitleaks, trufflehog, gosec |
| **Exploit Dev** | pwntools, ROPgadget, ropper, one\_gadget, angr, patchelf, seccomp-tools |
| **Debugging** | gdb, pwndbg, GEF, PEDA, lldb, valgrind |
| **Advanced RE** | Ghidra, Cutter, RetDec, radare2, binwalk, volatility3 |
| **Fuzzing** | AFL++ |
| **Runtime Hooks** | frida-tools (Android/iOS SSL bypass, root bypass, method hooks) |

All tools are auto-installed via `scripts/install-dep.sh <name>`.

---

## Vulnerability Classes Detected

**Memory Safety (Binary/C/C++):**
Stack buffer overflow · Heap buffer overflow · Use-after-free · Double free ·
Integer overflow/underflow · Format string · Null pointer dereference · Off-by-one

**Binary Hardening:**
No NX/DEP · No PIE/ASLR · No stack canary · No RELRO · No FORTIFY ·
No CFG (Windows) · No SafeSEH (Windows)

**Injection:**
Command injection · SQL injection · LDAP injection · XML/XPath injection ·
Template injection · Header injection

**Mobile (Android/iOS):**
SSL pinning bypass · MCC-conditional certificate validation · Root detection bypass ·
Exported component abuse · WebView JavaScript bridge · SMS/OTP interception ·
Hardcoded API keys · Insecure SharedPreferences · Cleartext traffic

**Cryptography:**
Hardcoded key · Hardcoded IV · MD5/SHA1/DES/RC4 · ECB mode · Weak key size ·
Predictable random · Self-signed cert acceptance

**Secrets:**
Passwords · API keys · Auth tokens · Private keys · AWS credentials ·
Database connection strings · Cleartext HTTP

**Deserialization:**
Python pickle/yaml · Java ObjectInputStream · .NET BinaryFormatter ·
PHP unserialize · JSON TypeNameHandling (All/Objects)

**Web/API:**
XXE · SSRF · Open redirect · Insecure CORS · Missing CSRF · SQL injection

---

## Installation

---

### Claude Code

The native plugin format — gives you `/analyze`, `/decompile`, `/vuln_poc`, `/vuln-scan` slash commands.

#### Option A — Local install from this repo

```bash
# 1. Clone the repo
git clone https://github.com/FURQANAHMAD34/universal-re-skill.git
cd universal-re-skill

# 2. Install the plugin into Claude Code
claude plugin install ./plugins/universal-reverse-engineering

# 3. Verify
claude plugin list
# Should show: universal-reverse-engineering  v2.0.0

# 4. Use it
claude
# /decompile app.apk
# /vuln_poc target_binary
# /analyze malware.exe
```

#### Option B — Install from GitHub

```bash
claude plugin install https://github.com/FURQANAHMAD34/universal-re-skill
```

#### Option C — Manual install (no CLI)

```bash
mkdir -p ~/.claude/plugins/
cp -r plugins/universal-reverse-engineering ~/.claude/plugins/
# Restart Claude Code
```

#### Commands reference

```bash
# Decompile + auto PoC generation
/decompile app.apk
/decompile malware.exe --engine ilspy
/decompile target_bin --platform linux

# Deep vuln scan with runnable exploit scripts
/vuln_poc app.apk
/vuln_poc target.elf
/vuln_poc ./src/

# Full static analysis (all platforms)
/analyze app.apk
/analyze target.exe --deep
/analyze ./src --vuln

# Vulnerability scan only
/vuln-scan ./src
/vuln-scan malware.elf
```

---

### Cursor

Cursor reads `.cursorrules` from the project root or `~/.cursorrules` globally.

```bash
# Per-project
cp ai-integrations/cursor/.cursorrules /path/to/your/project/.cursorrules

# Global (all projects)
cp ai-integrations/cursor/.cursorrules ~/.cursorrules
```

Then ask naturally in Cursor:
```
Decompile this APK and generate an SSL bypass script
Find all buffer overflows in src/ and write a pwntools exploit
Check if this binary has NX and stack canary enabled
```

---

### Windsurf

```bash
cp ai-integrations/windsurf/.windsurfrules /path/to/your/project/.windsurfrules
```

---

### GitHub Copilot

```bash
mkdir -p .github
cp ai-integrations/github-copilot/.github/copilot-instructions.md .github/copilot-instructions.md
```

Ask in Copilot Chat:
```
@workspace decompile target.elf and find exploitable vulnerabilities
@workspace generate a Frida SSL bypass for this APK
@workspace find SQL injection in src/ and write a PoC
```

---

### Aider

```bash
# Per-project
cp ai-integrations/aider/.aider.conf.yml /path/to/your/project/.aider.conf.yml

# One-shot analysis
aider --message "Decompile app.apk and generate PoC scripts for all vulnerabilities" app.apk
```

---

### Continue.dev

```bash
cp ai-integrations/continue-dev/config.json ~/.continue/config.json
```

Commands available in Continue.dev: `/analyze`, `/vuln`

---

### OpenAI Codex CLI

```bash
codex --system-prompt "$(cat ai-integrations/codex-cli/system-prompt.md)" \
      "Decompile target.exe and find exploitable vulnerabilities"
```

---

### Any LLM / API

```python
# Anthropic Claude API
import anthropic
client = anthropic.Anthropic()

with open("ai-integrations/generic/system-prompt.md") as f:
    system_prompt = f.read()

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=8192,
    system=system_prompt,
    messages=[{"role": "user", "content": "Decompile app.apk and generate an SSL bypass PoC"}]
)
print(response.content[0].text)
```

---

## Quick Tool Install

```bash
SCRIPTS=plugins/universal-reverse-engineering/skills/universal-reverse-engineering/scripts

# Check everything
bash $SCRIPTS/check-deps.sh all

# Android + SSL bypass
bash $SCRIPTS/install-dep.sh java
bash $SCRIPTS/install-dep.sh jadx
bash $SCRIPTS/install-dep.sh apktool
pip install frida-tools

# Binary analysis + exploit dev
bash $SCRIPTS/install-dep.sh checksec
bash $SCRIPTS/install-dep.sh radare2
bash $SCRIPTS/install-dep.sh pwntools
bash $SCRIPTS/install-dep.sh ropgadget
bash $SCRIPTS/install-dep.sh gdb
bash $SCRIPTS/install-dep.sh pwndbg

# .NET decompile
bash $SCRIPTS/install-dep.sh ilspycmd
bash $SCRIPTS/install-dep.sh monodis

# SAST / secret scanning
bash $SCRIPTS/install-dep.sh semgrep
bash $SCRIPTS/install-dep.sh bandit
bash $SCRIPTS/install-dep.sh gitleaks

# Advanced RE
bash $SCRIPTS/install-dep.sh ghidra
bash $SCRIPTS/install-dep.sh cutter
bash $SCRIPTS/install-dep.sh angr
```

---

## Standalone Script Usage (no AI needed)

The scripts work standalone without any AI model:

```bash
PLUGIN_ROOT=plugins/universal-reverse-engineering

# Decompile + generate PoC scripts
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/decompile.sh app.apk --poc
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/decompile.sh target.elf --poc
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/decompile.sh malware.exe --platform dotnet --poc

# Deep vuln scan + PoC generation
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/vuln-poc.sh app.apk --platform android
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/vuln-poc.sh target.elf --platform linux

# Auto-analyze any target
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/analyze.sh auto target.apk
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/analyze.sh linux ./binary -o report/

# Vulnerability scan
bash $PLUGIN_ROOT/skills/vulnerability-scanner/scripts/vuln-scan.sh ./src -o vulns/

# Binary hardening check
bash $PLUGIN_ROOT/skills/vulnerability-scanner/scripts/check-binary-security.sh ./binary
```

---

## File Structure

```
universal-re-skill/
├── .claude-plugin/marketplace.json
├── README.md
├── plugins/
│   └── universal-reverse-engineering/
│       ├── .claude-plugin/plugin.json       ← v2.0.0
│       ├── commands/
│       │   ├── analyze.md                   ← /analyze
│       │   ├── decompile.md                 ← /decompile  ★ NEW
│       │   ├── vuln_poc.md                  ← /vuln_poc   ★ NEW
│       │   └── vuln-scan.md                 ← /vuln-scan
│       └── skills/
│           ├── universal-reverse-engineering/
│           │   ├── SKILL.md
│           │   ├── references/
│           │   │   ├── setup-guide.md
│           │   │   ├── android.md
│           │   │   ├── ios.md
│           │   │   ├── windows-pe.md
│           │   │   ├── linux-elf.md
│           │   │   ├── macos-macho.md
│           │   │   ├── dotnet.md
│           │   │   └── debugging-exploit-dev.md
│           │   └── scripts/
│           │       ├── detect-target.sh     ← auto-detect file type
│           │       ├── check-deps.sh        ← dependency checker
│           │       ├── install-dep.sh       ← auto-installer (40+ tools)
│           │       ├── analyze.sh           ← static analysis dispatcher
│           │       ├── decompile.sh         ← cross-platform decompiler  ★ NEW
│           │       └── vuln-poc.sh          ← PoC exploit generator       ★ NEW
│           └── vulnerability-scanner/
│               ├── SKILL.md
│               └── scripts/
│                   ├── vuln-scan.sh
│                   ├── scan-source.sh
│                   └── check-binary-security.sh
└── ai-integrations/
    ├── cursor/.cursorrules
    ├── windsurf/.windsurfrules
    ├── github-copilot/.github/copilot-instructions.md
    ├── aider/.aider.conf.yml
    ├── continue-dev/config.json
    ├── codex-cli/system-prompt.md
    ├── amazon-q/INSTALL.md
    └── generic/system-prompt.md
```

---

## PoC Generation — What You Get

### Android SSL Bypass (Example — Real Caller)

`/decompile real-caller.apk` + `/vuln_poc real-caller.apk` generates a ready-to-run Frida script covering:

- **Layer 1** — MCC spoof: forces `mainmcc = 424` (UAE), disabling pinning in `returnAppSecureCntxUrlBks*`
- **Layer 2** — SSLContext injection: replaces cert-pinned `sslContext` with a permissive TrustManager, defeating `returnAppSecureCntxUrlBksForcePan`
- **Layer 3** — `setSSLSocketFactory` hook: neutralizes any remaining pinned factory at connection level
- **Layer 4** — OkHttp3, WebView, Network Security Config bypass

```bash
# Run the generated bypass:
frida -U -f menwho.phone.callerid.social -l poc-ssl-bypass-real-caller.py --no-pause

# Set Burp proxy on device:
adb shell settings put global http_proxy 192.168.1.x:8080
```

### Linux ELF Buffer Overflow (Example)

`/vuln_poc target_elf` generates a pwntools script with:
- Correct architecture detection (x86/x86-64/ARM)
- `checksec` mitigations read automatically
- ret2libc path (NX enabled) or shellcode path (NX disabled)
- Placeholder offsets with exact gdb/pwndbg commands to find them
- ROP gadget search commands

```bash
python3 poc-bof.py LOCAL
python3 poc-bof.py REMOTE 10.10.10.1 4444
```

### .NET Deserialization (Example)

`/vuln_poc malware.dll` generates a ysoserial.net wrapper that:
- Tries all gadget chains (TypeConfuseDelegate, ObjectDataProvider, etc.)
- Targets all detected formatters (BinaryFormatter, NetDataContractSerializer)
- Sends payload to the discovered API endpoint

---

## Contributors

| GitHub | Website |
|--------|---------|
| [@FURQANAHMAD34](https://github.com/FURQANAHMAD34) | [devyforge.com](https://devyforge.com) |
| [@SimoneAvogadro](https://github.com/SimoneAvogadro) | [android-reverse-engineering-skill](https://github.com/SimoneAvogadro/android-reverse-engineering-skill) |

---

## License

Apache 2.0 — see LICENSE file.

---

<p align="center">Built by <a href="https://devyforge.com">devyforge.com</a></p>
