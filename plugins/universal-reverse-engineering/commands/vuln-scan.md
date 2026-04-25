---
allowed-tools: Bash, Read, Glob, Grep, Write, Edit
description: >
  Scan a binary or source directory for vulnerabilities: buffer overflows, heap
  corruption, format strings, integer overflows, use-after-free, command injection,
  SQL injection, insecure crypto, hardcoded secrets, deserialization flaws, and 30+
  more vulnerability classes across C/C++, Python, Java, JavaScript, Go, .NET,
  and compiled ELF/PE/Mach-O binaries.
user-invocable: true
argument-hint: <path to binary or source directory>
argument: target file or directory (optional)
---

# /vuln-scan

Vulnerability detection across source code and compiled binaries.

## Instructions

### Step 1: Get the Target

If the user provided a target, use it. Otherwise ask:
> "What do you want to scan? Provide a source directory or a compiled binary (ELF/EXE/Mach-O/APK)."

### Step 2: Install Required Tools (ask user for optional ones)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/check-deps.sh vuln
```

Required: `semgrep`, `flawfinder`, `bandit`, or `cppcheck` depending on target language.
Optional but highly recommended: `gitleaks`, `trufflehog`, `checksec`.

For each `INSTALL_REQUIRED:<dep>`:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/install-dep.sh <dep>
```

### Step 3: Run Vulnerability Scan

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/vulnerability-scanner/scripts/vuln-scan.sh <target> -o <target>-vuln-report
```

For a quick scan (pattern-only, no external tools):
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/vulnerability-scanner/scripts/vuln-scan.sh <target> -o <report> --level quick
```

For binary security check only:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/vulnerability-scanner/scripts/check-binary-security.sh <binary>
```

For source only:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/vulnerability-scanner/scripts/scan-source.sh <source-dir> -o <report>
```

### Step 4: Read and Triage Findings

Read `<report>/findings.md` and triage results by severity:

1. **CRITICAL** — hardcoded private keys, credentials with real values, no-NX + stack overflow
2. **HIGH** — dangerous functions with user input, command injection, SQL injection, format strings
3. **MEDIUM** — weak crypto, insecure deserialization patterns, missing binary hardening
4. **LOW** — informational patterns, potential issues needing manual review

### Step 5: For Each HIGH/CRITICAL Finding

Read the source code or decompiled output at the reported location and:
- Confirm whether user input actually reaches the vulnerable call
- Identify the call chain from entry point to the vulnerability
- Assess exploitability (ASLR/NX/canary status, input constraints)
- Write a finding in this format:

```markdown
### [SEVERITY] <Title>

- **Type**: <vulnerability class>
- **Location**: `<file>:<line>` or `<binary>:<offset>`
- **Evidence**: `<code snippet>`
- **Impact**: <what an attacker can do>
- **Recommendation**: <fix>
```

### Step 6: Offer Follow-Ups

- "I can produce a full structured report with all findings"
- "I can trace how user input reaches this vulnerable call"
- "I can check if this binary has ASLR/NX/canary protections"
- "I can search for a specific vulnerability type: `/vuln-scan --type bufferoverflow`"

Refer to `${CLAUDE_PLUGIN_ROOT}/skills/vulnerability-scanner/SKILL.md` for
complete vulnerability class documentation and manual review patterns.
