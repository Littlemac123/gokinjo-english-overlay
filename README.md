# Gokinjo Boukentai English overlay

An unofficial, work-in-progress English overlay for **Gokinjo Boukentai (Japan)**, using a modified MesenCE emulator. English text can page independently of the original dialogue, with native text masking, longer-name support, paired checkpoints, and in-game report capture.

**[Download tester builds](https://github.com/Littlemac123/gokinjo-english-overlay/releases)** · **[Support development on Ko-fi](https://ko-fi.com/little_mac)**

This preview is free. Donations support development and do not buy the original game. Supply your own matching original Japanese ROM; no ROM is included.

## Current coverage

The current runtime contains 152 ordinary dialogue records and 9 timed cinematic records, plus interface adapters. Opening material and selected Sunday, God, pendant, and battle messages are included. Many messages, menus, graphics, credits, and study screens remain Japanese. This is an incomplete testing preview, not a completed Sunday section or a full-game translation. Existing translation fidelity review is ongoing; historical wording is not all finally approved.

Translation policy: faithful, natural, uncensored English. Preserve meaning, intensity, voice, jokes, and repetition. Solve space limits through code and paging. Translator notes should be brief, clearly labeled, and used only when needed.

## Play

- Linux x86_64: download the AppImage, make it executable, and launch. Tested on Linux Mint/Ubuntu 24.04; older distributions are not certified. If FUSE is unavailable, use `./Gokinjo-English-Test-2026-10-20-Linux-x86_64.AppImage --appimage-extract-and-run`.
- Windows x64: extract the entire ZIP and run `Start-English.bat`. Windows 10/11 is the intended target. The executable has passed an English-opening smoke test under Wine; native Windows hardware, audio, gamepads, and the PowerShell bug-description dialog still need tester confirmation.
- Select your original Japanese `.sfc`, `.smc`, or `.zip`. Modified ROMs are rejected.

Keyboard: arrows move/choose, Space advances (A), A goes back (B), Enter is Start, X hides/reveals English, F6 saves a paired checkpoint, F7 loads it. S captures untranslated text; D captures a bug and asks for a description. Configure gamepads in Mesen Settings → Input → SNES.

Keep the entire save/profile folder backed up. Paired F6/F7 checkpoints preserve English reading state and long names. Native-only savestates do not preserve all overlay state. Reports include a screenshot and savestate: inspect them before sharing; do not publicly upload ROMs or whole private profiles.

## Source

- `emulator/`: complete modified MesenCE 2.2.1 source, including the native text-mask and batched glyph renderer APIs and Windows portability fixes.
- `overlay/`: current executable Lua dialogue catalog, UI adapters, cinematic logic, and reporting code.
- `launcher/`: Linux and Windows launcher/report-dialog source.
- `tools/`: Windows core cross-build helper.

See [build notes](docs/BUILD.md) and [verification scope](docs/VERIFICATION.md). This is a curated source snapshot of the tester runtime; it excludes development ROMs, saves, personal reports, and historical experiments.

## License and attribution

MesenCE is GPL-3.0; the overlay and launchers are GPL-3.0-or-later. See LICENSE, licenses/, and the original notices retained in emulator/. Third-party components retain their own licenses. This project is unofficial and is not affiliated with the game's rights holders. The game and its original assets belong to their respective owners.
