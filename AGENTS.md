# Notes for agents

## Taking a headless screenshot

To check a UI change, build the app and run it through `tool/screenshot`
with the `--screenshot` flag, then read the PNG. Nothing appears on the
user's screen.

```
flutter build linux --debug
tool/screenshot --screenshot=/path/to/out.png --session=latest
```

The script starts an X display that is not shown anywhere (Xvfb), runs the
app on it and passes its arguments on. The app loads, waits until the view
has settled, writes the picture and exits. A run takes about 2 seconds.

| Flag | Effect |
|---|---|
| `--screenshot=<file.png>` | Write a picture of the app to the file, then exit |
| `--session=<id>` or `latest` | Open that session; the start of an id is enough |
| `--tools` | Start with tool calls shown |
| `--top` | Open sessions at their first message instead of their last |
| `--size=<W>x<H>` | Size of the picture, default 1540x880 |

Things to know:

- The picture is laid out at `--size` whatever size the window is, so a tall
  size such as `--size=1000x3000` shows more of a conversation in one picture.
- Exit status 1 means the app could not show what was asked for: no session
  matched, a file could not be read, or loading took more than 5 seconds.
  Status 64 means an argument was not understood. The reason is on stderr.
- The pointer is ignored in screenshot mode, so nothing is drawn hovered.
- The app reads the real sessions in `~/.claude/projects`, so `latest` is
  usually the session of the agent taking the screenshot.
- Xvfb renders in software and Mesa warns about DRI3 on stderr. That is
  expected.
- Xvfb comes from the Fedora package `xorg-x11-server-Xvfb`. Do not use
  `xvfb-run` in place of the script: it sleeps for three seconds before it
  starts the app.
- `TNCODE_BUILD=release tool/screenshot …` runs the release build, which
  takes under 1 second, but building it is slower than building debug, so
  debug is quicker when the code has just changed.
- Running the app's binary with the same flags and no script also works, but
  a window flashes on the user's desktop.

The flags are parsed in `lib/launch.dart`. To reach a state they do not cover,
add a flag there.
