# Gokinjo Boukentai English overlay

An English translation project for **Gokinjo Boukentai**, running through a modified version of MesenCE. The emulator displays English in place of the Japanese text, with extra pages when a translation needs more room. It also supports longer names and lets you report untranslated text or bugs while you play.

**[Download the preview](https://github.com/Littlemac123/gokinjo-english-overlay/releases)** · **[Join the Discord](https://discord.gg/eRmexKmxvZ)** · **[Support on Ko-fi](https://ko-fi.com/little_mac)**

The preview is free. You'll need your own original Japanese ROM; it isn't included.

## How far along is it?

This is an early, incomplete preview. It includes English for parts of the opening and selected Sunday scenes, including the pendant, God, and some battle dialogue. Plenty of dialogue, menus, graphics, credits, and study screens are still Japanese. You can't play the whole game in English yet, and the full Sunday section isn't ready.

The current build has 152 dialogue entries and 9 timed cinematic entries, alongside menu and interface work. Those counts aren't a percentage of the game. Existing translations are still being checked against the Japanese and may change.

The aim is faithful, natural, uncensored English, keeping the original tone, jokes, and character voices. Text won't be shortened just to fit a box; longer translations can use more pages. Brief translator notes will be added only where context needs explaining.

## Getting started

Download a build from [Releases](https://github.com/Littlemac123/gokinjo-english-overlay/releases):

- **Linux x86_64:** make the AppImage executable and open it. Tested on Linux Mint / Ubuntu 24.04; older distributions haven't been checked. If FUSE gives you trouble, run it with `--appimage-extract-and-run`.
- **Windows x64:** extract the entire ZIP, then run `Start-English.bat`. It targets Windows 10/11. Launching and the English opening have been tested under Wine, but testing on a real Windows machine is still needed, including audio, gamepads, and the bug-description dialog.

On first launch, choose your original Japanese `.sfc`, `.smc`, or `.zip`. The launcher checks for the matching original ROM and won't accept a patched copy.

## Controls and saves

| Key | Action |
| --- | --- |
| Arrow keys | Move / choose |
| Space | A / advance text |
| A | B / back |
| Enter | Start |
| X | Hide / show English |
| F6 | Save the game and overlay state together |
| F7 | Load that save |
| S | Report untranslated text |
| D | Report a bug and enter a description |

For a controller, open **Mesen Settings → Input → SNES**.

Use **F6 and F7** for saves that also remember your English reading position and long names. Mesen's normal savestates alone don't keep all of that information. Back up your whole save/profile folder.

## Feedback

Found Japanese text or something broken? Press **S** for untranslated text or **D** for a bug. Reports save a screenshot and savestate so the problem can be investigated later.

[Join the Discord](https://discord.gg/eRmexKmxvZ) to share feedback and follow the project. Check your reports before sharing them, and don't upload ROMs or your entire private profile folder.

## Working on the code

- `emulator/` — modified MesenCE 2.2.1 source, including Japanese text masking, English glyph rendering, and Windows build fixes.
- `overlay/` — Lua dialogue, menus, timed scenes, and report capture.
- `launcher/` — Linux and Windows launchers and report dialogs.
- `tools/` — Windows core cross-build helper.

See the [build notes](docs/BUILD.md) and [test results and limitations](docs/VERIFICATION.md). This repository contains the source used for the tester preview; development ROMs, personal saves, and reports are excluded.

## Support and credits

If you'd like to support development, here's my [Ko-fi](https://ko-fi.com/little_mac). The preview stays free; donations support the project and don't purchase the original game.

MesenCE is GPL-3.0. The overlay and launchers are GPL-3.0-or-later. See [LICENSE](LICENSE), `licenses/`, and the notices in `emulator/` for details and third-party licenses.

This is an unofficial fan project, with no affiliation to the game's rights holders. The game and its original assets belong to their respective owners.
