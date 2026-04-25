#!/usr/bin/env bash
# detect-target.sh — Auto-detect binary/source format
# Output: TARGET_TYPE:<type> and TARGET_ARCH:<arch>
# Usage: detect-target.sh <file-or-dir>
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: detect-target.sh <file-or-directory>" >&2
  exit 1
fi

TARGET="$1"

if [[ ! -e "$TARGET" ]]; then
  echo "Error: '$TARGET' does not exist." >&2
  exit 1
fi

# Directory → source code project
if [[ -d "$TARGET" ]]; then
  ext_counts=""
  c_count=$(find "$TARGET" -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.cc" -o -name "*.cxx" 2>/dev/null | wc -l)
  py_count=$(find "$TARGET" -name "*.py" 2>/dev/null | wc -l)
  java_count=$(find "$TARGET" -name "*.java" -o -name "*.kt" 2>/dev/null | wc -l)
  js_count=$(find "$TARGET" -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" 2>/dev/null | wc -l)
  go_count=$(find "$TARGET" -name "*.go" 2>/dev/null | wc -l)
  rs_count=$(find "$TARGET" -name "*.rs" 2>/dev/null | wc -l)
  cs_count=$(find "$TARGET" -name "*.cs" 2>/dev/null | wc -l)

  echo "=== Source Directory Analysis ==="
  echo "C/C++: $c_count  Python: $py_count  Java/Kotlin: $java_count"
  echo "JS/TS: $js_count  Go: $go_count  Rust: $rs_count  C#: $cs_count"
  echo

  # Pick dominant language
  max=0
  type="unknown"
  for pair in "$c_count:source-c" "$py_count:source-python" "$java_count:source-java" \
              "$js_count:source-javascript" "$go_count:source-go" "$rs_count:source-rust" \
              "$cs_count:source-csharp"; do
    count="${pair%%:*}"
    t="${pair##*:}"
    if (( count > max )); then
      max=$count
      type=$t
    fi
  done

  echo "TARGET_TYPE:$type"
  echo "TARGET_ARCH:source"
  exit 0
fi

# File — use file(1) and extension
FILE_OUTPUT=$(file -b "$TARGET" 2>/dev/null || echo "unknown")
FILENAME=$(basename "$TARGET")
EXT="${FILENAME##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

echo "=== File Type Detection ==="
echo "File: $TARGET"
echo "file(1) output: $FILE_OUTPUT"
echo "Extension: .$EXT_LOWER"
echo

detect_arch() {
  local fout="$1"
  if echo "$fout" | grep -qi 'aarch64\|arm64'; then echo "arm64"
  elif echo "$fout" | grep -qi 'arm'; then echo "arm"
  elif echo "$fout" | grep -qi 'x86-64\|x86_64\|AMD64\|x64'; then echo "x86_64"
  elif echo "$fout" | grep -qi 'i386\|i486\|i586\|i686\|80386\|x86'; then echo "x86"
  elif echo "$fout" | grep -qi 'MIPS'; then echo "mips"
  elif echo "$fout" | grep -qi 'PowerPC\|PPC'; then echo "ppc"
  else echo "unknown"
  fi
}

ARCH=$(detect_arch "$FILE_OUTPUT")

# Android
case "$EXT_LOWER" in
  apk)
    echo "TARGET_TYPE:android-apk"
    echo "TARGET_ARCH:dalvik"
    exit 0
    ;;
  xapk)
    echo "TARGET_TYPE:android-xapk"
    echo "TARGET_ARCH:dalvik"
    exit 0
    ;;
  jar)
    if echo "$FILE_OUTPUT" | grep -qi 'zip\|JAR\|Java'; then
      # Check for classes.dex inside (Android)
      if command -v unzip &>/dev/null && unzip -l "$TARGET" 2>/dev/null | grep -q 'classes.dex'; then
        echo "TARGET_TYPE:android-apk"
        echo "TARGET_ARCH:dalvik"
      else
        echo "TARGET_TYPE:android-jar"
        echo "TARGET_ARCH:jvm"
      fi
    fi
    exit 0
    ;;
  aar)
    echo "TARGET_TYPE:android-aar"
    echo "TARGET_ARCH:dalvik"
    exit 0
    ;;
  dex)
    echo "TARGET_TYPE:android-dex"
    echo "TARGET_ARCH:dalvik"
    exit 0
    ;;
esac

