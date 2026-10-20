# Tester verification — 20 October 2026

Linux AppImage SHA-256: f24e6ae7f0c09849fbf6be9d8b95857eb679c6a1a7aa7ca048348f4b7e7407e5

The exact AppImage passed package integrity checks, clean-profile ZIP/header import, invalid-ROM preservation, relaunch, duplicate-profile rejection, and power-on to the English opening at frame 3905 without loading a native savestate. A private Xvfb GUI test exercised the ROM picker, keyboard Start/A, S report capture, D description dialog, held-key protection, F6 paired save, X hide, F7 restore, and clean exit. Tests used dummy audio and extraction mode; physical gamepads, hardware audio, and normal FUSE mounting were not certified.

The packaged Windows launcher ran using embedded Windows Python under Wine and prepared a private profile. The actual custom Windows core and packaged overlay reached the English opening from power-on at frame 3906, with native masking and batched glyph APIs checked. These checks do not certify native Windows 10/11, gamepads, audio, the ROM picker, or the Windows PowerShell bug-description dialog. Those remain tester tasks.

These are runtime/package checks, not full-route completion or linguistic approval. Full Sunday, alternate branches, study interactions, every long-name consumer, and the remaining translation need work. Current user saves and the prior installed AppImage are preserved.

Final Windows ZIP SHA-256: 0d59737cdc384b91bf20733da3ff8be257e90931237242c2ed3a3529235feecc

The final Windows manifest also passed under embedded Windows Python in Wine: headered ZIP import, invalid-ROM rejection preserving the imported ROM and name profile, relaunch, duplicate-profile locking, and custom-core preservation after the opening boot.

## Return-home branch follow-up

The Lua runtime and Linux core were matched by SHA-256 to the published AppImage, then tested from a captured Sunday return-home checkpoint. Yes, No, and Cancel passed: complete English question/response, native choice display, held-A protection, and paired checkpoint restore. The question after loading was also visually inspected.

After acknowledging the English, tested native-reader completion waits were 0–30 emulated frames. The Yes response took 22 frames; the earlier slow-reader experiment took 506. This does not establish every dialogue case or physical display pacing. This check used the released Linux runtime; it adds no Windows branch certification and is not a continuous whole-Sunday playthrough. Evidence is attached to the release as `Gokinjo-English-Test-2026-10-20-RETURN-STUDY-CHECK.json`.
