import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/services/encrypted_video_service.dart';

/// These cover the three pure rules behind the iOS offline-download fixes.
///
/// * a download is found again after the app container moves (iOS gives the
///   app a new random container directory on every install and update, so the
///   absolute path recorded at download time dangles),
/// * a backend id can never produce a file name that escapes the video
///   directory or that a file system rejects,
/// * a cleartext lecture URL is upgraded on iOS, where App Transport Security
///   refuses it outright, and left alone on Android, which works today.
void main() {
  group('resolving a download after the app container moves', () {
    test('a POSIX path reduces to its file name', () {
      expect(
        DownloadedVideo.fileNameFromPath(
          '/var/mobile/Containers/Data/Application/OLD-UUID/Documents'
          '/.learnoo_videos/video_12_34.enc',
        ),
        'video_12_34.enc',
      );
    });

    test('a Windows-style path reduces to its file name', () {
      expect(
        DownloadedVideo.fileNameFromPath(r'C:\app\.learnoo_videos\video_1_2.enc'),
        'video_1_2.enc',
      );
    });

    test('a bare file name is returned unchanged', () {
      expect(DownloadedVideo.fileNameFromPath('video_1_2.enc'), 'video_1_2.enc');
    });

    test('trailing separators do not swallow the name', () {
      expect(DownloadedVideo.fileNameFromPath('/a/b/video.enc/'), 'video.enc');
    });

    test('an empty or separator-only path yields nothing', () {
      expect(DownloadedVideo.fileNameFromPath(''), '');
      expect(DownloadedVideo.fileNameFromPath('///'), '');
    });

    test('metadata written before the file-name field still resolves', () {
      final video = DownloadedVideo.fromJson({
        'id': 'c1_ch1',
        'chapterId': 'ch1',
        'chapterTitle': 'Chapter 1',
        'lectureTitle': 'Lecture 1',
        'courseId': 'c1',
        'originalUrl': 'https://api.learnoo.app/video.mp4',
        'encryptedFilePath':
            '/var/mobile/Containers/Data/Application/OLD/Documents'
                '/.learnoo_videos/video_c1_ch1.enc',
        'thumbnailUrl': '',
        'fileSize': 1024,
        'duration': '10:00',
        'downloadDate': '2026-01-01T00:00:00.000Z',
        'encryptionKey': '',
        'encryptionNonce': '',
        'encryptionVersion': 2,
      });

      expect(video.storedFileName, 'video_c1_ch1.enc');
    });

    test('the file name survives a JSON round trip', () {
      final video = DownloadedVideo(
        id: 'c1_ch1',
        chapterId: 'ch1',
        chapterTitle: 'Chapter 1',
        lectureTitle: 'Lecture 1',
        courseId: 'c1',
        originalUrl: 'https://api.learnoo.app/video.mp4',
        encryptedFilePath: '/old/container/video_c1_ch1.enc',
        storedFileName: 'video_c1_ch1.enc',
        thumbnailUrl: '',
        fileSize: 1024,
        duration: '10:00',
        downloadDate: DateTime.utc(2026),
        encryptionKey: '',
      );

      final restored = DownloadedVideo.fromJson(video.toJson());

      expect(restored.storedFileName, 'video_c1_ch1.enc');
      // The absolute path is still recorded so an older build can read the
      // entry, but it is no longer what resolves the file.
      expect(restored.encryptedFilePath, '/old/container/video_c1_ch1.enc');
    });
  });

  group('storage file names', () {
    test('a plain id keeps its characters', () {
      expect(EncryptedVideoService.storageFileName('12_34'), 'video_12_34.enc');
    });

    test('a separator in the id cannot escape the video directory', () {
      expect(
        EncryptedVideoService.storageFileName('../../etc/passwd'),
        'video_______etc_passwd.enc',
      );
      expect(
        EncryptedVideoService.storageFileName('12/34'),
        'video_12_34.enc',
      );
    });

    test('characters a file system may reject are replaced', () {
      expect(
        EncryptedVideoService.storageFileName('a:b*c?d"e'),
        'video_a_b_c_d_e.enc',
      );
    });

    test('an empty id still yields a usable name', () {
      expect(EncryptedVideoService.storageFileName(''), 'video_unknown.enc');
    });

    test('an absurdly long id is capped well inside the name limit', () {
      final name = EncryptedVideoService.storageFileName('x' * 500);
      expect(name.length, lessThan(200));
      expect(name.startsWith('video_'), isTrue);
      expect(name.endsWith('.enc'), isTrue);
    });
  });

  group('cleartext lecture URLs', () {
    const cleartext = 'http://cdn.learnoo.app/storage/lecture.mp4';
    const secure = 'https://cdn.learnoo.app/storage/lecture.mp4';

    test('iOS asks for the same lecture over TLS', () {
      expect(
        EncryptedVideoService.secureVideoUrl(cleartext, isIOS: true),
        secure,
      );
      expect(
        EncryptedVideoService.isBlockedOnIOS(cleartext, isIOS: true),
        isTrue,
      );
    });

    test('Android is left exactly as it is', () {
      expect(
        EncryptedVideoService.secureVideoUrl(cleartext, isIOS: false),
        cleartext,
      );
      expect(
        EncryptedVideoService.isBlockedOnIOS(cleartext, isIOS: false),
        isFalse,
      );
    });

    test('an already-secure URL is untouched on both platforms', () {
      expect(EncryptedVideoService.secureVideoUrl(secure, isIOS: true), secure);
      expect(EncryptedVideoService.secureVideoUrl(secure, isIOS: false), secure);
      expect(EncryptedVideoService.isBlockedOnIOS(secure, isIOS: true), isFalse);
    });

    test('only the scheme changes, never the host, path or query', () {
      expect(
        EncryptedVideoService.secureVideoUrl(
          'http://a.b/c/d.m3u8?token=x&y=1',
          isIOS: true,
        ),
        'https://a.b/c/d.m3u8?token=x&y=1',
      );
    });

    test('a non-http URL is not rewritten', () {
      expect(
        EncryptedVideoService.secureVideoUrl('file:///tmp/a.mp4', isIOS: true),
        'file:///tmp/a.mp4',
      );
    });
  });
}
