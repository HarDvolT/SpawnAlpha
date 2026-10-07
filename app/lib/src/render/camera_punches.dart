import '../model/cut_plan.dart';
import '../transcription/captions.dart';

class CameraPunchStep {
  CameraPunchStep(this.time, this.zoomed) {
    if (time.isNegative) throw const FormatException('Invalid camera emphasis');
  }
  final Duration time;
  final bool zoomed;
  Map<String, Object?> toJson() => {
    'timeUs': time.inMicroseconds,
    'zoomed': zoomed,
  };
  factory CameraPunchStep.fromJson(Map<String, Object?> json) {
    if (json.length != 2 || json['timeUs'] is! int || json['zoomed'] is! bool) {
      throw const FormatException('Invalid camera emphasis');
    }
    return CameraPunchStep(
      Duration(microseconds: json['timeUs']! as int),
      json['zoomed']! as bool,
    );
  }
}

class CameraPunches {
  CameraPunches(List<CameraPunchStep> steps)
    : steps = List.unmodifiable(steps) {
    if (steps.length > 20000 || steps.length.isOdd) {
      throw const FormatException('Invalid camera emphasis');
    }
    var previous = Duration.zero;
    for (final (i, step) in steps.indexed) {
      if (step.zoomed != i.isEven ||
          step.time < previous ||
          (i.isOdd && step.time == previous)) {
        throw const FormatException('Invalid camera emphasis');
      }
      previous = step.time;
    }
  }
  final List<CameraPunchStep> steps;
  int get count => steps.length ~/ 2;
  void validateClock(
    CutPlan plan, {
    required Duration minimum,
    required Duration interval,
  }) {
    if (steps.isEmpty) return;
    if (plan.sourceDuration < minimum || plan.duration < minimum) {
      throw const FormatException('Invalid camera emphasis clock');
    }
    Duration? entrance;
    for (final step in steps) {
      if (step.time > plan.duration ||
          (step.zoomed &&
              entrance != null &&
              step.time - entrance < interval)) {
        throw const FormatException('Invalid camera emphasis clock');
      }
      if (step.zoomed) entrance = step.time;
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'steps': steps.map((s) => s.toJson()).toList(),
  };
  factory CameraPunches.fromJson(Map<String, Object?> json) {
    if (json.length != 2 ||
        json['version'] != 1 ||
        json['steps'] is! List ||
        (json['steps']! as List).length > 20000) {
      throw const FormatException('Invalid camera emphasis');
    }
    return CameraPunches(
      (json['steps']! as List)
          .map(
            (s) =>
                CameraPunchStep.fromJson(Map<String, Object?>.from(s as Map)),
          )
          .toList(),
    );
  }
}

class CameraPunchPolicy {
  const CameraPunchPolicy({
    required this.minimum,
    required this.interval,
    required this.hold,
  });
  final Duration minimum, interval, hold;
}

/// Input phrases carry already verified frozen-source cue identity. No text
/// enters the resulting track and no face detection or performance score occurs.
CameraPunches cameraPunchesOnCut(
  CutPlan plan,
  List<Caption> phrases,
  CameraPunchPolicy policy, {
  Duration? cameraDuration,
}) {
  if (policy.minimum <= Duration.zero ||
      policy.interval <= Duration.zero ||
      policy.hold.isNegative) {
    throw const FormatException('Invalid camera emphasis policy');
  }
  final available = cameraDuration ?? plan.sourceDuration;
  if (available > plan.sourceDuration || available.isNegative) {
    throw const FormatException('Invalid camera duration');
  }
  if (available < policy.minimum || plan.duration < policy.minimum) {
    return CameraPunches(const []);
  }
  final windows = <(Duration, Duration)>[];
  var output = Duration.zero;
  Duration? sourceEnd;
  for (final range in plan.ranges) {
    final end = range.end < available ? range.end : available;
    if (end > range.start) {
      final windowEnd = output + end - range.start;
      if (windows.isNotEmpty &&
          windows.last.$2 == output &&
          sourceEnd == range.start) {
        final old = windows.removeLast();
        windows.add((old.$1, windowEnd));
      } else {
        windows.add((output, windowEnd));
      }
      sourceEnd = end;
    }
    output += range.duration;
  }
  final retained = windows.fold(Duration.zero, (sum, w) => sum + w.$2 - w.$1);
  if (retained < policy.minimum) return CameraPunches(const []);
  final steps = <CameraPunchStep>[];
  Duration? last;
  var boundary = 0;
  for (final phrase in phrases) {
    for (final word in phrase.words) {
      if (!word.cue.stress ||
          (last != null && word.start - last < policy.interval)) {
        continue;
      }
      while (boundary < windows.length && windows[boundary].$2 <= word.start) {
        boundary++;
      }
      if (boundary == windows.length ||
          word.start < windows[boundary].$1 ||
          word.end > windows[boundary].$2) {
        continue;
      }
      var end = word.end + policy.hold;
      if (end > windows[boundary].$2) end = windows[boundary].$2;
      // Long emphasized wording can outlast an interval. Never overlap crops.
      if (steps.isNotEmpty && steps.last.time > word.start) continue;
      steps.addAll([
        CameraPunchStep(word.start, true),
        CameraPunchStep(end, false),
      ]);
      if (steps.length > 20000) {
        throw const FormatException('Too much camera emphasis');
      }
      last = word.start;
    }
  }
  return CameraPunches(steps);
}
