# Linux ELF Reverse Engineering Reference

## ELF File Types

| e_type | Description |
|--------|-------------|
| `ET_EXEC` | Position-dependent executable (no PIE) |
| `ET_DYN` | Position-independent executable (PIE) or shared library |
| `ET_REL` | Relocatable object file (`.o`) |
| `ET_CORE` | Core dump file |

---

## Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `readelf` | ELF headers, sections, dynamic info | `apt install binutils` |
| `objdump` | Disassembly + headers | `apt install binutils` |
| `nm` | Symbol table | `apt install binutils` |
| `strings` | String extraction | `apt install binutils` |
| `strace` | System call trace | `apt install strace` |
| `ltrace` | Library call trace | `apt install ltrace` |
| `checksec` | Security mitigations | `apt install checksec` / `pip install checksec` |
| `pwndbg` | GDB with pwn extensions | GitHub: pwndbg/pwndbg |
| `radare2` | Full RE framework | `apt install radare2` |
| `Ghidra` | NSA decompiler | ghidra-sre.org |
| `angr` | Symbolic execution | `pip install angr` |

---

## Basic Identification

```bash
# File type and architecture
file target
# → ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked,
#   interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=..., not stripped

# ELF header
readelf -h target
# Key fields: Class (32/64 bit), Machine (EM_X86_64/EM_ARM/etc.),
#             Type (DYN=PIE, EXEC=no-PIE), Entry point

# Quick summary
file target && readelf -h target | grep -E '(Class|Machine|Type|Entry)'
```

---

## Sections

```bash
# List all sections
readelf -S target

# Key sections:
# .text    → executable code
# .rodata  → read-only data (strings, constants)
# .data    → initialized global variables
# .bss     → uninitialized globals
# .got     → Global Offset Table (function pointers for lazy binding)
# .plt     → Procedure Linkage Table (trampoline stubs)
# .got.plt → GOT entries for PLT
# .dynamic → Dynamic linking info

# Section content (hex + strings)
objdump -s --section=.rodata target | head -40
```

---

## Dynamic Dependencies

```bash
# Libraries the binary links against
readelf -d target | grep NEEDED
# ldd shows full resolved paths (requires compatible system)
ldd target

# RPATH / RUNPATH (where to search for libs — hijack target)
readelf -d target | grep -E 'RPATH|RUNPATH'
# Empty RPATH + writable . in PATH = DT_RPATH hijack possible
```

---

## Symbol Tables

```bash
# Dynamic symbol table (visible to linker)
nm -D target

# All symbols including local (for non-stripped binaries)
nm -a target | head -40

# Undefined (imported) symbols
nm -u target | head -30

# Dangerous function imports
nm -D target | grep -E ' U .*(gets|strcpy|strcat|sprintf|vsprintf|scanf|system|popen|exec)'
```

---

## Disassembly

```bash
# Disassemble all executable sections
objdump -d target > disasm.asm

# Intel syntax (easier to read)
objdump -d -M intel target | head -100

# Only the .text section
objdump -d --section=.text target | head -100

# Specific function (by name)
objdump -d target | grep -A50 '<main>:'

# With radare2 (best output)
r2 -A target
# r2 commands:
# afl           → list all functions
# s main        → seek to main
# pdf           → print disassembly of current function
# axt sym.imp.gets → find all callers of gets()
# s sym.imp.strcpy; axt → all callers of strcpy
```

---

## Security Mitigations

```bash
# Best tool
checksec --file=target

# Manual checks:
# 1. NX / DEP — is stack executable?
readelf -l target | grep 'GNU_STACK'
# RW  = non-executable stack (NX enabled — good)
# RWE = executable stack (NX DISABLED — bad)

# 2. Stack canary
nm -D target | grep '__stack_chk_fail'
# Present = stack canary enabled

# 3. PIE
readelf -h target | grep 'Type:'
# DYN = PIE enabled (randomized load address)
# EXEC = no PIE (fixed address — easier ROP)

# 4. RELRO
readelf -l target | grep 'GNU_RELRO'      # PARTIAL if present
readelf -d target | grep 'BIND_NOW'       # FULL RELRO if also present

# 5. FORTIFY_SOURCE
nm -D target | grep '_chk@'              # e.g., __printf_chk, __strcpy_chk

# 6. Position of GOT/PLT
objdump -d target | grep -E 'call.*@plt'  # PLT entries
```

---

## String Analysis

```bash
# All strings ≥6 chars
strings -a -n 6 target > strings.txt

# Interesting patterns
grep -E 'https?://|ftp://' strings.txt
grep -iE '(password|secret|api[_-]?key|token|auth)' strings.txt
grep -E '/bin/sh|/bin/bash|/etc/passwd|/etc/shadow' strings.txt
grep -E 'flag\{|CTF\{|picoCTF' strings.txt    # CTF flags
grep -E '^[A-Za-z0-9+/]{20,}={0,2}$' strings.txt | head -10  # base64
```

---

## GOT / PLT (for exploit dev / hooking)

```bash
# List PLT entries (name → address mapping)
objdump -d target | grep '@plt>' | sed 's/.*<//; s/@plt>//'

# GOT entries
objdump -R target    # dynamic reloc entries = GOT entries for extern funcs

# In radare2
r2 -A target
# > ir    → list relocations
# > iS    → list sections with addresses
# > is    → imports
```

---

## Dynamic Analysis

```bash
# Trace system calls
strace ./target 2>&1 | head -50

# Trace library calls (args + return values)
ltrace ./target 2>&1 | head -50

# Trace specific calls
strace -e trace=open,read,write,execve ./target

# With gdb + pwndbg
gdb ./target
# pwndbg commands:
# run            → start
# checksec       → check mitigations
# pattern create 100 → create cyclic pattern for overflow
# cyclic -l 0x41614141 → find offset
# disass main    → disassemble main
# x/10i $rip     → examine instructions at rip
```

---

## Common CTF / Pwn Patterns

| Vulnerability | Detection | Tool |
|--------------|-----------|------|
| Stack overflow | `gets`, `strcpy`, `scanf("%s")` in nm + no canary | checksec + nm |
| Format string | `printf(user_input)` — `printf` called with only 1 arg | objdump grep |
| Heap overflow | `malloc` without proper bounds, `free` twice | ltrace + valgrind |
| ROP chain needed | NX enabled, no canary | checksec |
| ret2libc | Leaked libc address + system() import | nm + plt |
| ret2plt | `system@plt` or `execve@plt` present | objdump |
