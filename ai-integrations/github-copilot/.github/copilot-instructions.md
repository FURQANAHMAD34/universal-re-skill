# GitHub Copilot Custom Instructions — Universal RE & Vuln Detection

When assisting with reverse engineering or security analysis tasks, follow these
workflows. These instructions apply workspace-wide.

## Reverse Engineering Workflows

### Android (APK/XAPK/JAR/AAR)
- Use `jadx -d output/ --show-bad-code --deobf target.apk` for decompilation
- Parse `AndroidManifest.xml` for exported components, permissions, debuggable flag
- Search for Retrofit endpoints: `grep -rn '@GET\|@POST\|@PUT\|@DELETE' sources/`
- Check for hardcoded URLs, tokens, API keys in decompiled Java/Kotlin source

### iOS (IPA / Mach-O)
- Unzip IPA: `unzip app.ipa -d extracted/` → find binary in `Payload/*.app/`
- List libraries: `otool -L binary`
- Dump Objective-C headers: `class-dump -H binary -o headers/`
- Check entitlements: `codesign -d --entitlements :- binary`
- Find strings: `strings binary | grep -E 'https?://|api|token|key'`

### Windows PE (EXE/DLL)
- Headers: `objdump -p target.exe`
- Imports: `objdump -p target.exe | grep -A999 'DLL Name'`
- Packing: `upx -t target.exe` + check for high entropy sections
- Security: `checksec --file=target.exe` (ASLR, DEP, CFG, SafeSEH)

### Linux ELF
- `readelf -h target` (type, arch, entry point)
- `readelf -S target` (sections)
- `nm -D target | grep ' U '` (imported symbols)
- `checksec --file=target` (canary, NX, PIE, RELRO, FORTIFY)
- `objdump -d -M intel target | head -200` (disassembly)

### macOS Mach-O
- `otool -h target` (header), `otool -L target` (libraries)
- `lipo -info target` (fat binary arches)
- `codesign -dvv target` (signing info)
- `nm -gU target` (exported symbols)

### .NET Assembly
- `ilspycmd -p -o decompiled/ target.dll`
- Grep for: `BinaryFormatter`, `SqlCommand`, `Process.Start`, `TypeNameHandling`

## Vulnerability Patterns to Always Flag

- **Buffer overflow**: `gets()`, `strcpy()`, `sprintf()` without bounds
- **Format string**: `printf(user_var)` — single argument, no format string
- **Heap overflow**: `malloc(size * n)` without checking for integer overflow
- **UAF**: `free(ptr)` followed by use of `ptr`
- **Command injection**: `system()`, `exec()`, `os.system()`, `subprocess(shell=True)`
- **SQL injection**: string concatenation into SQL queries
- **Insecure deserialization**: `pickle.load`, `ObjectInputStream`, `BinaryFormatter`
- **Hardcoded secrets**: `password =`, `api_key =`, `-----BEGIN PRIVATE KEY-----`
- **Weak crypto**: MD5, SHA1, DES, RC4, ECB mode, hardcoded IV, `Math.random()`
- **No binary hardening**: missing NX, no PIE, no stack canary (checked via checksec)

## Code Generation Rules

When generating analysis scripts:
- Always use `set -euo pipefail` in bash scripts
- Quote all file path variables
- Use `realpath` for absolute paths
- Include fallbacks when tools are absent
- Output machine-readable markers like `FINDING:HIGH:...` for parsing
