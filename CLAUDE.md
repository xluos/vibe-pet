# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
make build      # swift build -c release
make bundle     # build + assemble VibePet.app with both binaries
make run        # bundle + open the app
make sign       # ad-hoc codesign (no Developer ID)
make dmg        # create VibePet-1.0.0.dmg (requires: brew install create-dmg)
make dist       # create VibePet-1.0.0.zip
make clean      # remove .build/, VibePet.app/, *.dmg, *.zip
```

## Architecture

Two-target SPM project (Swift 5.10, macOS 14+, no external dependencies):

**VibePet** — macOS menu bar app (LSUIElement, no dock icon)
- Listens on Unix domain socket `/tmp/vibe-pet.sock` for session events
- Displays a notch-hugging NSPanel that expands on hover to show session list
- Persists sessions to `~/.vibe-pet/sessions.json`
- Plays procedurally generated chiptune sounds (no WAV files — synthesized via AVAudioEngine)

**VibePetBridge** — CLI invoked by IDE hooks
- Reads hook context JSON from stdin + environment variables
- Normalizes event names across Claude Code (PascalCase), Codex (PascalCase), and Coco (snake_case)
- Sends JSON to the main app via Unix socket, then exits
- Detects TTY by walking the process tree, detects terminal from env vars

## IPC Flow

```
IDE hook fires → VibePetBridge reads stdin → sends JSON to /tmp/vibe-pet.sock → VibePet SocketServer → SessionStore → UI update + sound
```

## Hook Integration

HookInstaller writes hooks into three different config formats on app launch:
- **Claude Code**: `~/.claude/settings.json` — JSON, event-keyed arrays with matcher/hooks structure
- **Codex**: `~/.codex/hooks.json` — same JSON format as Claude Code
- **Coco/Trae**: `~/.trae/traecli.yaml` — YAML with `hooks:` array and `matchers:` per entry

Merging is additive (never removes other tools' hooks). Creates `.vibe-pet-backup` before modifying. Install/uninstall are idempotent — safe to run multiple times.

## Key Design Decisions

- **POSIX socket over NWListener**: NWListener with TCP over Unix path caused issues; raw POSIX `socket()/bind()/listen()/accept()` is more reliable
- **Sound buffer format must match engine output**: AVAudioPlayerNode crashes if buffer channel count doesn't match `mainMixerNode.outputFormat`. Buffers are generated matching the engine's actual format.
- **Notch panel positioning**: Uses `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea` to calculate notch width. Panel is wider than the notch so content (pet icon, session count) is visible on either side.
- **Window level**: `CGShieldingWindowLevel` to render above the menu bar (`.statusBar` level renders behind it)
- **Launcher indirection**: `~/.vibe-pet/bin/vibe-pet-bridge` is a shell script that finds the real binary in the .app bundle, with mdfind fallback

## Debugging

```bash
cat /tmp/vibe-pet-bridge.log    # bridge invocations, stdin, socket sends
cat /tmp/vibe-pet-server.log    # socket server accepts, message decoding
```

Test socket manually:
```bash
python3 -c "import socket,json,time;s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.connect('/tmp/vibe-pet.sock');s.sendall((json.dumps({'sessionId':'test','hookEvent':'SessionStart','source':'claude','timestamp':time.time()})+'\n').encode());s.shutdown(socket.SHUT_WR);s.close()"
```
