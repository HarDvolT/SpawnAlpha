import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../recording/camera_bubble.dart';
import '../theme/theme.dart';

const cameraBubbleViewChannel = MethodChannel('spawnalpha/camera_bubble_view');

Future<void> runCameraBubble() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await cameraBubbleViewChannel.invokeMapMethod<Object?, Object?>(
    'ready',
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: CameraBubbleScreen(
        initial: CameraBubbleState.fromJson(state ?? {}),
      ),
    ),
  );
}

class CameraBubbleScreen extends StatefulWidget {
  const CameraBubbleScreen({super.key, required this.initial, this.preview});
  final CameraBubbleState initial;
  final Widget? preview;
  @override
  State<CameraBubbleScreen> createState() => _CameraBubbleScreenState();
}

class _CameraBubbleScreenState extends State<CameraBubbleScreen> {
  late CameraBubbleState _state = widget.initial;
  @override
  void initState() {
    super.initState();
    cameraBubbleViewChannel.setMethodCallHandler((call) async {
      if (call.method == 'update' && call.arguments is Map && mounted) {
        setState(
          () => _state = CameraBubbleState.fromJson(
            (call.arguments as Map).cast<Object?, Object?>(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    cameraBubbleViewChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SaPalette.dark, s = _state;
    return Scaffold(
      backgroundColor: p.stage,
      body: ClipOval(
        child: GestureDetector(
          onPanStart: (_) =>
              unawaited(cameraBubbleViewChannel.invokeMethod<void>('drag')),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (s.live)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: s.width.toDouble(),
                    height: s.height.toDouble(),
                    child: widget.preview ?? Texture(textureId: s.textureId),
                  ),
                )
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(SaSpace.s8),
                    child: Text(
                      'Camera starts at go',
                      textAlign: TextAlign.center,
                      style: SaType.caption.copyWith(color: p.stageText),
                    ),
                  ),
                ),
              Positioned(
                top: SaSpace.s6,
                left: SaSpace.s8,
                right: SaSpace.s8,
                child: Center(
                  child: IconButton.filledTonal(
                    tooltip: 'Hide camera preview',
                    style: IconButton.styleFrom(
                      backgroundColor: p.stageGlass,
                      foregroundColor: p.stageText,
                    ),
                    onPressed: () => unawaited(
                      cameraBubbleViewChannel.invokeMethod<void>('hide'),
                    ),
                    icon: const Icon(Icons.visibility_off_rounded),
                  ),
                ),
              ),
              Positioned(
                left: SaSpace.s8,
                right: SaSpace.s8,
                bottom: SaSpace.s6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.stageGlass,
                    borderRadius: BorderRadius.circular(SaRadius.sm),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(SaSpace.s2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hidden from recording',
                          textAlign: TextAlign.center,
                          style: SaType.caption.copyWith(color: p.stageOk),
                        ),
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(s.name)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          style: SaType.caption.copyWith(
                            color: p.stageChromeText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
