# Mobile Security Rules

**These rules apply to mobile applications built with React Native.** Mobile apps have unique security considerations around local storage, network communication, and platform-specific security features.

## Quick Reference

- **Secure Storage**: Never use AsyncStorage for secrets, use react-native-keychain or expo-secure-store
- **Certificate Pinning**: Implement SSL pinning for all API connections
- **Deep Links**: Validate and sanitize all deep link parameters
- **Biometrics**: Provide fallback to PIN/password, store keys in secure hardware
- **Platform Security**: Configure ATS (iOS) and Network Security Config (Android)
- **Release Security**: Enable ProGuard/R8, disable debug logging, remove dev tools
- **Device Security**: Detect jailbreak/root for sensitive apps
- **Clipboard**: Clear clipboard after sensitive data, prevent copying CVV/full card numbers
- **Screenshots**: Prevent screenshots on sensitive screens

## 1. Secure Storage

**NEVER** store secrets, tokens, or credentials in AsyncStorage.

### Storage Security Levels

| Storage | Security | Use For |
|---------|----------|---------|
| react-native-keychain | High | Auth tokens, credentials, API keys |
| expo-secure-store | High | Auth tokens, credentials, API keys |
| MMKV (encrypted) | Medium | User preferences with sensitive data |
| AsyncStorage | Low | Non-sensitive data only |

### Secure Storage Patterns

```typescript
// CORRECT: Using react-native-keychain
import * as Keychain from 'react-native-keychain';

await Keychain.setGenericPassword(username, password, {
  accessible: Keychain.ACCESSIBLE.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
  securityLevel: Keychain.SECURITY_LEVEL.SECURE_HARDWARE
});

// CORRECT: Using expo-secure-store
import * as SecureStore from 'expo-secure-store';

await SecureStore.setItemAsync('token', token, {
  keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY
});

// WRONG: Storing tokens in AsyncStorage
await AsyncStorage.setItem('authToken', token); // NEVER for sensitive data
```

## 2. Certificate Pinning

**IMPLEMENT** certificate pinning for all API connections to protect against MITM attacks.

### Implementation

```typescript
import { fetch as sslFetch } from 'react-native-ssl-pinning';

const response = await sslFetch(endpoint, {
  sslPinning: { certs: ['cert1', 'cert2'] },
  timeoutInterval: 10000
});
```

## 3. Deep Link Validation

**VALIDATE** all deep link parameters before use.

### Safe Deep Link Handling

```typescript
const ALLOWED_PATHS = [/^\/product\/[a-zA-Z0-9-]+$/, /^\/user\/profile$/] as const;

function validateDeepLink(url: string): boolean {
  const parsed = new URL(url);
  if (!['myapp', 'https'].includes(parsed.protocol.replace(':', ''))) return false;
  if (parsed.protocol === 'https:' && parsed.host !== 'app.example.com') return false;
  return ALLOWED_PATHS.some(pattern => pattern.test(parsed.pathname));
}
```

## 4. Biometric Authentication

**PROVIDE** fallback to PIN/password, store keys in secure hardware.

```typescript
import * as LocalAuthentication from 'expo-local-authentication';

const result = await LocalAuthentication.authenticateAsync({
  promptMessage: 'Authenticate to continue',
  fallbackLabel: 'Use passcode',
  disableDeviceFallback: false
});
```

## 5. Platform-Level Network Security

### iOS - App Transport Security (ATS)

Configure in `ios/YourApp/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <false/>
</dict>
```

### Android - Network Security Config

Create `android/app/src/main/res/xml/network_security_config.xml`:

```xml
<network-security-config>
  <base-config cleartextTrafficPermitted="false">
    <trust-anchors>
      <certificates src="system"/>
    </trust-anchors>
  </base-config>
</network-security-config>
```

## 6. Code Obfuscation & Release Security

**ENABLE** ProGuard/R8 for Android, **DISABLE** debug logging in production.

### Android ProGuard

```groovy
android {
  buildTypes {
    release {
      minifyEnabled true
      shrinkResources true
    }
  }
}
```

### Debug Logging Prevention

```typescript
const isProduction = !__DEV__;

const logger = {
  log: (...args) => { if (!isProduction) console.log(...args); },
  error: (...args) => { if (isProduction) reportError(args); else console.error(...args); }
};
```

## 7. Jailbreak/Root Detection

**REQUIRED** for Banking/Finance and Healthcare apps, **RECOMMENDED** for Enterprise/MDM.

```typescript
import JailMonkey from 'jail-monkey';

if (JailMonkey.isJailBroken()) {
  handleCompromisedDevice(['Device is jailbroken/rooted']);
}
```

## 8. Secure Clipboard Handling

**CLEAR** clipboard after pasting sensitive data, **PREVENT** copying CVV/full card numbers.

```typescript
import Clipboard from '@react-native-clipboard/clipboard';

Clipboard.setString(text);
setTimeout(() => Clipboard.setString(''), 30000); // Clear after 30s
```

## 9. Screenshot Prevention

Prevent screenshots of sensitive screens (payment, banking, etc.).

```typescript
function usePreventScreenshot(shouldPrevent: boolean) {
  useEffect(() => {
    if (shouldPrevent && Platform.OS === 'android') {
      NativeModules.ScreenshotPrevention?.enable();
    }
    return () => {
      if (Platform.OS === 'android') {
        NativeModules.ScreenshotPrevention?.disable();
      }
    };
  }, [shouldPrevent]);
}
```

## See Also

- `.claude/rules/security-core.md` - Core security practices (always applies)
- `.claude/rules/security.md` - Platform-specific security rules (OWASP Top 10)
- `.cursor/rules/security-mobile.mdc` - Full rule with comprehensive examples
