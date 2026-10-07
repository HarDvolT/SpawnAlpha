import 'dart:convert';
import 'dart:io';

import '../model/mark.dart';
import '../review/publishing_text.dart';

/// Explicit local saves use fresh owned folders. No video or prior text changes.
class PublishingStore {
  const PublishingStore(this.directory);
  final Directory directory;
  Future<Directory> save(PublishingText draft) async {
    await directory.create(recursive: true);
    final name = 'publishing-${newId()}';
    final temporary = Directory(
      '${directory.path}${Platform.pathSeparator}$name.tmp',
    );
    final finished = Directory(
      '${directory.path}${Platform.pathSeparator}$name',
    );
    if (await temporary.exists() || await finished.exists()) {
      throw const FileSystemException('Fresh text folder unavailable');
    }
    await temporary.create();
    try {
      Future<void> write(String name, String text) =>
          File('${temporary.path}${Platform.pathSeparator}$name')
              .writeAsString(text, flush: true);
      await write('title.txt', draft.title);
      await write('description.txt', draft.description);
      await write('chapters.txt', draft.chapterText);
      await write('publishing.txt', draft.combined);
      await write('publishing.json', jsonEncode(draft.toJson()));
      return await temporary.rename(finished.path);
    } on Object {
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        /* Preserve any failed cleanup for retry. */
      }
      rethrow;
    }
  }
}
