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
| `--session=<id>` or `latest` | Show only that session's prompts; the start of an id is enough |
| `--project=<name>` | Open at that project, named by its directory, such as `tncode`, instead of the one with the latest message |
| `--notes=<file>` | Keep the notes of the sidebar in this file instead of `~/.local/share/tncode/notes.json`. Give a file in a temporary directory when adding or changing notes, so that the user's own are left alone. The file need not exist |
| `--tools` | Start with tool calls shown |
| `--top` | Open at the oldest prompt shown instead of the latest |
| `--size=<W>x<H>` | Size of the picture, default 1540x880 |
| `--wait=<seconds>` | Take the picture this long after loading, to see a change to the sessions get picked up |

Things to know:

- The picture is laid out at `--size` whatever size the window is, so a tall
  size such as `--size=1000x3000` shows more prompts in one picture.
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

## Driving the app with a fake mouse and keyboard

A screenshot shows how the app opens. To check something that only happens
after input, such as selecting text, typing in a box or pressing a button,
run the app through `tool/drive`. It also runs on an X display that is not
shown anywhere.

```
flutter build linux --debug
tool/drive --top <<'END'
shot /path/to/before.png
xdotool mousemove 324 797 mousedown 1 mousemove 600 800 mousemove 936 817 mouseup 1
xdotool type 'Too much detail here'
shot /path/to/typing.png
xdotool key Return
xdotool mousemove 1115 30 click 1
shot /path/to/after.png
END
```

The arguments are the app's flags from the table above, except
`--screenshot`, which would make the app exit. Standard input is a bash
script. It runs once the app's window is up and the sessions have had 2
seconds to load, and the app is stopped when it ends. A run takes about 4
seconds plus the script.

In the script:

- `xdotool` sends the input. `DISPLAY` is already set to the hidden display.
- Each `xdotool` command is followed by a wait of 0.3 seconds, because the
  app acts on input a frame or more after it arrives. So put steps that
  depend on each other in separate commands: a click that opens a box on one
  line, the typing into it on the next. Within one command nothing waits,
  which is what a drag needs.
- `shot <file.png>` writes a picture of the window.
- The window is 1540x880 at the top left of the display, so a position in a
  picture from `shot` is the position to give `xdotool mousemove`.

How to work:

1. Run once with only a `shot`, and read the picture to find the positions
   of what you want to click or select.
2. Run again with the input, and a `shot` after each step you want to see.

Things to know:

- Each run starts the app afresh, so a script has to do every step from the
  start. Nothing carries over from the last run.
- The page shows real sessions, which change, among them the session of the
  agent doing the driving. Positions found in one run can be wrong in a
  later one. Use `--top`, which opens at the oldest prompt shown, or
  `--session=<id>` with a session that is finished, and take the positions
  from a picture made a moment before.
- If input seems to be lost, it probably arrived too early: the start of
  typed text goes missing when the box does not have the keyboard yet, and a
  click does nothing when its button is not there yet. Add a `sleep`.
- To drag, give a `mousemove` or two between `mousedown 1` and `mouseup 1`,
  as in the example. A selection needs the pointer to move while the button
  is down.
- There is no window manager on the display. The script gives the window the
  keyboard itself, so key presses arrive, but anything that depends on a
  window manager, such as maximizing, does not happen.
- To read the clipboard after a copy, there is no `xclip`. Run this in the
  script:
  `python3 -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk, Gdk; print(Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).wait_for_text())"`
- If the page is still loading in the first picture, set `TNCODE_LOAD_WAIT`
  to more seconds.
- `xdotool` and `ffmpeg`, which `shot` uses, must be installed. `Xvfb` is
  needed as for screenshots.
- Widget tests in `test/` are quicker for checking logic, but they do not
  show focus problems: `tester.enterText` gives the field the keyboard
  itself. A box that failed to take the keyboard passed its tests and was
  only caught by driving the app.
