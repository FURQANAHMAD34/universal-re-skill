# iOS Reverse Engineering Reference

## File Types

| Format | Description |
|--------|-------------|
| `.ipa` | iOS App Archive (ZIP containing `Payload/<Name>.app/`) |
| `.app` | macOS/iOS application bundle (directory) |
| Mach-O binary | The actual executable inside the `.app` bundle |
| `.dylib` | Dynamic library |
| `.framework` | Framework bundle (directory containing dylib + headers) |

---

## Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `otool` | Load commands, linked libs, disassembly | `xcode-select --install` |
| `nm` | Symbol table (imports/exports) | `xcode-select --install` |
| `lipo` | Fat binary slicing | `xcode-select --install` |
| `codesign` | Signing info + entitlements | `xcode-select --install` |
| `class-dump` | Objective-C class/method headers | `brew install class-dump` |
| `strings` | String extraction | Built-in |
| `ipsw` | IPSW, dyld, DSC analysis | `brew install blacktop/tap/ipsw` |
| Frida | Dynamic instrumentation | `pip install frida-tools` |
| Hopper / IDA Pro | GUI disassembler (commercial) | hopper.nl / hex-rays.com |
| Ghidra | Free NSA RE suite | ghidra-sre.org |

---

## IPA Extraction

```bash
# An IPA is just a ZIP
unzip -qo app.ipa -d app-extracted/
ls app-extracted/Payload/
# Output: AppName.app/

# Find main binary (not a plist or resource)
file app-extracted/Payload/AppName.app/*
# Look for "Mach-O 64-bit ARM64 executable"
```

---

## Architecture

```bash
# Check architecture of binary
file AppName
# Mach-O 64-bit executable arm64         ← device binary
# Mach-O universal binary with 2 architectures: [x86_64:…] [arm64:…]  ← simulator or old universal

# Fat binary: list architectures
lipo -info AppName
# → arm64 x86_64

# Extract a specific slice
lipo AppName -thin arm64 -output AppName-arm64
```

---

## Load Commands and Libraries

```bash
# Mach-O header
otool -h AppName

# Linked libraries (dylibs and frameworks)
otool -L AppName

# All load commands (full dump)
otool -l AppName

# RPATH entries (potential hijack)
otool -l AppName | grep -A3 'LC_RPATH'

# Encryption info (cryptid=1 = still encrypted; =0 = decrypted dump)
otool -l AppName | grep -A5 'LC_ENCRYPTION_INFO'
```

---

## Symbol Table

```bash
# Exported symbols (Swift mangled + ObjC)
nm -gU AppName | head -50

# Undefined (imported) symbols
nm -u AppName | head -50

# Demangle Swift symbols
swift-demangle $(nm -gU AppName | grep '_$s' | awk '{print $3}') 2>/dev/null
# Or: echo '_$s4AppN...' | xcrun swift-demangle
```

---

## Objective-C Analysis

```bash
# Dump all ObjC class headers
class-dump -H AppName -o headers/

# List all classes only
class-dump -f AppName | grep '@interface'

# Find delegate methods
grep -l 'delegate\|Delegate' headers/
```

---

## String Analysis

```bash
# Extract all strings
strings AppName | sort -u > all-strings.txt

# Find URLs
strings AppName | grep -E 'https?://'

# Find API keys and tokens
strings AppName | grep -iE '(api[_-]?key|token|secret|bearer|auth)'

# Find AWS credentials
strings AppName | grep 'AKIA'
```

---

## Entitlements

```bash
# View app entitlements
codesign -d --entitlements :- AppName

# Common entitlements to check:
# com.apple.security.network.client  — allows network connections
# com.apple.security.files.user-selected.read-only  — file access
# keychain-access-groups  — keychain sharing
# get-task-allow  — allows debugger attach (dev builds)
```

---

## Info.plist Security Checks

```bash
# Find Info.plist
find AppName.app -name 'Info.plist' | head -1

# Read it (binary plist → XML on macOS)
plutil -p AppName.app/Info.plist

# Key security flags to check:
# NSAllowsArbitraryLoads: YES  → ATS disabled, cleartext HTTP allowed
# NSExceptionDomains          → per-domain ATS exceptions
# NSPhotoLibraryUsageDescription
# NSCameraUsageDescription
# UIFileSharingEnabled: YES   → files accessible via iTunes
# NSAllowsLocalNetworking: YES → allows cleartext on local network
```

---

## Disassembly

```bash
# Disassemble text section
otool -tV AppName | head -100

# Disassemble specific function (grep by address)
otool -tV AppName | grep -A20 '<_functionName>'

# With radare2 (better output)
r2 -A AppName
# In r2: afl (list functions), pd 50 (print 50 instructions), pdf @sym.name
```

---

## Dynamic Analysis (Runtime)

```bash
# Frida: list processes (requires jailbroken device or Frida server)
frida-ps -U

# Hook all ObjC methods
frida-trace -U -f com.example.App -m '*[* *]'

# Hook specific method
frida-trace -U -f com.example.App -m '-[LoginVC loginButtonPressed:]'

# Python script with Frida
python3 frida_hook.py
```

---

## Common Findings

| Finding | Where to Look |
|---------|---------------|
| Hardcoded API endpoint | `strings` output, ObjC constants |
| Auth token in binary | `strings \| grep -i token` |
| SSL pinning | `nm` for `SecTrustEvaluate`, `TrustKit`, `AFNetworking` |
| Jailbreak detection | `strings \| grep -iE 'cydia\|substrate\|jailbreak\|unc0ver'` |
| HTTP (not HTTPS) | `strings \| grep 'http://'` |
| Debug flag | `get-task-allow = YES` in entitlements |
| Insecure keychain | `kSecAttrAccessibleAlways` in nm symbols |
| Cleartext log | `NSLog\|print\|debugPrint` in class-dump output |
