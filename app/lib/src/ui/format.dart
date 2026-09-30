import 'package:flutter/material.dart';

import '../model/coaching_style.dart';
import '../model/script_document.dart';
import '../prompter/delivery_timeline.dart';

/// "1:05", or "1:02:05" past an hour.
String formatDuration(Duration d) {
  final seconds = d.inSeconds;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// How long a read-through takes at the style's pace, with the accepted
/// marks.
Duration estimatedDuration(ScriptDocument script) => DeliveryTimeline.build(
      script.tokens,
      script.marks.where((m) => m.accepted).toList(),
      script.style,
    ).total;

IconData styleIcon(CoachingStyle style) => switch (style) {
      CoachingStyle.shortSocial => Icons.bolt_outlined,
      CoachingStyle.presentation => Icons.co_present_outlined,
      CoachingStyle.tutorial => Icons.school_outlined,
    };

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}
