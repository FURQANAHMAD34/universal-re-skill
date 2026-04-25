# macOS Mach-O Reverse Engineering Reference

## File Types

| Type | Magic / Description |
|------|---------------------|
| Mach-O executable | `MH_EXECUTE` — standard app binary |
| Mach-O dylib | `MH_DYLIB` — dynamic library (`.dylib`) |
| Mach-O bundle | `MH_BUNDLE` — loadable plugin (`.so`, `.bundle`) |
| Mach-O KEXT | Kernel extension |
| Universal / fat binary | Multiple arch slices in one file |
| `.app` bundle | Directory containing binary + resources |
| `.framework` | Directory with versioned dylib + headers |

---

## Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `otool` | Headers, load cmds, disassembly | Xcode CLI Tools |
| `nm` | Symbol table | Xcode CLI Tools |
| `lipo` | Fat binary slice management | Xcode CLI Tools |
| `codesign` | Signature + entitlements | Xcode CLI Tools |
| `dyldinfo` | Dyld binding info | Xcode CLI Tools |
| `vtool` | Mach-O platform/min-version info | Xcode CLI Tools |
| `strings` | String extraction | Built-in |
| `class-dump` | ObjC class headers | `brew install class-dump` |
| `Hopper` | GUI disassembler/decompiler (paid) | hopperapp.com |
| `IDA Pro` | Industry standard (paid) | hex-rays.com |
| `Ghidra` | Free NSA RE suite | ghidra-sre.org |
| `radare2` | CLI RE framework | `brew install radare2` |
| `Frida` | Dynamic instrumentation | `pip install frida-tools` |

---

## Quick Identification

```bash
file target
# Mach-O 64-bit executable arm64
# Mach-O universal binary with 2 architectures: [x86_64:...] [arm64:...]

# Mach-O header fields
otool -h target
# magic: 0xfeedfacf (64-bit) or 0xfeedface (32-bit) or 0xcafebabe (fat)
# cputype, cpusubtype, filetype (MH_EXECUTE=2, MH_DYLIB=6, MH_BUNDLE=8)
# flags: MH_PIE (0x200000), MH_ALLOW_STACK_EXECUTION, etc.

# For fat binaries
lipo -info target
# → Architectures in the fat file: target are: x86_64 arm64
```

---

## Fat Binaries

```bash
# List architectures
lipo -info target

# Extract specific slice
lipo target -thin arm64 -output target-arm64
lipo target -thin x86_64 -output target-x86_64

# Remove an architecture
lipo target -remove i386 -output target-no-i386
```

---

## Load Commands

```bash
# Full load command dump (very verbose)
otool -l target

# Just load command names
otool -l target | grep 'cmd LC_'

# Key load commands:
# LC_SEGMENT_64       → memory segments (__TEXT, __DATA, __LINKEDIT)
# LC_DYLIB_ID         → this library's install name (dylibs only)
# LC_LOAD_DYLIB       → linked libraries
# LC_RPATH            → rpath search directories
# LC_CODE_SIGNATURE   → code signature offset
# LC_ENCRYPTION_INFO  → App Store encryption
# LC_MAIN             → entry point
# LC_UUID             → binary UUID (matches dSYM)
# LC_SOURCE_VERSION   → source version tag
```

---

## Linked Libraries

```bash
# All linked dylibs and frameworks
otool -L target
# Format: install_name (compatibility version X, current version Y)

# Look for weak-linked libs (optional deps)
otool -l target | grep -B2 'LC_LOAD_WEAK_DYLIB'
```

---

## RPATH (Potential Hijacking)

```bash
# List all rpaths
otool -l target | grep -A3 'LC_RPATH' | grep 'path'

# @executable_path = relative to the executable
# @loader_path     = relative to the loading library
# @rpath           = resolved via LC_RPATH list

# Attack surface: if @rpath contains writable dirs before system paths,
# a malicious dylib placed there will load instead of the real one.
```

---

## Symbol Table

