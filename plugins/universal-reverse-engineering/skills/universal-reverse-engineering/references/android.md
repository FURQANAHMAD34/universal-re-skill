# Android Reverse Engineering Reference

## File Types

| Extension | Description |
|-----------|-------------|
| `.apk` | Android Package — the standard installable app (ZIP) |
| `.xapk` | Extended APK — ZIP of APKs + OBB files (APKPure format) |
| `.aab` | Android App Bundle — not directly installable; used for Play Store upload |
| `.jar` | Java Archive — may contain Dalvik DEX or standard JVM bytecode |
| `.aar` | Android ARchive — library format (ZIP of classes.jar + resources) |
| `.dex` | Dalvik Executable — compiled Android bytecode |

---

## Tools

| Tool | Purpose | Install |
|------|---------|---------|
| jadx | APK/JAR/AAR → Java source | GitHub: skylot/jadx |
| apktool | APK → smali + XML resources | `apt install apktool` |
| dex2jar | DEX → JAR (for Fernflower) | GitHub: pxb1988/dex2jar |
| Vineflower | JAR → Java source (better for complex code) | GitHub: Vineflower/vineflower |
| adb | Android Debug Bridge | `apt install adb` |
| frida-tools | Dynamic instrumentation | `pip install frida-tools` |
| MobSF | Automated mobile security framework | GitHub: MobSF/Mobile-Security-Framework-MobSF |

---

## APK Structure

An APK is a ZIP file. Contents:
```
AndroidManifest.xml    ← binary XML, encoded — jadx/apktool decode it
classes.dex            ← compiled Dalvik bytecode for main classes
classes2.dex           ← secondary dex (multidex)
res/                   ← compiled resources (layout, drawable, values)
assets/                ← raw assets (HTML, databases, configs)
lib/                   ← native .so libraries (armeabi-v7a, arm64-v8a, x86)
META-INF/              ← signing certificates and manifest
resources.arsc         ← compiled resource table
```

---

## Decompile with jadx

```bash
# Basic decompile
jadx -d output/ app.apk

# With deobfuscation (for obfuscated apps — single-letter names)
jadx -d output/ --deobf app.apk

# Code only, skip resources (faster)
jadx -d output/ --no-res app.apk

# Show partial/bad code instead of errors
jadx -d output/ --show-bad-code app.apk

# Decompile library JAR
jadx -d output/ library.jar

# Output structure:
# output/sources/    → decompiled Java source
# output/resources/  → decoded XML resources including AndroidManifest.xml
```

---

## AndroidManifest.xml Analysis

After jadx decompiles, read `output/resources/AndroidManifest.xml`:

```bash
# Key things to extract:
# 1. Package name
grep 'package=' output/resources/AndroidManifest.xml | head -1

# 2. Main launcher activity
grep -A5 'android.intent.action.MAIN' output/resources/AndroidManifest.xml

# 3. All activities/services/receivers/providers
grep -E '<(activity|service|receiver|provider)' output/resources/AndroidManifest.xml

# 4. Exported components (potential attack surface)
grep 'android:exported="true"' output/resources/AndroidManifest.xml

# 5. Permissions
grep 'uses-permission' output/resources/AndroidManifest.xml

# 6. Application class (custom Application)
grep 'android:name=' output/resources/AndroidManifest.xml | grep 'application'

# 7. Backup flag (insecure backup)
grep 'android:allowBackup' output/resources/AndroidManifest.xml

# 8. Debug flag (production app should be false)
grep 'android:debuggable' output/resources/AndroidManifest.xml
```

---

## Package Structure Navigation

```
output/sources/
  com/example/app/
    MainActivity.java           ← launcher activity
    data/
      network/
        ApiService.java         ← Retrofit interface
      repository/
        UserRepository.java
    domain/
      model/
      usecase/
    presentation/
      viewmodel/
        LoginViewModel.java
    di/
      AppModule.java            ← Dagger/Hilt DI bindings
```

```bash
# Find network-related packages
find output/sources -type d | grep -iE '(api|network|http|retrofit|data|repository|remote)'

# Find all Retrofit interfaces
grep -rn '@GET\|@POST\|@PUT\|@DELETE' output/sources/ | head -20

# Find all Activities
grep -rn 'extends AppCompatActivity\|extends Activity' output/sources/ | head -20

# Find all ViewModels
grep -rn 'extends ViewModel\|extends AndroidViewModel' output/sources/ | head -20
```

