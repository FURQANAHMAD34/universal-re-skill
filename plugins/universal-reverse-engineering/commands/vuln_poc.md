---
allowed-tools: Bash, Read, Glob, Grep, Write, Edit
description: Deep vulnerability scan with working PoC exploit generation — finds real flaws (offsets, validation gaps, codebase controls) and produces runnable exploit scripts
user-invocable: true
argument-hint: <path to binary, APK, EXE, ELF, DLL, IPA, or source directory>
argument: path to target file or directory (optional)
---

# /vuln_poc

Perform deep vulnerability analysis on any target and generate **working, runnable PoC exploit scripts** — not just identification. This goes beyond surface scanning: it finds real offsets, validation control bypasses, authentication gaps, and codebase logic flaws, then produces Python/Bash/C PoC code you can run immediately.

## Instructions

You are running the full vulnerability + PoC generation workflow. Follow every step.

### Step 1: Get the target

If the user provided a file path as an argument, use it. Otherwise ask.

Resolve the absolute path. If a decompiled source directory already exists from a previous `/decompile` run, detect it:

```bash
ls /tmp/re-results/<basename>-decompiled/ 2>/dev/null
```

If a source directory exists, use it as the scan target for source-level analysis.

### Step 2: Auto-detect target and platform

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/detect-target.sh <file_path>
```

Parse `TARGET_TYPE:` and `TARGET_ARCH:`. If the file was already decompiled, also check:
```bash
grep 'DECOMPILE_PLATFORM:' /tmp/re-results/<basename>-decompiled/decompile.log 2>/dev/null | tail -1
```

### Step 3: Install required tools

Check and install all vulnerability scanning tools:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/check-deps.sh vuln
```

Install any missing tools. Key tools for PoC generation:

| Tool | Purpose | Install |
|------|---------|---------|
| `checksec` | Binary hardening analysis | `install-dep.sh checksec` |
| `radare2` (r2) | Function list, xrefs, disassembly | `install-dep.sh radare2` |
| `semgrep` | Source SAST | `install-dep.sh semgrep` |
| `pwntools` | BOF/ROP exploit framework | `install-dep.sh pwntools` |
| `ROPgadget` | ROP chain building | `install-dep.sh ropgadget` |
| `frida-tools` | Android/iOS runtime hooks | `pip install frida-tools` |
| `de4dot` | .NET deobfuscation | `install-dep.sh de4dot` |

For binary targets (Linux ELF), also install: `gdb`, `pwndbg`, `pwntools`, `ROPgadget`
For Android targets, also install: `jadx` (if not already decompiled)

### Step 4: Decompile if not already done

If no decompiled source directory exists, run decompile first:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/decompile.sh \
  <file_path> \
  --platform <platform> \
  -o /tmp/re-results/<basename>-decompiled
```

Then set `SOURCE_DIR=/tmp/re-results/<basename>-decompiled/sources` (or `/disasm` for binary targets).

### Step 5: Run the full vulnerability + PoC scanner

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/vuln-poc.sh \
  <file_path> \
  --platform <platform> \
  --source-dir <source_dir_if_available> \
  -o /tmp/re-results/<basename>-poc \
  --level full
```

Watch the output carefully. Note every vulnerability class detected and every PoC file generated.

### Step 6: Perform manual deep analysis

Beyond what the automated scanner finds, perform these manual checks based on platform:

**For Android APKs:**

Search for MCC-based conditional security bypasses (like real-world SSL bypass patterns):
```bash
grep -rn 'mcc\|MCC\|countryCode\|getNetworkCountryIso\|OPERATOR' \
  <source_dir> 2>/dev/null | head -30
```

Find authentication validation logic:
```bash
grep -rn --include="*.java" --include="*.kt" \
  -E '(verify|validate|check|authenticate|isValid|authorize)\s*\(' \
  <source_dir> 2>/dev/null | grep -v '//' | head -40
```

Find HWID / license / DRM checks:
```bash
grep -rn --include="*.java" --include="*.kt" \
  -E '(getDeviceId|IMEI|IMSI|getSerial|Build\.SERIAL|getLicenseStatus|DRMInfo|checkLicense)' \
  <source_dir> 2>/dev/null | head -20
```

