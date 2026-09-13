import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/offline_video_cipher.dart';

/// Deterministic-length pseudo-random plaintext. The content only has to be
/// non-uniform; it is never used as key material.
Uint8List _plaintext(int length, {int seed = 7}) {
  final random = Random(seed);
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late OfflineVideoCipher cipher;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('offline_cipher_test');
    cipher = OfflineVideoCipher();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File file(String name) => File('${tempDir.path}/$name');

  Future<File> writePlain(String name, Uint8List bytes) async {
    final f = file(name);
    await f.writeAsBytes(bytes);
    return f;
  }

  group('round trip', () {
    test('encrypt then decrypt returns the original bytes', () async {
      final original = _plaintext(4096);
      final source = await writePlain('source.mp4', original);
      final encrypted = file('source.enc');
      final restored = file('restored.mp4');

      await cipher.encryptFile(
        source: source,
        destination: encrypted,
        videoId: 'course1_chapter1',
      );

      expect(await cipher.isSecureContainer(encrypted), isTrue);
      // The container must not contain the plaintext verbatim.
      final cipherBytes = await encrypted.readAsBytes();
      expect(cipherBytes.length, greaterThan(original.length));

      await cipher.decryptFile(
        source: encrypted,
        destination: restored,
        videoId: 'course1_chapter1',
      );

      expect(await restored.readAsBytes(), equals(original));
    });

    test('an empty source round trips', () async {
      final source = await writePlain('empty.mp4', Uint8List(0));
      final encrypted = file('empty.enc');
      final restored = file('empty_out.mp4');

      await cipher.encryptFile(
        source: source,
        destination: encrypted,
        videoId: 'course1_chapter2',
      );
      await cipher.decryptFile(
        source: encrypted,
        destination: restored,
        videoId: 'course1_chapter2',
      );

      expect(await restored.length(), 0);
    });

    test('a multi-frame file round trips and reports progress', () async {
      // Four frames plus a partial one, so frame indexing and the final-frame
      // flag are both exercised.
      const chunk = 1024;
      final original = _plaintext(chunk * 4 + 137);
      final source = await writePlain('big.mp4', original);
      final encrypted = file('big.enc');
      final restored = file('big_out.mp4');

      var lastProcessed = 0;
      await cipher.encryptFile(
        source: source,
        destination: encrypted,
        videoId: 'course2_chapter9',
        chunkSize: chunk,
        onProgress: (processed, total) {
          expect(processed, greaterThanOrEqualTo(lastProcessed));
          expect(total, original.length);
          lastProcessed = processed;
        },
      );
      expect(lastProcessed, original.length);

      await cipher.decryptFile(
        source: encrypted,
        destination: restored,
        videoId: 'course2_chapter9',
      );

      expect(await restored.readAsBytes(), equals(original));
    });
  });

  group('nonce and key uniqueness', () {
    test('encrypting the same input twice yields different containers',
        () async {
      final original = _plaintext(2048);
      final source = await writePlain('same.mp4', original);
      final first = file('first.enc');
      final second = file('second.enc');

      await cipher.encryptFile(
        source: source,
        destination: first,
        videoId: 'course1_chapter1',
      );
      await cipher.encryptFile(
        source: source,
        destination: second,
        videoId: 'course1_chapter1',
      );

      final a = await first.readAsBytes();
      final b = await second.readAsBytes();

      expect(a.length, b.length);
      // Different salt and nonce prefix means the ciphertext differs even for
      // an identical plaintext, video id and installation.
      expect(a, isNot(equals(b)));
    });
  });

  group('rejection', () {
    late Uint8List original;
    late File encrypted;

    setUp(() async {
      original = _plaintext(3000);
      final source = await writePlain('reject_source.mp4', original);
      encrypted = file('reject.enc');
      await cipher.encryptFile(
        source: source,
        destination: encrypted,
        videoId: 'course3_chapter3',
        chunkSize: 1024,
      );
    });

    test('a different video id fails authentication', () async {
      await expectLater(
        cipher.decryptFile(
          source: encrypted,
          destination: file('out.mp4'),
          videoId: 'course3_chapter4',
        ),
        throwsA(isA<OfflineCipherException>()),
      );
      expect(await file('out.mp4').exists(), isFalse);
    });

    test('a file from another installation fails authentication', () async {
      // A fresh keystore stands in for a different install.
      FlutterSecureStorage.setMockInitialValues({});
      final otherInstall = OfflineVideoCipher();

      await expectLater(
        otherInstall.decryptFile(
          source: encrypted,
          destination: file('other.mp4'),
          videoId: 'course3_chapter3',
        ),
        throwsA(isA<OfflineCipherException>()),
      );
    });

    test('a flipped ciphertext byte is detected', () async {
      final bytes = await encrypted.readAsBytes();
      // Somewhere inside the first frame's ciphertext, past the header.
      bytes[60] = bytes[60] ^ 0xFF;
      final tampered = await writePlain('tampered.enc', bytes);

      await expectLater(
        cipher.decryptFile(
          source: tampered,
          destination: file('tampered_out.mp4'),
          videoId: 'course3_chapter3',
        ),
        throwsA(isA<OfflineCipherException>()),
      );
    });

    test('a flipped authentication tag byte is detected', () async {
      final bytes = await encrypted.readAsBytes();
      // The last 16 bytes of the file are the final frame's GCM tag.
      bytes[bytes.length - 1] = bytes[bytes.length - 1] ^ 0x01;
      final tampered = await writePlain('badtag.enc', bytes);

      await expectLater(
        cipher.decryptFile(
          source: tampered,
          destination: file('badtag_out.mp4'),
          videoId: 'course3_chapter3',
        ),
        throwsA(isA<OfflineCipherException>()),
      );
    });

    test('a truncated file is rejected rather than partially played', () async {
      final bytes = await encrypted.readAsBytes();
      final truncated = await writePlain(
        'truncated.enc',
        Uint8List.fromList(bytes.sublist(0, bytes.length - 40)),
      );

      await expectLater(
        cipher.decryptFile(
          source: truncated,
          destination: file('truncated_out.mp4'),
          videoId: 'course3_chapter3',
        ),
        throwsA(isA<OfflineCipherException>()),
      );
      expect(await file('truncated_out.mp4').exists(), isFalse);
    });

    test('a legacy file without the magic is not treated as secure', () async {
      // What the old XOR scheme produced: raw bytes, no header.
      final legacy = await writePlain('legacy.enc', _plaintext(500));

      expect(await cipher.isSecureContainer(legacy), isFalse);
      await expectLater(
        cipher.decryptFile(
          source: legacy,
          destination: file('legacy_out.mp4'),
          videoId: 'course3_chapter3',
        ),
        throwsA(isA<OfflineCipherException>()),
      );
    });
  });

  group('interrupted work', () {
    test('a leftover .part file is not mistaken for the output', () async {
      final encrypted = file('interrupted.enc');
      final partial = File('${encrypted.path}.part');
      await partial.writeAsBytes(_plaintext(64));

      expect(await encrypted.exists(), isFalse);
      await cipher.discardPartial(encrypted);
      expect(await partial.exists(), isFalse);
    });

    test('encryption replaces an existing destination atomically', () async {
      final original = _plaintext(1500);
      final source = await writePlain('replace.mp4', original);
      final encrypted = file('replace.enc');

      await cipher.encryptFile(
        source: source,
        destination: encrypted,
        videoId: 'course4_chapter1',
      );
      final firstSize = await encrypted.length();

      await cipher.encryptFile(
        source: source,
        destination: encrypted,
        videoId: 'course4_chapter1',
      );

      expect(await encrypted.length(), firstSize);
      expect(await File('${encrypted.path}.part').exists(), isFalse);

      final restored = file('replace_out.mp4');
      await cipher.decryptFile(
        source: encrypted,
        destination: restored,
        videoId: 'course4_chapter1',
      );
      expect(await restored.readAsBytes(), equals(original));
    });
  });

  group('installation secret', () {
    test('is 32 bytes and stable across calls', () async {
      final first = await cipher.installSecret();
      cipher.forgetCachedSecret();
      final second = await cipher.installSecret();

      expect(first.length, 32);
      expect(second, equals(first));
    });

    test('is not stored in plaintext form', () async {
      final secret = await cipher.installSecret();
      final stored = await const FlutterSecureStorage().readAll();

      expect(stored, isNotEmpty);
      // The keystore holds base64, never the raw bytes as a string.
      expect(stored.values.any((v) => v.contains(String.fromCharCodes(secret))),
          isFalse);
    });
  });
}