```bash
# Exported symbols
nm -gU target | head -40

# All symbols (non-stripped)
nm target | head -40

# Undefined / imported
nm -u target

# Swift: demangle symbols
nm -gU target | grep '_$s' | while read -r line; do
  sym=$(echo "$line" | awk '{print $3}')
  echo "$line → $(xcrun swift-demangle "$sym" 2>/dev/null || echo "$sym")"
done | head -30
```

---

## Disassembly

```bash
# Disassemble __TEXT,__text section
otool -tV target | head -100

# Specific function (grep)
otool -tV target | grep -A30 '<main>'

# With radare2
r2 -A target
# afl     → list functions
# s main  → seek to main
# pdf     → print disassembly of function
# axt sym.imp.objc_msgSend → callers of objc_msgSend
```

---

## Objective-C Analysis

```bash
# Dump all classes and methods as headers
class-dump -H target -o headers/
ls headers/
# → NSObject.h, AppDelegate.h, etc.

# ObjC method list from objdump
otool -ov target | grep -E 'method_name|name 0x' | head -40

# Find selector strings
strings target | grep -E '^[a-z][a-zA-Z]+:' | head -30
```

---

## Swift Analysis

```bash
# Swift types via nm + demangle
nm -gU target | grep '_$s' | xcrun swift-demangle 2>/dev/null | head -40

# Swift reflection metadata
strings target | grep 'reflect/Metadata\|$S\|$s' | head -20

# ipsw (for dyld shared cache analysis)
ipsw macho info target
ipsw macho disass target --symbol main
```

---

## Code Signing & Entitlements

```bash
# Signing info
codesign -dvv target

# Entitlements (plist format)
codesign -d --entitlements :- target

# Verify signature
codesign -v target && echo "Signature valid" || echo "Signature INVALID"

# Key entitlements for security:
# com.apple.security.network.client     — outbound network
# com.apple.security.network.server     — listen on socket
# com.apple.security.files.*            — file access sandbox
# com.apple.security.cs.allow-jit       — JIT execution
# com.apple.security.cs.disable-library-validation — load unsigned dylibs
# com.apple.security.automation.apple-events       — Apple Events
```

---

## PIE / ASLR Check

```bash
# Check MH_PIE flag
otool -h target | grep flags
python3 -c "
flags_hex = '0x00200085'  # replace with actual flags from otool -h
flags = int(flags_hex, 16)
print('PIE:', bool(flags & 0x200000))
print('Allow stack exec:', bool(flags & 0x20000))
print('No heap exec:', bool(flags & 0x01000000))
"

# Easy way
checksec --file=target   # if installed
```

---

## Interesting Strings

```bash
strings target | grep -E 'https?://'             # URLs
strings target | grep -iE '(api[_-]?key|token|secret|password|bearer)'
strings target | grep 'BEGIN.*PRIVATE KEY'        # private keys
strings target | grep 'AKIA'                      # AWS access key
strings target | grep -iE '(cydia|substrate|jailbreak)'  # jailbreak detection

# Find format string candidates (ObjC)
strings target | grep -E '^%[0-9@sdlf]'
```

---

## Dynamic Analysis

```bash
# Frida: hook all ObjC methods
frida-trace -f com.example.App -m '*[* *]' 2>/dev/null | head -50

# Frida: intercept specific method
frida-trace -f com.example.App -m '-[NetworkManager sendRequest:]'

# DYLD_INSERT_LIBRARIES for dylib injection (unsigned)
# On non-SIP targets only:
DYLD_INSERT_LIBRARIES=hook.dylib ./target

# lldb attach
lldb target
# (lldb) b -n main
# (lldb) run
```

---

## Common Findings

| Finding | Command |
|---------|---------|
| Unencrypted network calls | `otool -L` + grep for NSURLConnection/NSURLSession |
| Hardcoded API key | `strings target \| grep -iE 'api.?key'` |
| Jailbreak bypass needed | `strings target \| grep cydia` |
| Rpath hijack possible | `otool -l target \| grep -A3 LC_RPATH` |
| App loads unsigned dylibs | `codesign -d --entitlements :- target \| grep disable-library-validation` |
| Weak linked exploitable | `otool -l target \| grep WEAK_DYLIB` |