**For Linux ELF:**

Find exact buffer size and offset for stack overflow:
```bash
# Run in gdb-pwndbg:
# gdb <binary>
# cyclic 300
# r  (enter cyclic string when prompted)
# After crash: cyclic -l <value in $rsp>
```

Find ROP gadgets:
```bash
ROPgadget --binary <file_path> 2>/dev/null | grep -E '(pop rdi|pop rsi|pop rdx|ret$|syscall)' | head -20
```

Find /bin/sh string:
```bash
strings -a -t x <file_path> | grep '/bin/sh'
```

Check for format string vulnerability:
```bash
# In gdb: run with %p.%p.%p.%p as input — if stack addresses appear, it's vulnerable
```

**For .NET / Windows:**

Find all API endpoints:
```bash
grep -rn --include="*.cs" \
  -E '"\/(api|v[0-9]|rest)\/' \
  <source_dir> 2>/dev/null | head -30
```

Find authentication/authorization gaps:
```bash
grep -rn --include="*.cs" \
  -E '(\[AllowAnonymous\]|\[Authorize\]|role.*admin|IsInRole|ClaimsPrincipal)' \
  <source_dir> 2>/dev/null | head -30
```

Find connection strings with credentials:
```bash
grep -rn --include="*.config" --include="*.json" \
  -E 'connectionString|Data Source|Initial Catalog|User Id=|Password=' \
  <source_dir> 2>/dev/null | head -20
```

### Step 7: Read and present all findings

```bash
cat /tmp/re-results/<basename>-poc/findings.md
cat /tmp/re-results/<basename>-poc/exploit-notes.md
```

List all generated PoC scripts:
```bash
ls -la /tmp/re-results/<basename>-poc/poc-* 2>/dev/null
ls -la /tmp/re-results/<basename>-poc/*.html 2>/dev/null
```

For **each** generated PoC script:
1. Read the full script
2. Explain exactly what vulnerability it exploits and why it works
3. Point to the specific code locations in the decompiled source that prove the vulnerability
4. Identify every placeholder that needs actual values and tell the user how to get them
5. Provide the exact commands to run the PoC

### Step 8: Fill in real values from decompiled source

For each PoC placeholder, provide the real value:

**PACKAGE** (Android) — from AndroidManifest.xml:
```bash
grep 'package=' /tmp/re-results/<basename>-decompiled/AndroidManifest.xml | head -1
```

**OFFSET** (buffer overflow) — requires gdb+pwndbg run; provide the exact commands:
```bash
gdb <binary>
(gdb) set disassembly-flavor intel
(pwndbg) cyclic 300
# Enter output when binary prompts
# After crash:
(pwndbg) cyclic -l $rsp
```

**TARGET_URL** (.NET) — from grep of decompiled source:
```bash
grep -rn --include="*.cs" 'BaseAddress\|baseUrl\|apiUrl\|"http' <source_dir> | head -10
```

Update the PoC files with actual values using the Edit tool.

### Step 9: Semgrep SAST (if source available)

If decompiled source exists and semgrep is installed:

```bash
semgrep --config "p/owasp-top-ten" --config "p/secrets" \
  --no-rewrite-rule-ids --text \
  <source_dir> 2>/dev/null | head -100
```

Parse and add any new HIGH/CRITICAL findings to the report.

### Step 10: Final report to user

Present a structured summary:

**Vulnerability Summary:**
- List each finding with: severity | class | location in code | PoC file
- Highlight any CRITICAL findings first
- Note which PoCs are ready to run vs. need values filled in

**Running the PoCs:**
- Provide exact, copy-paste commands for each PoC
- Note prerequisites (frida running, network access, debug build, etc.)

**Limitations:**
- Note any tools that weren't available that would improve the scan
- Note any parts of the code that couldn't be reached (encrypted, obfuscated, native)

Refer to the full vulnerability class reference in `${CLAUDE_PLUGIN_ROOT}/skills/vulnerability-scanner/SKILL.md` for the complete list of vulnerability classes to check.
