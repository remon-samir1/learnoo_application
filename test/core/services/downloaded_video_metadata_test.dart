import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/encrypted_video_service.dart';
import 'package:learnoo/core/services/offline_video_cipher.dart';

/// The encryption version recorded in a download's metadata is what keeps an
/// unauthenticated legacy file from being read through the authenticated path.
/// These check the inference rules for entries written before the field
/// existed, because getting them wrong would silently downgrade security.
void main() {
  Map<String, dynamic> baseJson(Map<String, dynamic> extra) => {
        'id': 'c1_ch1',
        'chapterId': 'ch1',
        'chapterTitle': 'Chapter 1',
        'lectureTitle': 'Lecture 1',
        'courseId': 'c1',
        'originalUrl': 'https://api.learnoo.app/video.mp4',
        'encryptedFilePath': '/videos/c1_ch1.enc',
        'thumbnailUrl': '',
        'fileSize': 1024,
        'duration': '10:00',
        'downloadDate': '2026-01-01T00:00:00.000Z',
        ...extra,
      };

  test('an entry with no nonce and no version is the original XOR scheme', () {
    final video = DownloadedVideo.fromJson(
      baseJson({'encryptionKey': 'a2V5', 'encryptionNonce': ''}),
    );

    expect(video.encryptionVersion, 0);
    expect(
      video.encryptionVersion,
      lessThan(OfflineVideoCipher.kFormatVersion),
      reason: 'legacy entries must never reach the authenticated path',
    );
  });

  test('an entry with a nonce but no version is the keystream scheme', () {
    final video = DownloadedVideo.fromJson(
      baseJson({'encryptionKey': 'a2V5', 'encryptionNonce': 'bm9uY2U='}),
    );

    expect(video.encryptionVersion, 1);
    expect(video.encryptionVersion, lessThan(OfflineVideoCipher.kFormatVersion));
  });

  test('an explicit version wins over inference', () {
    final video = DownloadedVideo.fromJson(
      baseJson({
        'encryptionKey': '',
        'encryptionNonce': '',
        'encryptionVersion': OfflineVideoCipher.kFormatVersion,
      }),
    );

    expect(video.encryptionVersion, OfflineVideoCipher.kFormatVersion);
  });

  test('a version 2 entry carries no key material in its metadata', () {
    final video = DownloadedVideo.fromJson(
      baseJson({
        'encryptionKey': '',
        'encryptionNonce': '',
        'encryptionVersion': 2,
      }),
    );

    expect(video.encryptionKey, isEmpty);
    expect(video.encryptionNonce, isEmpty);
  });

  test('the round trip through JSON preserves the version', () {
    final original = DownloadedVideo.fromJson(
      baseJson({
        'encryptionKey': '',
        'encryptionNonce': '',
        'encryptionVersion': 2,
      }),
    );

    final restored = DownloadedVideo.fromJson(original.toJson());

    expect(restored.encryptionVersion, 2);
  });
}
