---
allowed-tools: Bash, Read, Glob, Grep, Write, Edit
description: >
  Reverse engineer any binary or source target — Android APK/XAPK, iOS IPA,
  Windows EXE/DLL, Linux ELF, macOS Mach-O, .NET assembly, or source directory.
  Auto-detects file type and runs the appropriate toolchain.
user-invocable: true
argument-hint: <path to binary, APK, IPA, EXE, ELF, Mach-O, .NET assembly, or source dir>
argument: target file or directory (optional)
---

# /analyze

Universal reverse engineering analysis of any binary or source target.

## Instructions

### Step 1: Get the Target

If the user provided a path, use it. Otherwise ask:
> "What file or directory do you want to analyze? (APK, IPA, EXE, DLL, ELF, Mach-O, .NET, or source directory)"

### Step 2: Check Dependencies

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/check-deps.sh all
```

Parse `INSTALL_REQUIRED:<dep>` lines. For each required missing dep:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/install-dep.sh <dep>
```

For optional deps, ask the user if they want to install for better results.

### Step 3: Auto-Detect Target Type

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/detect-target.sh <target>
```

Parse the `TARGET_TYPE:` and `TARGET_ARCH:` lines and tell the user what was detected.

### Step 4: Run Analysis

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh auto <target> -o <target>-analysis
```

For deep analysis (radare2/Ghidra):
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh auto <target> -o <target>-analysis --deep
```

To include vulnerability scanning in the same pass:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh auto <target> -o <target>-analysis --vuln
```

### Step 5: Read and Summarize

After the script completes, read `<output-dir>/analyze.log` and produce a
structured summary:

1. **Target** — file type, architecture, size, hash
2. **Structure** — key sections/packages/classes found
3. **Strings of interest** — URLs, credentials, keys, suspicious paths
4. **Security posture** — which mitigations are on/off
5. **Next steps** — what to investigate further

### Step 6: Offer Follow-Ups

Tell the user:
- "I can run a full vulnerability scan — `/vuln-scan`"
- "I can trace specific function call flows"
- "I can search for specific strings or patterns"
- "I can decompile specific classes/functions in detail"

Refer to `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/SKILL.md`
for the platform-specific deep-dive workflows.
