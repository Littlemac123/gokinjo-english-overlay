# Tester verification — 20 October 2026

Linux AppImage SHA-256: f24e6ae7f0c09849fbf6be9d8b95857eb679c6a1a7aa7ca048348f4b7e7407e5

The exact AppImage passed package integrity checks, clean-profile ZIP/header import, invalid-ROM preservation, relaunch, duplicate-profile rejection, and power-on to the English opening at frame 3905 without loading a native savestate. A private Xvfb GUI test exercised the ROM picker, keyboard Start/A, S report capture, D description dialog, held-key protection, F6 paired save, X hide, F7 restore, and clean exit. Tests used dummy audio and extraction mode; physical gamepads, hardware audio, and normal FUSE mounting were not certified.

The packaged Windows launcher ran using embedded Windows Python under Wine and prepared a private profile. The actual custom Windows core and packaged overlay reached the English opening from power-on at frame 3906, with native masking and batched glyph APIs checked. These checks do not certify native Windows 10/11, gamepads, audio, the ROM picker, or the Windows PowerShell bug-description dialog. Those remain tester tasks.

These are runtime/package checks, not full-route completion or linguistic approval. Full Sunday, alternate branches, study interactions, every long-name consumer, and the remaining translation need work. Current user saves and the prior installed AppImage are preserved.
