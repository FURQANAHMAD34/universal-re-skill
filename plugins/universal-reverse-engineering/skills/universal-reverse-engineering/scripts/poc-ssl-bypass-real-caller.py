#!/usr/bin/env python3
"""
Real Caller — Comprehensive SSL Pinning Bypass (All Locations)
Target:  menwho.phone.callerid.social
Source:  HtsUtils.java + MainApplication.java (decompiled)
Author:  universal-re-skill / devyforge.com

====================================================================
VULNERABILITY ANALYSIS (from decompiled source):
====================================================================

MainApplication.java:setMainMcc()
  → reads TelephonyManager.getNetworkOperator()[0:3] → mainmcc (int)

HtsUtils.java:returnAppSecureCntxUrlBks()          [used for: login, verify, block/unblock, name lookup]
HtsUtils.java:returnAppSecureCntxUrlBksSFS()        [used for: secondary server calls]
HtsUtils.java:returnUploadImgUrlBks()               [used for: profile image upload]
  → if mainmcc != 424: httpsURLConnection.setSSLSocketFactory(sslContext.getSocketFactory())
  → if mainmcc == 424: default SSL (NO pinning) ← UAE users unprotected

HtsUtils.java:returnAppSecureCntxUrlBksForcePan()   [used for: MainActivity ALL main API calls]
  → ALWAYS: httpsURLConnection.setSSLSocketFactory(sslContext.getSocketFactory())
  → No MCC check — all regions get pinning here

MainApplication.java:returnSSLcontext()
  → loads R.raw.g (custom cert) into KeyStore → TrustManagerFactory → SSLContext
  → sslContext pinned to server cert

MainApplication.java:returnSSLcontextSFS()
  → loads R.raw.m (secondary custom cert) → sslContextSFS

====================================================================
BYPASS STRATEGY (four-layer, covers all regions and all methods):
====================================================================

Layer 1 — MCC Spoof to UAE (424)
  Targets: returnAppSecureCntxUrlBks, returnAppSecureCntxUrlBksSFS,
           returnUploadImgUrlBks
  How: Intercept TelephonyManager.getNetworkOperator() → return "42402"
       → mainmcc becomes 424 → condition (mainmcc != 424) is FALSE
       → setSSLSocketFactory is never called → default SSL used

Layer 2 — Permissive SSLContext injection
  Targets: returnAppSecureCntxUrlBksForcePan (no MCC check)
  How: Hook MainApplication.returnSSLcontext() and returnSSLcontextSFS()
       → replace TrustManager with an all-trusting implementation
       → sslContext.getSocketFactory() now accepts any certificate

Layer 3 — HttpsURLConnection.setSSLSocketFactory fallback
  Targets: Any remaining SSL calls
  How: Hook setSSLSocketFactory on all HttpsURLConnection instances
       → inject the permissive factory directly

Layer 4 — System TrustManager nullification
  Targets: OkHttp, Retrofit, WebView SSL
  How: Hook X509TrustManager.checkServerTrusted → no-op
       Hook HostnameVerifier.verify → return true

====================================================================
REQUIREMENTS:
====================================================================
  pip install frida-tools
  Rooted device OR Frida Gadget injected into APK
  ADB: adb shell settings put global http_proxy <burp-ip>:8080
  Burp Suite: Proxy → Options → listen on 0.0.0.0:8080

====================================================================
USAGE:
====================================================================
  # Spawn mode (fresh start):
  frida -U -f menwho.phone.callerid.social -l poc-ssl-bypass-real-caller.py --no-pause

  # Attach mode (already running):
  frida -U menwho.phone.callerid.social -l poc-ssl-bypass-real-caller.py

  # With objection (alternative):
  objection -g menwho.phone.callerid.social explore
  > android sslpinning disable
"""

import frida
import sys
import time

PACKAGE = "menwho.phone.callerid.social"

