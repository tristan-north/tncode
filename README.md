# tncode

A Linux desktop viewer for Claude Code sessions. It reads the transcripts
under `~/.claude/projects` (or `$CLAUDE_CONFIG_DIR/projects`) and shows the
latest prompts of one session, with Claude's replies, and follows the session
as it is written to.

- The bar along the bottom offers the sessions with the latest messages, and
  the project name at the top of the sidebar opens the latest session of
  another project.
- Selecting text in a reply, or clicking two words with Shift held, opens a
  box to comment on it. A reply's comments are copied together, to paste back
  to Claude.
- The sidebar keeps to-do notes for each project, in
  `~/.local/share/tncode/notes.json`.

Run it with:

    flutter run -d linux

The command line options are listed in `lib/launch.dart`, and are printed when
an argument is not understood. `AGENTS.md` describes how to take a screenshot
of the app and how to drive it without a window.

## Code

| File | What is in it |
|---|---|
| `lib/main.dart` | The app |
| `lib/launch.dart` | The command line, and screenshots |
| `lib/theme.dart` | Colours and text styles |
| `lib/paths.dart` | Where things are kept on disk |
| `lib/sessions.dart` | Reading the transcripts |
| `lib/session_controller.dart` | Which session is open and what of it is shown |
| `lib/home_page.dart` | The page: top bar, search, the list of exchanges |
| `lib/entry_widgets.dart` | The messages, tool calls and other entries of an exchange |
| `lib/markdown.dart` | The text of a reply |
| `lib/annotations.dart` | The comments on a reply's text |
| `lib/annotation_highlights.dart`, `lib/annotation_layer.dart` | Highlighting the text that is commented on, and the box to comment in |
| `lib/session_bar.dart`, `lib/project_picker.dart` | Picking a session or a project |
| `lib/notes.dart`, `lib/notes_sidebar.dart`, `lib/note_row.dart` | The to-do notes, their sidebar and a note in it |