# iOS
case "$EXT_LOWER" in
  ipa)
    echo "TARGET_TYPE:ios-ipa"
    echo "TARGET_ARCH:arm64"
    exit 0
    ;;
esac

# ELF
if echo "$FILE_OUTPUT" | grep -qi 'ELF'; then
  if echo "$FILE_OUTPUT" | grep -qi 'shared object\|shared library\|dynamically linked shared'; then
    echo "TARGET_TYPE:linux-elf-so"
  else
    echo "TARGET_TYPE:linux-elf"
  fi
  echo "TARGET_ARCH:$ARCH"
  exit 0
fi

# Mach-O
if echo "$FILE_OUTPUT" | grep -qi 'Mach-O'; then
  if echo "$FILE_OUTPUT" | grep -qi 'dynamically linked shared library\|bundle'; then
    echo "TARGET_TYPE:macos-dylib"
  else
    echo "TARGET_TYPE:macos-macho"
  fi
  echo "TARGET_ARCH:$ARCH"
  exit 0
fi

# PE (Windows)
if echo "$FILE_OUTPUT" | grep -qi 'PE32\|PE32+\|MS-DOS executable\|DLL'; then
  # Check for .NET
  if echo "$FILE_OUTPUT" | grep -qi 'Mono\|\.Net\|CIL'; then
    echo "TARGET_TYPE:windows-dotnet"
    echo "TARGET_ARCH:msil"
    exit 0
  fi
  if echo "$FILE_OUTPUT" | grep -qi 'PE32+\|x86-64\|AMD64'; then
    echo "TARGET_TYPE:windows-pe64"
  else
    echo "TARGET_TYPE:windows-pe32"
  fi
  echo "TARGET_ARCH:$ARCH"
  exit 0
fi

# .NET standalone detection (sometimes not caught by PE check)
if echo "$FILE_OUTPUT" | grep -qi 'Mono/.Net\|CIL\|Common Language'; then
  echo "TARGET_TYPE:dotnet-assembly"
  echo "TARGET_ARCH:msil"
  exit 0
fi

case "$EXT_LOWER" in
  dll)
    if echo "$FILE_OUTPUT" | grep -qi 'Mono\|\.Net\|CIL'; then
      echo "TARGET_TYPE:windows-dotnet"
      echo "TARGET_ARCH:msil"
    else
      echo "TARGET_TYPE:windows-pe64"
      echo "TARGET_ARCH:$ARCH"
    fi
    exit 0
    ;;
  exe)
    if echo "$FILE_OUTPUT" | grep -qi 'Mono\|\.Net\|CIL'; then
      echo "TARGET_TYPE:windows-dotnet"
      echo "TARGET_ARCH:msil"
    else
      echo "TARGET_TYPE:windows-pe32"
      echo "TARGET_ARCH:$ARCH"
    fi
    exit 0
    ;;
  nupkg)
    echo "TARGET_TYPE:dotnet-nupkg"
    echo "TARGET_ARCH:msil"
    exit 0
    ;;
  # Source files
  c|cpp|cc|cxx|h|hpp)
    echo "TARGET_TYPE:source-c"
    echo "TARGET_ARCH:source"
    exit 0
    ;;
  py)
    echo "TARGET_TYPE:source-python"
    echo "TARGET_ARCH:source"
    exit 0
    ;;
  java|kt)
    echo "TARGET_TYPE:source-java"
    echo "TARGET_ARCH:source"
    exit 0
    ;;
  js|ts|jsx|tsx|mjs|cjs)
    echo "TARGET_TYPE:source-javascript"
    echo "TARGET_ARCH:source"
    exit 0
    ;;
  go)
    echo "TARGET_TYPE:source-go"
    echo "TARGET_ARCH:source"
    exit 0
    ;;
  rs)
    echo "TARGET_TYPE:source-rust"
    echo "TARGET_ARCH:source"
    exit 0
    ;;
  cs)
    echo "TARGET_TYPE:source-csharp"
    echo "TARGET_ARCH:source"
    exit 0
    ;;
esac

# Fallback: fat/universal binary
if echo "$FILE_OUTPUT" | grep -qi 'universal binary'; then
  echo "TARGET_TYPE:macos-universal"
  echo "TARGET_ARCH:multi"
  exit 0
fi

echo "TARGET_TYPE:unknown"
echo "TARGET_ARCH:unknown"
echo
echo "Could not determine file type. Try: file -b '$TARGET'"
