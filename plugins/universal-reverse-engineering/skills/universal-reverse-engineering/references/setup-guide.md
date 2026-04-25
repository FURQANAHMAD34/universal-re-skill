# Setup Guide: All Dependencies

Quick-install any dep: `bash scripts/install-dep.sh <name>`

---

## Universal (Required on all platforms)

| Tool | Purpose | Install |
|------|---------|---------|
| `file` | File type detection | Built-in on Linux/macOS |
| `strings` | String extraction | `apt install binutils` / `brew install binutils` |
| `grep` | Pattern search | Built-in |
| `unzip` | Archive extraction | `apt install unzip` / built-in macOS |

---

## Android

| Tool | Required | Install |
|------|---------|---------|
| Java JDK 17+ | Yes | `apt install openjdk-17-jdk` / `brew install openjdk@17` |
| jadx | Yes | GitHub releases or `brew install jadx` |
| apktool | Optional | `apt install apktool` / `brew install apktool` |
| dex2jar | Optional | GitHub releases: pxb1988/dex2jar |
| Vineflower | Optional | GitHub releases: Vineflower/vineflower |
| adb | Optional | `apt install adb` / `brew install android-platform-tools` |

---

## iOS / macOS

| Tool | Required | Install |
|------|---------|---------|
| otool | Yes | `xcode-select --install` (macOS) |
| nm | Yes | `xcode-select --install` / `apt install binutils` |
| class-dump | Optional | `brew install class-dump` |
| codesign | Optional | Xcode CLI Tools |
| lipo | Optional | Xcode CLI Tools |
| ipsw | Optional | `brew install blacktop/tap/ipsw` |

---

## Windows PE

| Tool | Required | Install |
|------|---------|---------|
| objdump | Yes | `apt install binutils` / `brew install binutils` |
| strings | Yes | `apt install binutils` |
| readpe | Optional | `apt install pev` |
| capa | Optional | GitHub: mandiant/capa releases |
| upx | Optional | `apt install upx` / `brew install upx` |

---

## Linux ELF

| Tool | Required | Install |
|------|---------|---------|
| readelf | Yes | `apt install binutils` |
| objdump | Yes | `apt install binutils` |
| nm | Yes | `apt install binutils` |
| strace | Optional | `apt install strace` |
| ltrace | Optional | `apt install ltrace` |
| checksec | Optional | `apt install checksec` / `pip install checksec` |

---

## .NET

| Tool | Required | Install |
|------|---------|---------|
| ilspycmd | Yes | `dotnet tool install -g ilspycmd` |
| .NET SDK | Yes | https://dotnet.microsoft.com/download |
| monodis | Optional | `apt install mono-utils` |

---

## Vulnerability / SAST

| Tool | Purpose | Install |
|------|---------|---------|
| semgrep | Multi-language SAST | `pip install semgrep` |
| cppcheck | C/C++ static analysis | `apt install cppcheck` / `brew install cppcheck` |
| flawfinder | C/C++ dangerous functions | `pip install flawfinder` |
| bandit | Python security linter | `pip install bandit` |
| gitleaks | Secret scanning | GitHub releases: gitleaks/gitleaks |
| trufflehog | Deep secret scanning | `pip install trufflehog` |
| gosec | Go security scanner | `go install github.com/securego/gosec/v2/cmd/gosec@latest` |
| checksec | Binary hardening check | `apt install checksec` / `pip install checksec` |

---

## Advanced / Optional

| Tool | Purpose | Install |
|------|---------|---------|
| radare2 | Advanced binary analysis | `apt install radare2` / `brew install radare2` |
| Ghidra | NSA RE suite (GUI) | https://ghidra-sre.org |
| binwalk | Firmware / embedded analysis | `apt install binwalk` / `pip install binwalk` |

---

## One-Line Install by Category

```bash
# Linux (apt) — all Android tools
sudo apt install openjdk-17-jdk apktool adb unzip && bash scripts/install-dep.sh jadx

# Linux (apt) — all binary analysis tools
sudo apt install binutils readelf checksec strace ltrace radare2

# Linux (apt) — all SAST tools
pip install semgrep cppcheck flawfinder bandit gitleaks trufflehog

# macOS (Homebrew) — all tools
brew install jadx apktool android-platform-tools openjdk@17 \
     binutils radare2 cppcheck semgrep gitleaks class-dump checksec
```
