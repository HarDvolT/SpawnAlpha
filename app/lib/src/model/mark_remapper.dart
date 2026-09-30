import 'dart:typed_data';

import 'mark.dart';
import 'token.dart';

/// Above this many cells the middle of the diff is not aligned, and marks
/// in it are dropped. It keeps a whole-script paste from stalling the UI.
const _maxDiffCells = 4000000;

/// Maps each token of [before] to the index of the same word in [after],
/// or null when the word was removed or changed.
///
/// Words are compared by their normalized form, so adding punctuation to a
/// word keeps its marks. Unchanged runs at both ends are matched directly,
/// and the edited middle is aligned with a longest common subsequence.
List<int?> alignTokens(List<Token> before, List<Token> after) {
  final map = List<int?>.filled(before.length, null);
  var head = 0;
  while (head < before.length && head < after.length && before[head].bare == after[head].bare) {
    map[head] = head;
    head++;
  }
  var tail = 0;
  while (tail < before.length - head &&
      tail < after.length - head &&
      before[before.length - 1 - tail].bare == after[after.length - 1 - tail].bare) {
    map[before.length - 1 - tail] = after.length - 1 - tail;
    tail++;
  }

  final n = before.length - head - tail;
  final m = after.length - head - tail;
  if (n == 0 || m == 0 || n * m > _maxDiffCells) return map;

  // lengths[i][j] = LCS length of before[head+i..] and after[head+j..].
  final width = m + 1;
  final lengths = Uint32List((n + 1) * width);
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lengths[i * width + j] = before[head + i].bare == after[head + j].bare
          ? lengths[(i + 1) * width + j + 1] + 1
          : _max(lengths[(i + 1) * width + j], lengths[i * width + j + 1]);
    }
  }
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (before[head + i].bare == after[head + j].bare) {
      map[head + i] = head + j;
      i++;
      j++;
    } else if (lengths[(i + 1) * width + j] >= lengths[i * width + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return map;
}

int _max(int a, int b) => a > b ? a : b;

/// Moves [marks] to new token indices using [map] from [alignTokens].
///
/// A gap mark is dropped when the word before it is gone. A span shrinks to
/// the words of it that survived and is dropped when none did.
List<Mark> remapMarks(List<Mark> marks, List<int?> map) {
  final result = <Mark>[];
  for (final mark in marks) {
    if (mark.end >= map.length) continue;
    if (mark.kind.isGap) {
      final after = map[mark.end];
      if (after != null) result.add(mark.copyWith(start: after, end: after));
      continue;
    }
    int? first;
    int? last;
    for (var i = mark.start; i <= mark.end; i++) {
      final target = map[i];
      if (target == null) continue;
      first ??= target;
      last = target;
    }
    if (first != null && last != null && first <= last) {
      result.add(mark.copyWith(start: first, end: last));
    }
  }
  return result;
}