---

## Network / API Extraction

```bash
# Retrofit annotations
grep -rn --include="*.java" -E '@(GET|POST|PUT|DELETE|PATCH|HTTP)\s*\(' output/sources/

# Base URL and endpoint constants
grep -rn --include="*.java" -iE '(BASE_URL|API_URL|SERVER_URL|ENDPOINT|baseUrl)\s*[=:]' output/sources/

# OkHttp patterns
grep -rn --include="*.java" -E '(Request\.Builder|OkHttpClient|newCall|enqueue|addInterceptor)' output/sources/

# Hardcoded URLs
grep -rn --include="*.java" -E '"https?://[^"]+"' output/sources/ | head -20

# Auth patterns
grep -rn --include="*.java" -iE '(Authorization|Bearer|api[_-]?key|x-api-key|access_token)' output/sources/

# WebView usage
grep -rn --include="*.java" -E '(loadUrl|addJavascriptInterface|setJavaScriptEnabled)' output/sources/
```

---

## Security Checks

```bash
# Hardcoded credentials / secrets
grep -rn --include="*.java" \
  -E '(password\s*=\s*"[^"]{4,}"|secret\s*=\s*"[^"]{6,}"|api[_-]?key\s*=\s*"[^"]{8,}")' \
  output/sources/

# Insecure cryptography
grep -rn --include="*.java" \
  -E '(getInstance\("MD5"|getInstance\("SHA-1"|getInstance\("DES"|getInstance\("AES/ECB|getInstance\("RC4)' \
  output/sources/

# SQL injection (ContentProvider + raw queries)
grep -rn --include="*.java" \
  -E '(rawQuery|execSQL|query\s*\()' \
  output/sources/ | head -20

# Exported components with intent data
grep -rn --include="*.java" -E 'getIntent\(\)\.(get|getString|getData)' output/sources/ | head -20

# WebView JS enabled
grep -rn --include="*.java" 'setJavaScriptEnabled(true)' output/sources/

# Insecure SharedPreferences (storing sensitive data)
grep -rn --include="*.java" -E '(getSharedPreferences|SharedPreferences\.Editor)' output/sources/ | head -20

# Custom SSL trust manager (certificate pinning bypass / no validation)
grep -rn --include="*.java" \
  -E '(TrustManager|X509TrustManager|checkServerTrusted|onReceivedSslError)' \
  output/sources/
```

---

## Native Libraries

```bash
# List native libs
find output -name '*.so' | head -10

# Analyze with readelf / nm
readelf -h output/lib/arm64-v8a/libapp.so
nm -D output/lib/arm64-v8a/libapp.so | grep -E 'Java_|JNI_' | head -20

# JNI function naming: Java_<package>_<class>_<method>
nm -D output/lib/arm64-v8a/libapp.so | grep 'Java_'

# Extract strings from native lib
strings output/lib/arm64-v8a/libapp.so | head -30
```

---

## Common Architecture Patterns

| Pattern | Detection |
|---------|-----------|
| MVP | `Presenter` classes, `View` interfaces |
| MVVM | `ViewModel` extends, `LiveData`, `StateFlow` |
| Clean Architecture | `domain/`, `data/`, `presentation/` packages |
| Dagger/Hilt | `@Module`, `@Provides`, `@Inject`, `@Component` |
| Retrofit | `@GET`, `@POST`, `interface *Service` |
| Room DB | `@Entity`, `@Dao`, `@Database` annotations |
| RxJava | `Observable`, `Single`, `Flowable`, `Disposable` |

---

## Dynamic Analysis

```bash
# List installed apps on connected device
adb shell pm list packages | grep -i <keyword>

# Get APK from device
adb shell pm path com.example.app
adb pull /data/app/com.example.app-xxx/base.apk ./app.apk

# Logcat (look for debug output)
adb logcat | grep -i <package>

# Frida: hook network calls
frida-trace -U -f com.example.app -m 'okhttp3.OkHttpClient!enqueue'

# Frida: bypass SSL pinning
frida --codeshare pcipolloni/universal-android-ssl-pinning-bypass-with-frida -f com.example.app -U
```