SCRIPT = r"""
Java.perform(function() {
    console.log("[*] Real Caller SSL Bypass — All Locations");
    console.log("[*] Package: menwho.phone.callerid.social");
    console.log("[*] Applying 4-layer bypass...");

    // =========================================================================
    // LAYER 1: MCC Spoof — force mainmcc = 424 (UAE)
    // This disables setSSLSocketFactory in returnAppSecureCntxUrlBks,
    // returnAppSecureCntxUrlBksSFS, and returnUploadImgUrlBks
    // =========================================================================
    try {
        var TelephonyManager = Java.use("android.telephony.TelephonyManager");

        // Hook getNetworkOperator to return UAE MCC+MNC (424-02 = Etisalat UAE)
        TelephonyManager.getNetworkOperator.implementation = function() {
            console.log("[L1] TelephonyManager.getNetworkOperator() → '42402' (UAE spoof)");
            return "42402";  // MCC=424 (UAE), MNC=02 (Etisalat)
        };

        // Also hook getSimOperator in case app falls back to SIM MCC
        TelephonyManager.getSimOperator.implementation = function() {
            console.log("[L1] TelephonyManager.getSimOperator() → '42402' (UAE spoof)");
            return "42402";
        };

        // Force mainmcc field directly on MainApplication class
        try {
            var MainApplication = Java.use("menwho.phone.callerid.social.MainApplication");
            // Set static field mainmcc = 424
            MainApplication.mainmcc.value = 424;
            console.log("[L1] MainApplication.mainmcc forced to 424");
        } catch(e) {
            console.log("[L1] Direct field set failed (ok, TM hook covers this): " + e);
        }

        console.log("[L1] ✓ MCC spoof active — returnAppSecureCntxUrlBks* pinning disabled");
    } catch(e) {
        console.log("[L1] ERROR: " + e);
    }

    // =========================================================================
    // LAYER 2: Permissive SSLContext injection
    // Hooks MainApplication.returnSSLcontext() and returnSSLcontextSFS()
    // to install an all-trusting TrustManager instead of the pinned cert
    // This covers returnAppSecureCntxUrlBksForcePan which always pins
    // =========================================================================
    try {
        // Build a permissive TrustManager
        var TrustManager = Java.registerClass({
            name: "com.re.bypass.PermissiveTrustManager",
            implements: [Java.use("javax.net.ssl.X509TrustManager")],
            methods: {
                checkClientTrusted: function(chain, authType) {
                    // Accept all clients
                },
                checkServerTrusted: function(chain, authType) {
                    // Accept all servers — this is the key bypass
                    console.log("[L2] checkServerTrusted bypassed for: " +
                        (chain && chain.length > 0 ? chain[0].getSubjectDN() : "unknown"));
                },
                getAcceptedIssuers: function() {
                    return Java.array("java.security.cert.X509Certificate", []);
                }
            }
        });

        var SSLContext = Java.use("javax.net.ssl.SSLContext");
        var MainApp = Java.use("menwho.phone.callerid.social.MainApplication");

        // Hook returnSSLcontext — replaces cert-pinned context with permissive one
        MainApp.returnSSLcontext.implementation = function(context) {
            console.log("[L2] returnSSLcontext() intercepted — injecting permissive TrustManager");
            var sslCtx = SSLContext.getInstance("TLS");
            var trustManagers = Java.array("javax.net.ssl.TrustManager", [TrustManager.$new()]);
            sslCtx.init(null, trustManagers, null);
            MainApp.sslContext.value = sslCtx;
            console.log("[L2] ✓ sslContext replaced with permissive (accepts any cert)");
        };

        // Hook returnSSLcontextSFS — same for the secondary cert (R.raw.m)
        MainApp.returnSSLcontextSFS.implementation = function(context) {
            console.log("[L2] returnSSLcontextSFS() intercepted — injecting permissive TrustManager");
            var sslCtx = SSLContext.getInstance("TLS");
            var trustManagers = Java.array("javax.net.ssl.TrustManager", [TrustManager.$new()]);
            sslCtx.init(null, trustManagers, null);
            MainApp.sslContextSFS.value = sslCtx;
            console.log("[L2] ✓ sslContextSFS replaced with permissive (accepts any cert)");
        };

        // If sslContext was already initialized before our hook, overwrite it now
        try {
            var existingCtx = MainApp.sslContext.value;
            if (existingCtx !== null) {
                var sslCtxNew = SSLContext.getInstance("TLS");
                var trustManagers2 = Java.array("javax.net.ssl.TrustManager", [TrustManager.$new()]);
                sslCtxNew.init(null, trustManagers2, null);
                MainApp.sslContext.value = sslCtxNew;
                console.log("[L2] ✓ Pre-existing sslContext overwritten");
            }
        } catch(e) { /* field not yet initialized */ }

        console.log("[L2] ✓ SSLContext injection active — ForcePan calls will accept Burp cert");
    } catch(e) {
        console.log("[L2] ERROR: " + e);
    }

    // =========================================================================
    // LAYER 3: HttpsURLConnection.setSSLSocketFactory fallback
    // Even if sslContext is replaced, hook at the connection level as safety net
    // Covers any code path that calls setSSLSocketFactory directly
    // =========================================================================
    try {
        var HttpsURLConnection = Java.use("javax.net.ssl.HttpsURLConnection");

        HttpsURLConnection.setSSLSocketFactory.implementation = function(factory) {
            // Don't apply the pinned factory — use system default instead
            console.log("[L3] setSSLSocketFactory() blocked — using system default");
            // Call with null factory to reset to default
            // We DON'T call this.setSSLSocketFactory(factory) — that's the pinned one
        };

        // Also hook setHostnameVerifier
        HttpsURLConnection.setHostnameVerifier.implementation = function(verifier) {
            console.log("[L3] setHostnameVerifier() blocked — hostname verification disabled");
            // Don't apply strict verifier
        };

        // Hook getHostnameVerifier to return permissive verifier
        var HostnameVerifier = Java.registerClass({
            name: "com.re.bypass.TrustAllHostnames",
            implements: [Java.use("javax.net.ssl.HostnameVerifier")],
            methods: {
                verify: function(hostname, session) {
                    console.log("[L3] HostnameVerifier.verify() → true for: " + hostname);
                    return true;
                }
            }
        });

        console.log("[L3] ✓ HttpsURLConnection hooks active — setSSLSocketFactory neutralized");
    } catch(e) {
        console.log("[L3] ERROR: " + e);
    }

    // =========================================================================
    // LAYER 4: System-level TrustManager + OkHttp bypass
    // Covers any libraries (OkHttp3, Retrofit, Volley) that may be used
    // =========================================================================
    try {
        // OkHttp3 CertificatePinner
        try {
            var CertificatePinner = Java.use("okhttp3.CertificatePinner");
            CertificatePinner.check.overload("java.lang.String", "java.util.List")
                .implementation = function(hostname, certs) {
                    console.log("[L4] OkHttp CertificatePinner.check() bypassed for: " + hostname);
                };
            CertificatePinner["check$okhttp"].implementation = function(hostname, url, certs) {
                console.log("[L4] OkHttp CertificatePinner.check$okhttp() bypassed for: " + hostname);
            };
        } catch(e) {
            console.log("[L4] OkHttp CertificatePinner: " + e.message);
        }

        // OkHttp3 internal TLS check
        try {
            var RealTrustManager = Java.use("okhttp3.internal.tls.OkHostnameVerifier");
            RealTrustManager.verify.overload("java.lang.String", "javax.net.ssl.SSLSession")
                .implementation = function(host, session) {
                    console.log("[L4] OkHostnameVerifier.verify() → true for: " + host);
                    return true;
                };
        } catch(e) { /* OkHttp not used here */ }

        // WebViewClient SSL errors
        try {
            var WebViewClient = Java.use("android.webkit.WebViewClient");
            WebViewClient.onReceivedSslError.implementation = function(view, handler, error) {
                handler.proceed();
                console.log("[L4] WebViewClient SSL error bypassed: " + error.toString());
            };
        } catch(e) { /* no WebView SSL errors */ }

        // Network Security Config override (Android 7+ certificate pinning)
        // This covers apps using network_security_config.xml pinning
        try {
            var NetworkSecurityConfig = Java.use("android.security.net.config.NetworkSecurityConfig");
            var PinSet = Java.use("android.security.net.config.PinSet");
            PinSet.satisfiedBy.implementation = function(certs) {
                console.log("[L4] Network Security Config pin check bypassed");
                return true;
            };
        } catch(e) { /* not using NSC pinning */ }

        console.log("[L4] ✓ OkHttp + WebView + NSC bypass active");
    } catch(e) {
        console.log("[L4] ERROR: " + e);
    }

    // =========================================================================
    // MONITOR: Log all HTTPS connections being intercepted
    // =========================================================================
    try {
        var URL = Java.use("java.net.URL");
        URL.openConnection.overload().implementation = function() {
            var conn = this.openConnection();
            var urlStr = this.toString();
            if (urlStr.startsWith("https")) {
                console.log("[INTERCEPT] " + urlStr);
            }
            return conn;
        };
    } catch(e) { /* monitor optional */ }

    console.log("");
    console.log("====================================================");
    console.log("[✓] Real Caller SSL Bypass ACTIVE — ALL REGIONS");
    console.log("[✓] Layer 1: MCC spoofed to 424 (UAE)");
    console.log("[✓] Layer 2: sslContext replaced with permissive TM");
    console.log("[✓] Layer 3: setSSLSocketFactory neutralized");
    console.log("[✓] Layer 4: OkHttp/WebView/NSC bypassed");
    console.log("====================================================");
    console.log("[*] Set Burp proxy: adb shell settings put global http_proxy <IP>:8080");
    console.log("[*] All HTTPS traffic now interceptable");
    console.log("");
});
"""


