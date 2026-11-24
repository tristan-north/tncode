import 'package:material_ui/material_ui.dart';

import 'paths.dart';
import 'sessions.dart';
import 'theme.dart';

/// The bar along the bottom, with a button for each of [sessions].
class SessionBar extends StatelessWidget {
  const SessionBar({
    super.key,
    required this.sessions,
    required this.current,
    required this.onSelected,
  });

  final List<SessionInfo> sessions;

  /// The path of the session that is open.
  final String? current;
  final ValueChanged<SessionInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          for (final (i, session) in sessions.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _SessionButton(
                session: session,
                active: session.path == current,
                onPressed: () => onSelected(session),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A button on the session bar: the session's project, in a pill of the
/// project's colour, above the session's title. It is filled in when its
/// session is the one shown.
class _SessionButton extends StatelessWidget {
  const _SessionButton({
    required this.session,
    required this.active,
    required this.onPressed,
  });

  final SessionInfo session;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = projectColor(session.projectDir);
    return Tooltip(
      message: '${session.title}\n${shortenHome(session.projectDir)}',
      child: Builder(
        builder: (context) => OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: active
                ? colors.onSurface
                : colors.onSurfaceVariant,
            backgroundColor: active ? color.withValues(alpha: 0.16) : null,
            side: BorderSide(
              color: active
                  ? color.withValues(alpha: 0.7)
                  : colors.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            // The compact density of a desktop would take the padding above
            // and below away.
            visualDensity: VisualDensity.standard,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          // The buttons share the bar's width equally, and each one's text
          // starts at its left edge.
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: ShapeDecoration(
                    color: color,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    projectName(session.projectDir),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.surface,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
