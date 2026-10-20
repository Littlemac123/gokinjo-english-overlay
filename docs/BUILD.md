# Build notes

MesenCE base: https://github.com/nesdev-org/MesenCE at `20ba206cef5ba207c21203176d02cb9f43dda9fb` (2.2.1). The full modified tree is supplied; it is authoritative.

## Linux

Use the upstream emulator/COMPILING.md or emulator/README.md for frontend/toolchain prerequisites. From emulator/, build the native core with `make core -j2 LTO=false`. The tester uses the upstream 2.2.1 frontend with our modified libMesenCore.so. The Linux release also bundles its exact Linux core source and notices inside the AppImage.

The Linux launcher expects an AppDir layout: launcher/linux/* under usr/bin/, overlay/* under usr/share/gokinjo/, Mesen frontend and native core under their matching upstream runtime layout, plus a manifest in usr/share/gokinjo/. Its manifest records SHA-256 hashes of the packaged payload. Extract the published AppImage with --appimage-extract to inspect the exact tested layout and bundled runtime libraries. Retain the separate writable user data directory.

## Windows cross-build from Linux

Install Python 3, and extract llvm-mingw 20261006 ucrt Ubuntu-22.04 x86_64 (download URL and hash in download-provenance.json). DirectXMath headers and Wine natupnp declarations are included in emulator/windows-sdk and emulator/Windows with their original notices. Their portability changes resolve SDK include casing, UTF-8 file constructors, and the unused-parameter macro without changing emulation behavior.

From the repository root:

```sh
python3 tools/build_windows_core.py --toolchain /path/to/llvm-mingw-20261006-ucrt-ubuntu-22.04-x86_64 --output build/windows/MesenCore.dll --jobs 3
```

Delete build/windows/objects before rebuilding after changing headers or compiler flags. The helper caches objects using source timestamps only.

Use the official Mesen 2.2.1 Windows frontend (provenance JSON). Put Mesen.exe, the custom MesenCore.dll, and llvm-mingw libc++.dll/libunwind.dll/libwinpthread-1.dll in emulator/. Copy launcher/windows/* to the package root and overlay/* into overlay/. Supply the official CPython 3.12.10 x64 embedded distribution in python/ (including its license), and preserve all third-party notices.

The launcher requires manifest.json with release_id and a files map of package-relative forward-slash paths to SHA-256 values for every regular file except manifest.json itself. Generate it only after staging is complete. The published ZIP is a working layout reference. The launcher protects the required custom core from replacement by the frontend's embedded stock core.

No ROM, user profile, or report belongs in either package. Test a clean private profile before distribution. Native Windows testing remains necessary even when Wine passes.
