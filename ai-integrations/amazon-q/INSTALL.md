# Amazon Q Developer — Universal RE & Vuln Detection Integration

Amazon Q Developer supports customization through **workspace context** and
**custom instructions** in the IDE plugin settings.

---

## Method 1: Workspace Context File

Create `.amazonq/customization.md` in your project root:

```bash
mkdir -p .amazonq
cat > .amazonq/customization.md << 'EOF'
# Security & Reverse Engineering Context

This workspace performs reverse engineering and security analysis.
When answering questions or generating code, apply these rules:

## Binary Analysis Commands
- ELF: `readelf -h target`, `nm -D target`, `checksec --file=target`, `objdump -d -M intel target`
- PE: `objdump -p target.exe`, `strings -a target.exe`, `checksec --file=target.exe`
- Mach-O: `otool -h target`, `otool -L target`, `nm -gU target`, `codesign -dvv target`
- APK: `jadx -d output/ target.apk`
- IPA: unzip → find Mach-O → otool + class-dump
- .NET: `ilspycmd -p -o out/ target.dll`

## Vulnerability Patterns Always Check
- Hardcoded secrets: password=, api_key=, PRIVATE KEY, AKIA
- Dangerous C functions: gets, strcpy, sprintf, scanf
- Command injection: system(), eval(), os.system(), shell=True
- SQL injection: string concatenation in queries
- Deserialization: pickle.load, ObjectInputStream, BinaryFormatter
- Weak crypto: MD5, SHA1, DES, ECB mode, hardcoded IV
- Binary: missing NX, no PIE, no canary (use checksec)

## Finding Format
[SEVERITY] Type | Location: file:line | Evidence: snippet | Fix: remedy
EOF
```

---

## Method 2: Amazon Q CLI Profile System Prompt

If using Amazon Q Developer CLI (`q`):

```bash
# Set a profile with security context
q configure --profile security-analyst

# Use the system prompt from our codex-cli integration
q chat --system-prompt "$(cat path/to/universal-re-skill/ai-integrations/codex-cli/system-prompt.md)"
```

---

## Method 3: VS Code Plugin Custom Instructions

1. Open VS Code with Amazon Q Developer extension
2. Click the Amazon Q icon in the sidebar
3. Go to **Settings** → **Custom Instructions**
4. Paste the contents of `../codex-cli/system-prompt.md`
5. Save — Q will apply these to all conversations in this workspace

---

## Inline Usage with Amazon Q

Once configured, use Q in the terminal:

```bash
# Analyze a binary
q "Analyze this ELF binary for vulnerabilities" --attach target_binary

# Scan source for issues
q "Find all SQL injection and command injection patterns in this directory" --context ./src

# Quick binary check
q "Run checksec on this file and explain what each missing protection means" --attach ./binary
```

---

## Amazon Q CLI: One-Shot Analysis

```bash
# Install Amazon Q CLI (if not installed)
pip install amazon-q-developer-cli   # or via AWS CLI

# Run analysis query
q "You are a security researcher. Analyze this binary using: file, strings, nm -D, checksec. \
   Report: file type, dangerous imports, hardcoded secrets, binary hardening status." \
  --attach ./target_binary

# Source scan
q "Scan this Python codebase for: pickle.load, yaml.load, eval(), os.system(), \
   hardcoded passwords, SQL injection patterns. Report each as [SEVERITY] Type | Location | Fix" \
  --context ./src
```
