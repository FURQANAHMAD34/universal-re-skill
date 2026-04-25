# .NET Assembly Reverse Engineering Reference

## File Types

| Extension | Description |
|-----------|-------------|
| `.exe` | .NET executable |
| `.dll` | .NET library |
| `.nupkg` | NuGet package (ZIP of assemblies + metadata) |
| `.xap` | Silverlight package |
| `.appx` / `.msix` | UWP app package |

---

## Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `ilspycmd` | CLI decompiler (best free option) | `dotnet tool install -g ilspycmd` |
| `ILSpy` | GUI decompiler | GitHub: icsharpcode/ILSpy |
| `dnSpy` | GUI decompiler + debugger | GitHub: dnSpy/dnSpy (archived) |
| `de4dot` | .NET obfuscation remover | GitHub: de4dot/de4dot |
| `monodis` | Mono IL disassembler | `apt install mono-utils` |
| `ildasm` | Microsoft IL disassembler | .NET SDK (`ildasm.exe`) |
| `strings` | String extraction | `apt install binutils` |
| `dnlib` | .NET assembly library (Python-via-.NET) | NuGet: dnlib |
| `Ghidra` | Supports .NET via plugin | ghidra-sre.org |

---

## Detect .NET Assembly

```bash
file target.exe
# → PE32 executable ... Mono/.Net assembly

# or programmatically
python3 -c "
import pefile
pe = pefile.PE('target.exe')
clr_dir = pe.OPTIONAL_HEADER.DATA_DIRECTORY[14]
print('Is .NET:', clr_dir.VirtualAddress != 0)
"
```

---

## Decompile with ilspycmd

```bash
# Install (once)
dotnet tool install -g ilspycmd
export PATH="$HOME/.dotnet/tools:$PATH"

# Decompile to project directory
ilspycmd -p -o decompiled/ target.dll

# Decompile to single file
ilspycmd target.dll

# Specific type
ilspycmd -t "Namespace.ClassName" target.dll

# List types only
ilspycmd --list-types target.dll | head -30
```

---

## monodis (Mono IL)

```bash
# List types
monodis --typedef target.exe | head -30

# Disassemble to IL
monodis target.exe > target.il

# List methods
monodis --method target.exe | head -30

# String table
monodis --strings target.exe | head -30
```

---

## ildasm (Windows / .NET SDK)

```bash
# On Windows or with mono
ildasm target.dll /out:target.il

# Or view in console
ildasm target.dll /text | head -100
```

---

## String Analysis

```bash
# All strings in the binary
strings -a -n 6 target.dll > strings.txt

# URLs and endpoints
grep -E 'https?://|ftp://' strings.txt

# Credentials
grep -iE '(password|passwd|secret|api.?key|token|bearer|connectionString)' strings.txt

# SQL connection strings
grep -iE '(Data Source=|Server=|Initial Catalog=|User ID=|Password=)' strings.txt

# .NET-specific embedded resources
# Resources are often in a .resources file inside the DLL
```

---

## Obfuscation Detection

```bash
# Look for obfuscator markers
strings target.dll | grep -iE '(ConfuserEx|Dotfuscator|Obfuscar|Babel|Eazfuscator|SmartAssembly|Rpx|Goliath)'

# Scrambled names = obfuscated
ilspycmd --list-types target.dll | grep -E '^[a-z]{1,3}$|^[A-Za-z]{1,3}$' | head -20
# Single-letter or 1-2 char class names = obfuscated

# Remove obfuscation with de4dot
de4dot target.dll -o target-clean.dll
```

---

## Interesting .NET Patterns (in decompiled C# source)

After running `ilspycmd -p -o decompiled/ target.dll`:

```bash
# Network calls
grep -rn --include="*.cs" \
  -E '(HttpClient|WebClient|HttpWebRequest|RestClient|WebRequest|TcpClient|Socket)' \
  decompiled/

# Database (SQL injection risk)
grep -rn --include="*.cs" \
  -E '(SqlCommand|OleDbCommand|NpgsqlCommand|MySqlCommand)\s*\(.*\+' \
  decompiled/
grep -rn --include="*.cs" \
  -E '(ExecuteNonQuery|ExecuteScalar|ExecuteReader)\s*\(' \
  decompiled/

# Command injection
grep -rn --include="*.cs" \
  -E '(Process\.Start\s*\(|ProcessStartInfo.*FileName|cmd\.exe|powershell.*-c)' \
  decompiled/

# Insecure deserialization
grep -rn --include="*.cs" \
  -E '(BinaryFormatter|SoapFormatter|NetDataContractSerializer|JsonConvert.*TypeNameHandling\.(All|Objects|Auto)|XmlSerializer.*UnknownType)' \
  decompiled/

# Cryptography (check for weak algorithms)
grep -rn --include="*.cs" \
  -E '(MD5|SHA1(?!_256)\b|DES(?!ede)\b|RC2|RC4|TripleDES|RijndaelManaged.*ECB|AesManaged.*ECB)' \
  decompiled/

# P/Invoke (native interop — potential memory issues)
grep -rn --include="*.cs" \
  -E '\[DllImport|Marshal\.(AllocHGlobal|PtrToStructure|Copy)|unsafe\s+(class|void|static)' \
  decompiled/

# Environment and config reading
grep -rn --include="*.cs" \
  -E '(Environment\.GetEnvironmentVariable|ConfigurationManager\.AppSettings|Registry\.GetValue)' \
  decompiled/

# XML processing (XXE risk)
grep -rn --include="*.cs" \
  -E '(XmlDocument|XmlReader|XPathDocument|XDocument)\.Load\s*\(' \
  decompiled/
```

---

## NuGet Package Analysis

```bash
# A .nupkg is a ZIP
unzip -l target.nupkg | head -30

# Extract everything
mkdir nupkg-extracted && unzip target.nupkg -d nupkg-extracted/

# Find all assemblies
find nupkg-extracted -name '*.dll' | head -20

# Decompile each
for dll in $(find nupkg-extracted -name '*.dll'); do
  echo "=== $dll ==="
  ilspycmd --list-types "$dll" 2>/dev/null | head -10
done
```

---

## Common Security Issues in .NET

| Issue | Where to Look |
|-------|--------------|
| SQL injection | `SqlCommand` + string concat |
| Deserialization | `BinaryFormatter.Deserialize` |
| Command injection | `Process.Start` with user input |
| Path traversal | `File.ReadAllText(userInput)` |
| Hardcoded creds | `SqlConnection` string in source |
| Weak crypto | `MD5.Create()`, `new DESCryptoServiceProvider()` |
| XXE | `XmlDocument` without `XmlResolver = null` |
| Insecure reflection | `Assembly.Load(userBytes)` |
| SSRF | `WebClient.DownloadString(userUrl)` |
| LDAP injection | `DirectorySearcher` with user input |
