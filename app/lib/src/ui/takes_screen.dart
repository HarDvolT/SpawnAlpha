import 'package:flutter/material.dart';

import '../app.dart';
import '../theme/theme.dart';
import 'home_screen.dart';

/// Every take, newest first. In-app playback is still to come: opening a
/// take shows its file (in Explorer on Windows).
class TakesScreen extends StatelessWidget {
  const TakesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    final p = SaTheme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Takes', style: Theme.of(context).textTheme.headlineMedium)),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final takes = [
            for (final s in library.scripts)
              for (var i = 0; i < s.takes.length; i++) (script: s, take: s.takes[i], number: i + 1),
          ]..sort((a, b) => b.take.recordedAt.compareTo(a.take.recordedAt));
          if (takes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(SaSpace.s6),
                child: Text(
                  'Your takes appear here after you record. They stay on this device.',
                  textAlign: TextAlign.center,
                  style: SaType.body.copyWith(color: p.ink2),
                ),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(SaSpace.s4),
            child: Wrap(
              spacing: SaSpace.s3,
              runSpacing: SaSpace.s4,
              children: [for (final t in takes) TakeThumb(script: t.script, take: t.take, number: t.number)],
            ),
          );
        },
      ),
    );
  }
}
