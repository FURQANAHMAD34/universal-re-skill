---
allowed-tools: Bash, Read, Glob, Grep, Write, Edit
description: Decompile any binary or app (APK/XAPK/EXE/DLL/ELF/IPA) and generate working PoC scripts for discovered vulnerabilities
user-invocable: true
argument-hint: <path to APK, XAPK, EXE, DLL, ELF, IPA, or source directory>
argument: path to target file or directory (optional)
---

# /decompile

Decompile a binary or application, analyze its structure and security posture, and generate working PoC scripts for any vulnerabilities found.

Supports: Android APK/XAPK/JAR/DEX, Windows PE/DLL/.NET assemblies, Linux ELF binaries, iOS IPA, macOS Mach-O, and source directories.

## Instructions

You are starting the universal reverse engineering and PoC generation workflow. Follow these steps precisely.

### Step 1: Get the target file

If the user provided a file path as an argument, use that. Otherwise ask the user for the path to the file they want to decompile.

Resolve the full absolute path before proceeding.

### Step 2: Auto-detect the target type

Run the detector to understand what we're dealing with:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/detect-target.sh <file_path>
```

Parse `TARGET_TYPE:` and `TARGET_ARCH:` from the output. Map to platform:
- `android-*` → android
- `windows-dotnet` / `dotnet-*` → dotnet
- `windows-pe*` → windows
- `linux-elf*` → linux
- `ios-*` / `macos-*` → ios
- `source-*` → source
- Otherwise → check with `file` command

### Step 3: Check and install required dependencies

Run the dependency check for the detected platform:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/check-deps.sh <platform>
```

Parse the output for `INSTALL_REQUIRED:` and `INSTALL_OPTIONAL:` lines.

**For each required dependency that is missing**, install it:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/install-dep.sh <dep_name>
```

Key dependencies by platform:
- **Android**: `java`, `jadx` (required); `vineflower`, `dex2jar` (recommended)
- **.NET**: `ilspycmd` or `monodis` (required for full decompile)
- **Linux/Windows**: `objdump`, `readelf` (required); `radare2`, `checksec` (recommended)
- **iOS/macOS**: `class-dump` (optional but very useful)

After any installation, verify it worked. If a required tool fails to install (exit code 2), show the manual install instructions to the user and ask whether to continue with partial analysis.

For optional tools, recommend them and ask if the user wants to install them — especially:
- `radare2` for Linux/Windows (function list, xrefs)
- `checksec` for security mitigations (all platforms)
- `frida-tools` (for runtime PoC scripts)

### Step 4: Decompile the target

Run the decompile script. Include `--poc` to also trigger PoC generation at this stage:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/decompile.sh \
  <file_path> \
  --platform <detected_platform> \
  -o /tmp/re-results/<basename>-decompiled \
  --poc
```

Additional flags based on context:
- Obfuscated app (single-letter class names, garbled identifiers): add `--deobf`
- Skip resource decoding for faster analysis: add `--no-res` (Android only)
- Prefer specific engine: `--engine jadx|fernflower|ilspy|r2|both`

Watch the output carefully. Note:
- Total source files decompiled
- Any decompile warnings or errors
- Security-relevant patterns printed during decompile (SSL, network, DllImport, etc.)

### Step 5: Analyze structure and findings

After decompilation, read and analyze the key outputs:

**Android APK:**
1. Read `AndroidManifest.xml` — note permissions, exported components, minSdkVersion
2. List top-level package structure
3. Search for: SSL/TLS patterns, API keys, network endpoints, accessibility services, broadcast receivers

**Windows .NET:**
1. List C# files and namespace structure
2. Search for: SqlCommand, Process.Start, BinaryFormatter, DllImport, hardcoded credentials

**Linux ELF:**
1. Review function list (from radare2 or nm)
2. Check security mitigations (checksec output)
3. Note: dangerous imports (gets, strcpy, system, sprintf), stack canary status, PIE, RELRO

**iOS/macOS:**
1. Review class-dump headers for Objective-C interfaces
2. Check Info.plist for NSAllowsArbitraryLoads
3. Note: encryption status (LC_ENCRYPTION_INFO), rpaths

### Step 6: Read the vulnerability report and PoC scripts

The PoC scripts are in `/tmp/re-results/<basename>-decompiled/poc-scripts/` (or within the output directory).

Read and present the key findings:

```bash
cat /tmp/re-results/<basename>-decompiled/poc-scripts/findings.md
ls -la /tmp/re-results/<basename>-decompiled/poc-scripts/poc-*.py \
        /tmp/re-results/<basename>-decompiled/poc-scripts/poc-*.sh \
        /tmp/re-results/<basename>-decompiled/poc-scripts/poc-*.c 2>/dev/null
```

For each generated PoC script:
1. Read the script
2. Identify what vulnerability it targets and how the exploit works
3. Note which parts need to be updated with actual values (offsets, package name, URL, etc.)
4. Tell the user exactly what they need to fill in

### Step 7: Customize PoCs with actual values

For each PoC where you have the actual information from the decompiled code:

**Android SSL bypass** — update `PACKAGE` in `poc-ssl-bypass.py` with the actual package name from AndroidManifest.xml

**Buffer overflow** — update `OFFSET` in `poc-bof.py` with the cyclic offset found via:
```bash
# In pwndbg:
# cyclic 200 → run → crash → cyclic -l <$rsp value>
```

**SQL injection** — update `TARGET_URL` and `PARAM_NAME` with actual API endpoint found in decompiled source

If you can determine these values directly from the decompile output, fill them in automatically. Show the user a diff of what was updated.

### Step 8: Offer next steps

Tell the user what they can do next:
- **`/vuln_poc <file>`** — Run deeper vulnerability scan with full PoC generation for every vulnerability class
- **Run the SSL bypass**: `frida -U -f <package> -l poc-ssl-bypass.py --no-pause`
- **Run the buffer overflow**: `python3 poc-bof.py LOCAL`
- **Trace call flows**: I can follow execution from any entry point
- **Re-decompile with different engine**: For better output quality

Refer to the full skill documentation in `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/SKILL.md` for the complete workflow.
