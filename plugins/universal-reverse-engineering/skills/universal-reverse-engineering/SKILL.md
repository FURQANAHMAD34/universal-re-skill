---
description: >
  Universal reverse engineering skill for Android (APK/XAPK/JAR/AAR), iOS (IPA/dylib),
  Windows (PE/EXE/DLL/SYS), Linux (ELF/SO), macOS (Mach-O/dylib/framework), and
  .NET assemblies. Auto-detects the target format, selects the right toolchain, and
  produces structured analysis: architecture, strings, imports/exports, disassembly,
  decompiled source, and call-flow documentation. Also detects 40+ vulnerability classes
  in both source code and compiled binaries.
trigger: >
  reverse engineer|decompile|disassemble|analyze binary|analyze APK|analyze IPA|
  analyze EXE|analyze DLL|analyze ELF|analyze PE|analyze Mach-O|analyze .NET|
  analyze dylib|analyze SO|find vulnerabilities|scan for vulns|buffer overflow|
  heap overflow|format string|stack overflow|use-after-free|vuln scan|
  binary analysis|extract strings|find API endpoints|call flow|
  RE android|RE ios|RE windows|RE linux|RE macos|checksec
---

# Universal Reverse Engineering & Vulnerability Detection

This skill handles reverse engineering and vulnerability analysis for every major binary
and source format. It auto-detects the target type and routes to the correct toolchain.

## Supported Targets

| Platform | Formats | Primary Tools |
|----------|---------|---------------|
| Android | APK, XAPK, JAR, AAR, DEX | jadx, apktool, dex2jar |
| iOS | IPA, dylib, framework | class-dump, otool, nm, ipsw |
| Windows | EXE, DLL, SYS, OCX (PE32/PE64) | pe-analyzer, strings, objdump, capa |
| Linux | ELF (x86/x86_64/ARM/MIPS) | readelf, objdump, nm, strings, ltrace |
| macOS | Mach-O, dylib, framework, .app | otool, nm, codesign, strings |
| .NET | EXE, DLL, nupkg | ilspycmd, monodis |
| Generic | Any binary | binwalk, file, strings, radare2 |
| Source | C/C++, Python, Java, JS, Go, Rust | semgrep, cppcheck, bandit, flawfinder |

---

## Phase 0: Auto-Detect Target

Before choosing a toolchain, identify what the target actually is.

**Action**: Run the detect script.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/detect-target.sh <file>
```

The script outputs a machine-readable type line:
- `TARGET_TYPE:android-apk`
- `TARGET_TYPE:android-xapk`
- `TARGET_TYPE:android-jar`
- `TARGET_TYPE:ios-ipa`
- `TARGET_TYPE:ios-macho` (single Mach-O binary from IPA or standalone)
- `TARGET_TYPE:windows-pe32`
- `TARGET_TYPE:windows-pe64`
- `TARGET_TYPE:windows-dotnet`
- `TARGET_TYPE:linux-elf`
- `TARGET_TYPE:macos-macho`
- `TARGET_TYPE:dotnet-assembly`
- `TARGET_TYPE:source-c`
- `TARGET_TYPE:source-python`
- `TARGET_TYPE:source-java`
- `TARGET_TYPE:source-javascript`
- `TARGET_TYPE:unknown`

Route to the appropriate section below based on this output.

---

## Phase 1: Verify and Install Dependencies

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/check-deps.sh [platform]
```

Platform options: `android`, `ios`, `windows`, `linux`, `macos`, `dotnet`, `all`.

Machine-readable output:
- `INSTALL_REQUIRED:<dep>` — must install before proceeding
- `INSTALL_OPTIONAL:<dep>` — improves results but not blocking

Install missing deps:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/install-dep.sh <dep>
```

---

## Phase 2: Platform-Specific Analysis

### Android (APK / XAPK / JAR / AAR / DEX)

Full workflow in `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/android.md`.

**Quick start:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh android <file> -o <output-dir>
```

Steps:
1. Decompile with jadx (`--deobf` for obfuscated apps)
2. Read AndroidManifest.xml — Activities, permissions, exported components
3. Map package structure and architecture pattern (MVP/MVVM/Clean)
4. Trace: Activity → ViewModel → Repository → API service
5. Run `find-api-calls.sh` to sweep for Retrofit, OkHttp, Volley, hardcoded URLs, auth tokens

---

### iOS (IPA / dylib / framework)

Full workflow in `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/ios.md`.

**Quick start:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh ios <file> -o <output-dir>
```

Steps:
1. Extract IPA (it's a ZIP) → `Payload/<AppName>.app/`
2. Find the main Mach-O binary inside the `.app` bundle
3. Run `file` and `otool -h` to determine arch (arm64, x86_64, universal)
4. Dump Objective-C class structure: `class-dump -H <binary> -o <headers-dir>`
5. List all linked frameworks and dylibs: `otool -L <binary>`
6. Extract Swift types: `nm -gU <binary> | grep -i swift`
7. Find hardcoded strings: `strings <binary> | grep -E '(https?://|api[_-]?key|token|secret)'`
8. Check entitlements: `codesign -d --entitlements :- <binary>`
9. If Ghidra available: auto-analyze and export function list

---

### Windows PE (EXE / DLL / SYS)

Full workflow in `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/windows-pe.md`.

**Quick start:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh windows <file> -o <output-dir>
```