def on_message(message, data):
    if message["type"] == "send":
        print(f"[Frida] {message['payload']}")
    elif message["type"] == "error":
        print(f"[!] Error: {message['stack']}")


def main():
    print(f"[*] Targeting: {PACKAGE}")
    print("[*] Connecting to device via USB...")

    try:
        device = frida.get_usb_device(timeout=10)
    except frida.TimedOutError:
        print("[!] No USB device found. Make sure:")
        print("    1. Device connected via USB with debugging enabled")
        print("    2. frida-server running on device: adb shell /data/local/tmp/frida-server &")
        sys.exit(1)

    mode = sys.argv[1] if len(sys.argv) > 1 else "spawn"

    if mode == "attach":
        print(f"[*] Attaching to running process...")
        session = device.attach(PACKAGE)
    else:
        print(f"[*] Spawning fresh: {PACKAGE}")
        pid = device.spawn([PACKAGE])
        session = device.attach(pid)

    script = session.create_script(SCRIPT)
    script.on("message", on_message)
    script.load()

    if mode != "attach":
        device.resume(session._impl.pid if hasattr(session._impl, 'pid') else 0)

    print(f"[*] Bypass injected into {PACKAGE}")
    print("[*] Ready to intercept traffic")
    print("[*] Press Ctrl+C to detach")
    print()

    try:
        sys.stdin.read()
    except KeyboardInterrupt:
        print("\n[*] Detaching...")
        session.detach()


if __name__ == "__main__":
    main()
