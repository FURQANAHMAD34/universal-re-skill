# Universal Reverse Engineering & Vulnerability Detection Skill

> **Author**: [FURQANAHMAD34](https://github.com/FURQANAHMAD34) — [devyforge.com](https://devyforge.com)

A universal plugin/skill for AI coding assistants that adds expert-level reverse
engineering and vulnerability detection capabilities for **every major binary format
and source language**.

---

## What It Does

| Capability | Platforms |
|-----------|----------|
| **Reverse Engineering** | Android APK/XAPK/JAR, iOS IPA/dylib, Windows EXE/DLL/SYS, Linux ELF, macOS Mach-O, .NET assemblies |
| **Vulnerability Detection** | C/C++, Python, Java/Kotlin, JavaScript/TypeScript, Go, C#/.NET, compiled binaries |
| **Binary Hardening Check** | Stack canary, NX/DEP, PIE/ASLR, RELRO, FORTIFY, CFG, SafeSEH |
| **Secret Scanning** | API keys, passwords, private keys, AWS creds, tokens in source + binaries |

---

## Supported AI Models

| AI Model | Integration Method | File |
|----------|-------------------|------|
| **Claude Code** | Plugin (skill + commands) | See [Claude Code Install](#claude-code) |
| **Cursor** | `.cursorrules` | `ai-integrations/cursor/.cursorrules` |
| **Windsurf** | `.windsurfrules` | `ai-integrations/windsurf/.windsurfrules` |
| **GitHub Copilot** | `.github/copilot-instructions.md` | `ai-integrations/github-copilot/` |
| **Aider** | `.aider.conf.yml` | `ai-integrations/aider/.aider.conf.yml` |
| **Continue.dev** | `config.json` with slash commands | `ai-integrations/continue-dev/config.json` |
| **OpenAI Codex CLI** | `--system-prompt` flag | `ai-integrations/codex-cli/system-prompt.md` |
| **Amazon Q Developer** | Workspace context + CLI | `ai-integrations/amazon-q/INSTALL.md` |
| **Any LLM** | System prompt | `ai-integrations/generic/system-prompt.md` |

---

## Tools Integrated (40+)

| Category | Tools |
|----------|-------|
| **Android** | jadx, apktool, dex2jar, vineflower, adb |
| **iOS / macOS** | otool, class-dump, codesign, lipo, ipsw, frida |
| **Windows PE** | objdump, checksec, upx, radare2 |
| **Linux ELF** | readelf, objdump, nm, checksec, strace, ltrace, radare2 |
| **.NET** | ilspycmd, dotnet SDK, monodis, de4dot |
| **SAST / Secrets** | semgrep, bandit, cppcheck, flawfinder, gitleaks, trufflehog, gosec |
| **Debugging** | gdb, pwndbg, GEF, PEDA, lldb, valgrind |
| **Exploit Dev** | pwntools, ROPgadget, ropper, one\_gadget, angr, patchelf, seccomp-tools |
| **Advanced RE** | Ghidra, Cutter, RetDec, radare2, binwalk, volatility3 |
| **Fuzzing** | AFL++ |

All tools are auto-installable via `scripts/install-dep.sh <name>`.

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

**Cryptography:**
Hardcoded key · Hardcoded IV · MD5/SHA1/DES/RC4 · ECB mode · Weak key size ·
Predictable random in security context

**Secrets:**
Passwords · API keys · Auth tokens · Private keys · AWS credentials ·
Database connection strings · Cleartext HTTP

**Deserialization:**
Python pickle/yaml · Java ObjectInputStream · .NET BinaryFormatter ·
PHP unserialize · JSON TypeNameHandling

**Web/API:**
XXE · SSRF · Open redirect · Insecure CORS · Missing CSRF

---

## Installation by AI Model

---

### Claude Code

The native plugin format. Works with the `/analyze` and `/vuln-scan` slash commands.

#### Option A — Local install from this repo

```bash
# 1. Clone the repo
git clone https://github.com/FURQANAHMAD34/universal-re-skill.git
cd universal-re-skill

# 2. Install the plugin into Claude Code
claude plugin install ./plugins/universal-reverse-engineering

# 3. Verify installation
claude plugin list
# Should show: universal-reverse-engineering

# 4. Use it
claude   # open Claude Code
# Then: /analyze path/to/target
# Or:   /vuln-scan path/to/source
```

#### Option B — Install from marketplace URL

```bash
claude plugin install https://github.com/FURQANAHMAD34/universal-re-skill
```

#### Option C — Manual install (no CLI)

```bash
# Copy plugin to Claude Code's plugin directory
mkdir -p ~/.claude/plugins/
cp -r plugins/universal-reverse-engineering ~/.claude/plugins/

# Restart Claude Code
```

#### Using Claude Code commands

```
/analyze app.apk              → auto-detect + reverse engineer
/analyze target.exe --deep    → deep analysis with radare2
/analyze ./src --vuln         → source + vuln scan
/vuln-scan ./src              → vulnerability scan only
/vuln-scan malware.elf        → binary security check
```

---

### Cursor

Cursor reads `.cursorrules` from the project root or `~/.cursorrules` globally.

#### Per-project install

```bash
cp ai-integrations/cursor/.cursorrules /path/to/your/project/.cursorrules
```

#### Global install (applies to all Cursor projects)

```bash
cp ai-integrations/cursor/.cursorrules ~/.cursorrules
```

#### Use in Cursor

Open Cursor in your project directory and type naturally:
```
Analyze this APK for me: app-release.apk
Find all buffer overflows in the src/ directory
Check if this binary has NX and ASLR enabled
Decompile target.exe and look for hardcoded credentials
```

Cursor will follow the RE workflows defined in `.cursorrules` automatically.

---

### Windsurf

Windsurf reads `.windsurfrules` from the workspace root.

#### Install

```bash
cp ai-integrations/windsurf/.windsurfrules /path/to/your/project/.windsurfrules
```

#### Global install

```bash
# Windsurf also reads from user home
cp ai-integrations/windsurf/.windsurfrules ~/.windsurfrules
```

#### Use in Windsurf

Same as Cursor — type naturally in the Windsurf Cascade panel:
```
Reverse engineer this ELF binary
Scan the src/ directory for SQL injection and command injection
Check binary hardening for target.dll
```

---

### GitHub Copilot

Copilot reads workspace instructions from `.github/copilot-instructions.md`.

#### Install

```bash
mkdir -p .github
cp ai-integrations/github-copilot/.github/copilot-instructions.md .github/copilot-instructions.md
```

#### Use in VS Code / JetBrains / GitHub.com

Ask Copilot Chat:
```
@workspace analyze the binary target.elf
@workspace find vulnerabilities in src/
@workspace what security mitigations does this PE have?
```

Or use the **Copilot Chat** inline panel and reference this project.

---

### Aider

Aider supports a project-level `.aider.conf.yml` or global `~/.aider.conf.yml`.

#### Per-project install

```bash
cp ai-integrations/aider/.aider.conf.yml /path/to/your/project/.aider.conf.yml
```

#### Global install

```bash
cp ai-integrations/aider/.aider.conf.yml ~/.aider.conf.yml
```

#### Use with Aider

```bash
# Standard usage — the system prompt is injected automatically
aider

# Explicit override if needed
aider --system-prompt "$(cat ai-integrations/generic/system-prompt.md)"

# One-shot analysis
aider --message "Analyze app.apk and report all security findings" app.apk
```

---

### Continue.dev

Continue reads `~/.continue/config.json` for global config.

#### Install

```bash
# Backup existing config if you have one
cp ~/.continue/config.json ~/.continue/config.json.bak 2>/dev/null || true

# Install our config (CAUTION: replaces existing config — merge manually if needed)
cp ai-integrations/continue-dev/config.json ~/.continue/config.json
```

#### Merge with existing config (recommended)

Open `~/.continue/config.json` and add:
1. The `systemMessage` field value from `ai-integrations/continue-dev/config.json`
2. The `slashCommands` entries (`/analyze` and `/vuln`)

#### Use in Continue.dev (VS Code / JetBrains)

```
/analyze                    → guided reverse engineering
/vuln                       → vulnerability scan
Ask: "Find all format string vulnerabilities in this C file"
```

---

### OpenAI Codex CLI

Codex CLI (`codex`) supports `--system-prompt` or a global config file.

#### One-shot usage

```bash
codex --system-prompt "$(cat ai-integrations/codex-cli/system-prompt.md)" \
      "Analyze target.exe for vulnerabilities"
```

#### Set as default system prompt

```bash
# Add to your shell profile:
export OPENAI_SYSTEM_PROMPT_FILE="$HOME/.config/codex-re-prompt.md"
cp ai-integrations/codex-cli/system-prompt.md ~/.config/codex-re-prompt.md

# Then in your shell init, alias codex to include the prompt:
alias codex-re='codex --system-prompt "$(cat $OPENAI_SYSTEM_PROMPT_FILE)"'
```

#### Config file method

```bash
mkdir -p ~/.config/codex
cat > ~/.config/codex/config.json << EOF
{
  "systemPrompt": "$(cat ai-integrations/codex-cli/system-prompt.md | tr '\n' ' ')"
}
EOF
```

#### Usage

```bash
codex-re "Decompile this APK and show me all the API endpoints"
codex-re "Check if ./binary has stack protection and NX"
codex-re "Find all hardcoded secrets in the src/ directory"
```

---

### Amazon Q Developer

See `ai-integrations/amazon-q/INSTALL.md` for full instructions.

#### Quick install (workspace context)

```bash
mkdir -p .amazonq
cp ai-integrations/amazon-q/INSTALL.md .amazonq/  # read the instructions
# Then create .amazonq/customization.md as described in INSTALL.md
```

---

### Any Other LLM / AI Tool

Use the generic system prompt with any LLM that accepts a system message:

```bash
# View the prompt
cat ai-integrations/generic/system-prompt.md

# OpenAI Python SDK
python3 << EOF
from openai import OpenAI
client = OpenAI()

with open("ai-integrations/generic/system-prompt.md") as f:
    system_prompt = f.read()

response = client.chat.completions.create(
    model="gpt-4o",
    messages=[
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": "Analyze target.elf for vulnerabilities"}
    ]
)
print(response.choices[0].message.content)
EOF

# Anthropic Claude API
python3 << EOF
import anthropic
client = anthropic.Anthropic()

with open("ai-integrations/generic/system-prompt.md") as f:
    system_prompt = f.read()

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=4096,
    system=system_prompt,
    messages=[{"role": "user", "content": "Analyze target.elf for vulnerabilities"}]
)
print(response.content[0].text)
EOF

# Ollama (local models)
ollama run llama3 "$(cat ai-integrations/generic/system-prompt.md)

USER: Analyze this binary for vulnerabilities. File type: $(file ./target)"
```

---

## Quick Tool Install

```bash
SCRIPTS=plugins/universal-reverse-engineering/skills/universal-reverse-engineering/scripts

# Check what's missing first
bash $SCRIPTS/check-deps.sh all

# Android
bash $SCRIPTS/install-dep.sh java
bash $SCRIPTS/install-dep.sh jadx
bash $SCRIPTS/install-dep.sh apktool

# Binary analysis
bash $SCRIPTS/install-dep.sh checksec
bash $SCRIPTS/install-dep.sh radare2
bash $SCRIPTS/install-dep.sh binwalk

# SAST / vuln scanning
bash $SCRIPTS/install-dep.sh semgrep
bash $SCRIPTS/install-dep.sh bandit
bash $SCRIPTS/install-dep.sh gitleaks

# Debugging & exploit dev
bash $SCRIPTS/install-dep.sh gdb
bash $SCRIPTS/install-dep.sh pwndbg
bash $SCRIPTS/install-dep.sh pwntools
bash $SCRIPTS/install-dep.sh ropgadget
bash $SCRIPTS/install-dep.sh angr

# Advanced RE suites
bash $SCRIPTS/install-dep.sh ghidra
bash $SCRIPTS/install-dep.sh cutter
```

---

## Standalone Script Usage (no AI model needed)

The scripts work standalone too:

```bash
PLUGIN_ROOT=plugins/universal-reverse-engineering

# Auto-analyze any target
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/analyze.sh auto target.apk

# Specific platform
bash $PLUGIN_ROOT/skills/universal-reverse-engineering/scripts/analyze.sh linux ./binary -o report/

# Vulnerability scan
bash $PLUGIN_ROOT/skills/vulnerability-scanner/scripts/vuln-scan.sh ./src -o vulns/

# Binary hardening check
bash $PLUGIN_ROOT/skills/vulnerability-scanner/scripts/check-binary-security.sh ./binary

# Source scan
bash $PLUGIN_ROOT/skills/vulnerability-scanner/scripts/scan-source.sh ./src -o report/
```

---

## File Structure

```
universal-re-skill/
├── .claude-plugin/marketplace.json        ← Claude Code marketplace entry
├── README.md                              ← this file
├── plugins/
│   └── universal-reverse-engineering/
│       ├── .claude-plugin/plugin.json
│       ├── commands/
│       │   ├── analyze.md                 ← /analyze slash command
│       │   └── vuln-scan.md              ← /vuln-scan slash command
│       └── skills/
│           ├── universal-reverse-engineering/
│           │   ├── SKILL.md              ← main skill definition
│           │   ├── references/
│           │   │   ├── setup-guide.md            ← all tools + one-line installs
│           │   │   ├── android.md
│           │   │   ├── ios.md
│           │   │   ├── windows-pe.md
│           │   │   ├── linux-elf.md
│           │   │   ├── macos-macho.md
│           │   │   ├── dotnet.md
│           │   │   └── debugging-exploit-dev.md  ← GDB, Ghidra, pwntools, ROP, angr
│           │   └── scripts/
│           │       ├── detect-target.sh  ← auto-detect file type
│           │       ├── check-deps.sh     ← dependency checker
│           │       ├── install-dep.sh    ← auto-installer
│           │       └── analyze.sh        ← main analysis dispatcher
│           └── vulnerability-scanner/
│               ├── SKILL.md              ← vuln detection skill
│               └── scripts/
│                   ├── vuln-scan.sh      ← master vuln scanner
│                   ├── scan-source.sh    ← source code scanner
│                   └── check-binary-security.sh ← binary hardening
└── ai-integrations/
    ├── claude-code/
    ├── cursor/.cursorrules
    ├── windsurf/.windsurfrules
    ├── github-copilot/.github/copilot-instructions.md
    ├── aider/.aider.conf.yml
    ├── continue-dev/config.json
    ├── codex-cli/system-prompt.md
    ├── amazon-q/INSTALL.md
    └── generic/system-prompt.md          ← any LLM / API
```

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