Steps:
1. Identify PE type: `file <binary>` and `objdump -f <binary>`
2. Check for packing: `strings <binary> | grep -iE '(upx|packed|stub)'` + entropy check
3. List imports (DLL dependencies): `objdump -p <binary> | grep -A999 'DLL Name'`
4. List exports (for DLLs): `objdump -x <binary> | grep -A999 '^Export'`
5. Extract all strings: `strings -a -n 6 <binary>`
6. For .NET binaries → route to .NET workflow
7. Check binary hardening: checksec or manual PE header inspection (ASLR, DEP, SafeSEH, CFG)
8. If radare2 available: `r2 -A -q -c 'afl' <binary>` for function list

---

### Linux ELF

Full workflow in `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/linux-elf.md`.

**Quick start:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh linux <file> -o <output-dir>
```

Steps:
1. `file <binary>` — confirm ELF, arch, linking type (static/dynamic), stripped status
2. `readelf -h <binary>` — entry point, machine type, flags
3. `readelf -S <binary>` — section layout (`.text`, `.data`, `.bss`, `.plt`, `.got`)
4. `readelf -d <binary>` — dynamic dependencies (shared libraries)
5. `nm -D <binary>` — dynamic symbol table (imports/exports)
6. `objdump -d <binary> | head -200` — disassemble entry + first functions
7. `strings -a -n 6 <binary>` — extract printable strings
8. Check security mitigations: `checksec --file=<binary>` (canary, NX, PIE, RELRO, FORTIFY)
9. `ltrace`/`strace` hooks (note: requires execution — mention to user)

---

### macOS Mach-O

Full workflow in `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/macos-macho.md`.

**Quick start:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh macos <file> -o <output-dir>
```

Steps:
1. `file <binary>` — confirm Mach-O, arch(es), type (executable/dylib/bundle)
2. `otool -h <binary>` — magic, CPU type, file type
3. `otool -L <binary>` — linked libraries
4. `otool -l <binary> | grep -A3 LC_RPATH` — rpath entries (for hijacking analysis)
5. `nm -gU <binary>` — exported symbols
6. `otool -tV <binary>` — disassemble text section
7. `strings <binary>` — hardcoded strings
8. `codesign -dvv <binary>` — signing info, entitlements
9. For fat binaries: `lipo -info <binary>` then extract arch of interest

---

### .NET Assemblies (EXE / DLL / nupkg)

Full workflow in `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/dotnet.md`.

**Quick start:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh dotnet <file> -o <output-dir>
```

Steps:
1. Confirm it's a .NET assembly: `file <binary>` shows "Mono/.Net assembly"
2. Decompile with ilspycmd: `ilspycmd -p -o <output-dir> <assembly.dll>`
3. List namespaces and types: `monodis --typedef <binary>` (if Mono available)
4. Find references to interesting .NET APIs: grep decompiled source for
   - `System.Net`, `HttpClient`, `WebRequest` — network
   - `SqlCommand`, `OleDbCommand` — database (SQL injection risk)
   - `Process.Start`, `Shell`, `cmd.exe` — command execution
   - `Environment.GetEnvironmentVariable`, `AppSettings` — config
   - `DllImport`, `Marshal` — P/Invoke (native interop, potential memory issues)
5. Check for obfuscation (ConfuserEx, Dotfuscator): scrambled names, junk methods
6. For NuGet packages: extract .nupkg (ZIP) and analyze each DLL

---

## Phase 3: Vulnerability Analysis

See `${CLAUDE_PLUGIN_ROOT}/skills/vulnerability-scanner/SKILL.md` for the full
vulnerability detection workflow.

**Quick vulnerability scan:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/scripts/analyze.sh vuln <target> -o <output-dir>
```

Covers:
- Binary: no-canary, no-NX, no-PIE, no-RELRO, dangerous functions, format strings
- Source C/C++: buffer overflows, format string bugs, integer overflows, unsafe functions
- Source Python: command injection, path traversal, pickle/yaml deserialization
- Source Java/.NET: SQL injection, XXE, insecure deserialization, command injection
- All: hardcoded secrets/API keys, weak crypto, cleartext HTTP

---

## Phase 4: Output and Documentation

For each analysis, produce:

1. **Target summary** — file type, architecture, platform, size, hash (MD5/SHA256)
2. **Structure map** — sections/segments, imports, exports, classes, namespaces
3. **Strings of interest** — URLs, IPs, credentials, keys, error messages
4. **Security posture** — enabled/disabled mitigations
5. **Findings** — vulnerabilities, suspicious patterns, hardcoded secrets
6. **Call flow** — (when traceable) entry points → interesting functions
7. **Recommendations** — prioritized list of issues to investigate further

Use this output template for each finding:

```markdown
### [SEVERITY] Finding: <short title>

- **Type**: buffer-overflow | format-string | hardcoded-secret | ...
- **Location**: <file>:<line> or <binary>:<offset/function>
- **Evidence**: `<code snippet or disassembly>`
- **Impact**: <what an attacker can do>
- **Recommendation**: <fix or mitigation>
```

Severity levels: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO`

---

## References

- `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/setup-guide.md` — Install all tools
- `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/android.md` — Android deep-dive
- `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/ios.md` — iOS deep-dive
- `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/windows-pe.md` — Windows PE deep-dive
- `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/linux-elf.md` — Linux ELF deep-dive
- `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/macos-macho.md` — macOS Mach-O deep-dive
- `${CLAUDE_PLUGIN_ROOT}/skills/universal-reverse-engineering/references/dotnet.md` — .NET deep-dive
- `${CLAUDE_PLUGIN_ROOT}/skills/vulnerability-scanner/SKILL.md` — Vulnerability detection workflows
