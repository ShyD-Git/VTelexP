# RuntimeInspector

Generic dynamic analysis dylib for iOS. 
Dumps Objective-C runtime classes, methods, properties, and interesting strings
directly to the app's Documents directory. 

- Target: iOS 16.3.1, no jailbreak
- Injection: TrollFools v4.3 (TrollStore)
- Build: GitHub Actions macOS runner, clang arm64, ad-hoc codesign
- No Theos, no substrate, no interpose.

---

## 1. Build the Dylib

1. Create a **public** repo (public repos have unlimited Action minutes).
2. Upload exactly 3 files, keeping this structure:
