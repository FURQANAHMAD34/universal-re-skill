# Windows PE Reverse Engineering Reference

## PE File Types

| Extension | Type |
|-----------|------|
| `.exe` | Executable (PE32 or PE32+) |
| `.dll` | Dynamic Link Library |
| `.sys` | Kernel driver |
| `.ocx` | ActiveX control |
| `.cpl` | Control Panel applet |
| `.scr` | Screensaver (executable) |
| `.mui` | Multilingual User Interface resource |

---

## Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `objdump` | PE headers, imports, disassembly | `apt install binutils` / `brew install binutils` |
| `strings` | String extraction | `apt install binutils` |
| `upx` | Detect/unpack UPX | `apt install upx` |
| `file` | Detect PE type | Built-in |
| `capa` | Malware capability detection | GitHub: mandiant/capa |
| `checksec` | Security mitigation check | `pip install checksec` |
| `pefile` (Python) | PE parsing | `pip install pefile` |
| `pe-bear` | GUI PE viewer | GitHub: hasherezade/pe-bear |
| `x64dbg` | GUI debugger (Windows) | x64dbg.com |
| `Ghidra` | Free decompiler / RE suite | ghidra-sre.org |
| `IDA Pro` | Industry-standard disassembler | hex-rays.com |
| `dnSpy` | .NET decompiler | GitHub: dnSpy/dnSpy |
| `radare2` | CLI RE framework | `apt install radare2` |

---

## Identify the PE

```bash
# File type and basic info
file target.exe
# → target.exe: PE32+ executable (console) x86-64, for MS Windows

# Detailed headers
objdump -f target.exe

# Full header dump
objdump -p target.exe | head -60
```

---

## Packing Detection

Many malware samples and protected binaries are packed (UPX, MPRESS, Themida, etc.).

```bash
# UPX check
upx -t target.exe
# "testing target.exe [OK]" = UPX packed

# Strings-based packer hints
strings target.exe | grep -iE '^(UPX|MPRESS|Themida|VMProtect|PECompact|ASPack|ExeCryptor)'

# Entropy (high entropy = packed/encrypted sections)
# Use python with pefile:
python3 -c "
import pefile, math, collections
pe = pefile.PE('target.exe')
for s in pe.sections:
    data = s.get_data()
    count = collections.Counter(data)
    entropy = -sum((c/len(data))*math.log2(c/len(data)) for c in count.values() if c)
    print(f'{s.Name.decode().strip(chr(0)):12s} entropy={entropy:.2f}')
"
# entropy > 7.0 in .text section usually means packed
```

---

## Import Table (DLL Dependencies)

```bash
# List all imported DLLs and functions
objdump -p target.exe | grep -A999 'DLL Name'

# Just DLL names
objdump -p target.exe | grep 'DLL Name'

# Python pefile alternative (cleaner output)
python3 -c "
import pefile
pe = pefile.PE('target.exe')
for entry in pe.DIRECTORY_ENTRY_IMPORT:
    print(f'  {entry.dll.decode()}')
    for imp in entry.imports[:5]:
        print(f'    {imp.name}')
"
```

---

## Export Table (for DLLs)

```bash
# List exports
objdump -x target.dll | grep -A999 '^Export'

# Python pefile
python3 -c "
import pefile
pe = pefile.PE('target.dll')
if hasattr(pe, 'DIRECTORY_ENTRY_EXPORT'):
    for exp in pe.DIRECTORY_ENTRY_EXPORT.symbols:
        print(f'  {exp.name} @ {hex(pe.OPTIONAL_HEADER.ImageBase + exp.address)}')
"
```

---

## Security Mitigations

```bash
# Using checksec
checksec --file=target.exe

# Manual via objdump
objdump -p target.exe | grep DllCharacteristics
# Decode the flags manually:
#   0x0020 = HIGH_ENTROPY_VA (64-bit ASLR)
#   0x0040 = DYNAMIC_BASE (ASLR enabled)
#   0x0100 = NX_COMPAT (DEP enabled)
#   0x0400 = NO_SEH (SafeSEH not used)
#   0x4000 = GUARD_CF (Control Flow Guard)
```

| Flag | Hex | Meaning |
|------|-----|---------|
| ASLR | 0x40 | Randomize load address |
| DEP/NX | 0x100 | Non-executable stack/heap |
| High Entropy VA | 0x20 | 64-bit full ASLR |
| CFG | 0x4000 | Control Flow Guard |
| SafeSEH | PE header | SEH integrity check |

---

## Suspicious Imports (Red Flags)

Look for these in the import table:

```
VirtualAlloc / VirtualAllocEx     — shellcode injection
WriteProcessMemory                — process injection
CreateRemoteThread                — remote thread injection
OpenProcess                       — process access (PROCESS_ALL_ACCESS)
LoadLibrary / GetProcAddress      — dynamic loading (often in packers)
InternetOpen / HttpOpenRequest    — network communication
URLDownloadToFile                 — download malware
ShellExecute / WinExec / CreateProcess — command execution
RegOpenKey / RegSetValue          — registry manipulation
CryptEncrypt / CryptDecrypt       — crypto (may hide data)
NtQueryInformationProcess         — anti-debugging check
IsDebuggerPresent / CheckRemoteDebugger — anti-debugging
```

---

## Disassembly

```bash
# Disassemble the entire binary
objdump -d target.exe > disasm.asm

# Disassemble just the .text section
objdump -d --section=.text target.exe | head -200

# Intel syntax (easier to read)
objdump -d -M intel target.exe | head -200

# With radare2
r2 -A target.exe
# Commands: afl (list funcs), s main (seek to main), pdf (print disasm of func)
```

---

## Interesting Strings

```bash
# All strings ≥6 chars
strings -a -n 6 target.exe > strings.txt

# URLs and IPs
grep -E 'https?://|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' strings.txt

# Passwords / secrets
grep -iE '(password|passwd|secret|api[_-]?key|token|auth)' strings.txt

# Registry paths
grep -E 'HKEY_|HKLM\\|HKCU\\' strings.txt

# File paths
grep -E '(C:\\|\\System32\\|\\Temp\\|\.exe|\.dll|\.bat)' strings.txt

# Base64 blobs (potential encoded payloads)
grep -E '^[A-Za-z0-9+/]{20,}={0,2}$' strings.txt | head -20
```

---

## .NET Detection

```bash
file target.exe
# → "Mono/.Net assembly" or "PE32 executable ... Mono/.Net"

# If .NET, use ilspycmd or dnSpy
ilspycmd -p -o decompiled/ target.exe

# Or check for .NET magic bytes
python3 -c "
import pefile
pe = pefile.PE('target.exe')
# .NET assemblies have a CLR header in directory index 14
if pe.OPTIONAL_HEADER.DATA_DIRECTORY[14].VirtualAddress != 0:
    print('This is a .NET assembly')
"
```

---

## Common Malware Patterns

| Pattern | Indicator |
|---------|-----------|
| Process injection | VirtualAllocEx + WriteProcessMemory + CreateRemoteThread |
| Persistence | RegSetValue with `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
| Keylogging | SetWindowsHookEx + WH_KEYBOARD |
| Screenshot | BitBlt + GetDC |
| Crypto ransomware | CryptEncrypt or AES patterns + file enumeration |
| C2 communication | InternetConnect + HttpSendRequest to unusual IPs |
| Anti-debug | IsDebuggerPresent + NtQueryInformationProcess |
| Self-deletion | MoveFileEx with MOVEFILE_DELAY_UNTIL_REBOOT |
