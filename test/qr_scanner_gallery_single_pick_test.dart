import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _body(String source, String start, String end) {
  final s = source.indexOf(start);
  expect(s, greaterThanOrEqualTo(0), reason: 'missing $start');
  final e = source.indexOf(end, s + start.length);
  expect(e, greaterThan(s), reason: 'missing $end after $start');
  return source.substring(s, e);
}

void main() {
  test('scanner picks a single image instantly without a confirm step', () {
    final scanner = _read('lib/src/qr_code_scanner_page.dart');
    expect(
      scanner.contains('AppGalleryPicker.pickSingleImageInstant(context)'),
      isTrue,
    );
    expect(
      scanner.contains('AppGalleryPicker.pickSingleImage(context)'),
      isFalse,
    );
  });

  test('instant picker routes to the system single-select API', () {
    final gallery = _read('lib/src/services/app_gallery_picker.dart');
    final instant = _body(
      gallery,
      'static Future<File?> pickSingleImageInstant(',
      '\n  }\n',
    );
    expect(instant.contains('SystemMediaPicker.pickSingleImage()'), isTrue);

    final system = _read('lib/src/services/system_media_picker.dart');
    final single = _body(
      system,
      'static Future<PickedMedia?> pickSingleImage()',
      'static Future<List<PickedMedia>> pickImages(',
    );
    expect(single.contains('pickImage('), isTrue);
    expect(single.contains('ImageSource.gallery'), isTrue);
    expect(single.contains('allowMultiple: false'), isTrue);
    expect(single.contains('pickMultipleMedia'), isFalse);
  });

  test('other single-image entry points keep the multi-select picker', () {
    const callers = <String>[
      'lib/src/create_group.dart',
      'lib/src/group_info_detail.dart',
      'lib/src/services/chat_background_service.dart',
      'lib/src/pages/moments/moments_cover_picker.dart',
      'lib/src/my_profile_detail.dart',
    ];
    for (final path in callers) {
      final source = _read(path);
      expect(
        source.contains('AppGalleryPicker.pickSingleImage(context)'),
        isTrue,
        reason: path,
      );
      expect(
        source.contains('pickSingleImageInstant'),
        isFalse,
        reason: path,
      );
    }
  });
}
