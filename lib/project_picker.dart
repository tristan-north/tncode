import 'package:material_ui/material_ui.dart';

import 'notes.dart';
import 'paths.dart';
import 'theme.dart';

/// The name of the project that is open, which opens a menu of every
/// project.
class ProjectPicker extends StatelessWidget {
  const ProjectPicker({
    super.key,
    required this.projects,
    required this.current,
    required this.notes,
    required this.onSelected,
  });

  /// Every project, by its directory.
  final List<String> projects;

  /// The directory of the project that is open.
  final String current;

  /// Each project in the menu says how many of its notes are to do.
  final Notes notes;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: PopupMenuButton<String>(
        tooltip: 'Open another project',
        position: PopupMenuPosition.under,
        color: colors.surfaceBright,
        constraints: const BoxConstraints.tightFor(width: 340),
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final project in projects)
            PopupMenuItem(
              value: project,
              height: 34,
              child: Row(
                children: [
                  // A long name leaves some room for its directory.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      projectName(project),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle.copyWith(
                        fontSize: 12,
                        fontWeight: project == current
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: projectColor(project),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      shortenHome(project),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (notes.openCount(project) > 0) ...[
                    const SizedBox(width: 10),
                    Text(
                      '${notes.openCount(project)} to do',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  projectName(current),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(
                    fontSize: 12,
                    color: projectColor(current),
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
