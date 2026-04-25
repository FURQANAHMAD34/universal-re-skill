# Setup Guide: All Dependencies

Quick-install any dep: `bash scripts/install-dep.sh <name>`
Check what's missing: `bash scripts/check-deps.sh all`

---

## Universal (Required on all platforms)

| Tool | Purpose | Install |
|------|---------|---------|
| `file` | File type detection | Built-in on Linux/macOS |
| `strings` | String extraction | `install-dep.sh strings-bin` |
| `grep` | Pattern search | Built-in |
| `unzip` | Archive extraction | `install-dep.sh unzip` |
| `xxd` | Hex dump | `install-dep.sh xxd` |

---

## Android

| Tool | Required | Install |
|------|---------|---------|
| Java JDK 17+ | Yes | `install-dep.sh java` |
| jadx | Yes | `install-dep.sh jadx` |
| apktool | Optional | `install-dep.sh apktool` |
| dex2jar | Optional | `install-dep.sh dex2jar` |
| Vineflower | Optional | `install-dep.sh vineflower` |
| adb | Optional | `install-dep.sh adb` |

---

## iOS / macOS

| Tool | Required | Install |
|------|---------|---------|
| otool | Yes | `install-dep.sh xcode-cli` (macOS) |
| nm | Yes | `install-dep.sh nm` |
| class-dump | Optional | `install-dep.sh class-dump` |
| codesign | Optional | `install-dep.sh xcode-cli` |
| lipo | Optional | `install-dep.sh xcode-cli` |
| ipsw | Optional | `install-dep.sh ipsw` |
| frida | Optional | `install-dep.sh frida` |

---

## Windows PE

| Tool | Required | Install |
|------|---------|---------|
| objdump | Yes | `install-dep.sh objdump` |
| strings | Yes | `install-dep.sh strings-bin` |
| checksec | Optional | `install-dep.sh checksec` |
| upx | Optional | `install-dep.sh upx` |
| radare2 | Optional | `install-dep.sh radare2` |

---

## Linux ELF

| Tool | Required | Install |
|------|---------|---------|
| readelf | Yes | `install-dep.sh readelf` |
| objdump | Yes | `install-dep.sh objdump` |
| nm | Yes | `install-dep.sh nm` |
| checksec | Optional | `install-dep.sh checksec` |
| strace | Optional | `install-dep.sh strace` |
| ltrace | Optional | `install-dep.sh ltrace` |
| radare2 | Optional | `install-dep.sh radare2` |

---

## macOS Mach-O

| Tool | Required | Install |
|------|---------|---------|
| otool | Yes | `install-dep.sh xcode-cli` |
| nm | Yes | `install-dep.sh nm` |
| lipo | Optional | `install-dep.sh xcode-cli` |
| codesign | Optional | `install-dep.sh xcode-cli` |
| radare2 | Optional | `install-dep.sh radare2` |

---

## .NET

| Tool | Required | Install |
|------|---------|---------|
| ilspycmd | Yes | `install-dep.sh ilspycmd` |
| dotnet SDK | Optional | `install-dep.sh dotnet` |
| monodis | Optional | `install-dep.sh monodis` |
| de4dot | Optional | `install-dep.sh de4dot` |

---

## Vulnerability / SAST

| Tool | Purpose | Install |
|------|---------|---------|
| semgrep | Multi-language SAST | `install-dep.sh semgrep` |
| cppcheck | C/C++ static analysis | `install-dep.sh cppcheck` |
| flawfinder | C/C++ dangerous functions | `install-dep.sh flawfinder` |
| bandit | Python security linter | `install-dep.sh bandit` |
| gitleaks | Secret scanning | `install-dep.sh gitleaks` |
| trufflehog | Deep secret scanning | `install-dep.sh trufflehog` |
| gosec | Go security scanner | `install-dep.sh gosec` |
| checksec | Binary hardening check | `install-dep.sh checksec` |

---

## Debugging & Exploit Development

| Tool | Purpose | Install |
|------|---------|---------|
| gdb | GNU Debugger | `install-dep.sh gdb` |
| pwndbg | GDB plugin — heap/ROP/context view | `install-dep.sh pwndbg` |
| gef | GDB Enhanced Features | `install-dep.sh gef` |
| peda | Python Exploit Dev Assistance for GDB | `install-dep.sh peda` |
| lldb | LLVM debugger (macOS default) | `install-dep.sh lldb` |
| pwntools | CTF/exploit framework | `install-dep.sh pwntools` |
| ROPgadget | ROP chain discovery | `install-dep.sh ropgadget` |
| ropper | Gadget finder + ROP builder | `install-dep.sh ropper` |
| one_gadget | Single-gadget shell in libc | `install-dep.sh one-gadget` |
| angr | Symbolic execution framework | `install-dep.sh angr` |
| valgrind | Memory error detector | `install-dep.sh valgrind` |
| patchelf | Modify ELF interpreter/RPATH | `install-dep.sh patchelf` |
| seccomp-tools | Seccomp BPF analysis | `install-dep.sh seccomp-tools` |
| AFL++ | Coverage-guided fuzzer | `install-dep.sh afl++` |

---

## Advanced RE Suites

| Tool | Purpose | Install |
|------|---------|---------|
| Ghidra | NSA RE suite with decompiler | `install-dep.sh ghidra` |
| Cutter | radare2 GUI | `install-dep.sh cutter` |
| RetDec | Binary → C decompiler | `install-dep.sh retdec` |
| radare2 | Advanced binary analysis CLI | `install-dep.sh radare2` |
| binwalk | Firmware/embedded RE | `install-dep.sh binwalk` |
| volatility3 | Memory forensics | `install-dep.sh volatility3` |

---

## One-Command Install by Category

```bash
# All Android tools
bash scripts/install-dep.sh java
bash scripts/install-dep.sh jadx
bash scripts/install-dep.sh apktool
bash scripts/install-dep.sh dex2jar
bash scripts/install-dep.sh vineflower

# All binary analysis tools
bash scripts/install-dep.sh readelf
bash scripts/install-dep.sh objdump
bash scripts/install-dep.sh checksec
bash scripts/install-dep.sh radare2
bash scripts/install-dep.sh binwalk

# All SAST / vuln tools
bash scripts/install-dep.sh semgrep
bash scripts/install-dep.sh bandit
bash scripts/install-dep.sh cppcheck
bash scripts/install-dep.sh gitleaks
bash scripts/install-dep.sh trufflehog

# All exploit-dev tools
bash scripts/install-dep.sh gdb
bash scripts/install-dep.sh pwndbg
bash scripts/install-dep.sh pwntools
bash scripts/install-dep.sh ropgadget
bash scripts/install-dep.sh angr
bash scripts/install-dep.sh ghidra

# Check everything at once
bash scripts/check-deps.sh all
```

---

## Notes

- **GDB extensions**: pwndbg, GEF, and PEDA all modify `~/.gdbinit` — only one can be active at a time. Install the one you prefer; `install-dep.sh` notes this.
- **Ghidra**: requires Java 17+. After install, run `ghidra` (wrapper script) or launch `$GHIDRA_HOME/ghidraRun`.
- **one_gadget**: requires Ruby (`gem install one_gadget`). Works only with known libc versions.
- **angr**: large Python package with many deps — install in a virtual environment if you want isolation: `python3 -m venv .venv && source .venv/bin/activate && pip install angr`.
- **macOS**: `otool`, `codesign`, `lipo`, `lldb` come from Xcode Command Line Tools (`xcode-select --install`). The installer handles this automatically.
