import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Raised when an encrypted download cannot be trusted.
///
/// Every failure path that could mean tampering, truncation, a wrong key or a
/// file copied from another installation surfaces as this rather than as a
/// generic error, so callers can delete the file instead of retrying.
class OfflineCipherException implements Exception {
  const OfflineCipherException(this.reason);

  final String reason;

  @override
  String toString() => 'OfflineCipherException: $reason';
}

/// Authenticated encryption for downloaded lecture videos.
///
/// ## Format
///
/// A file is a header followed by a sequence of independently authenticated
/// frames:
///
/// ```
///   magic      7  bytes   "LNOOENC"
///   version    1  byte    kFormatVersion
///   salt      16  bytes   random, per file — HKDF salt
///   noncePrefix 8 bytes   random, per file
///   chunkSize  4  bytes   big-endian plaintext chunk size
///   ---- repeated ----
///   frameLen   4  bytes   big-endian length of the frame that follows
///   frame      n  bytes   AES-GCM ciphertext ‖ 128-bit tag
/// ```
///
/// ## Keys
///
/// A 32-byte installation secret is generated with the platform CSPRNG on
/// first use and kept in the platform keystore (Android EncryptedSharedPrefs,
/// iOS Keychain) — never in source, SharedPreferences or a plain file. The key
/// used for one file is
/// `HKDF-SHA256(installSecret, salt: fileSalt, info: "…|<videoId>")`, so every
/// download gets a distinct key and a file copied from another installation
/// derives a different key and fails authentication.
///
/// ## Nonces
///
/// Each frame is sealed under `noncePrefix ‖ frameIndex`. The prefix is random
/// per file and the index is unique within it, so a nonce is never reused under
/// a key. Because the key is itself per-file, reuse across files is impossible
/// too.
///
/// ## Integrity
///
/// Each frame carries its own GCM tag, and the associated data binds the format
/// version, the frame index, a final-frame flag and the video id. That means a
/// modified byte, a reordered frame, a frame lifted from another video, and a
/// truncated file are all rejected: the last frame of a truncated file is not
/// marked final, which [decryptFile] treats as tampering.
class OfflineVideoCipher {
  OfflineVideoCipher({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Container magic, so a legacy file can never be mistaken for this format.
  static const List<int> kMagic = [0x4C, 0x4E, 0x4F, 0x4F, 0x45, 0x4E, 0x43];

  /// Bumped whenever the container layout or crypto changes.
  static const int kFormatVersion = 2;

  static const int _saltLength = 16;
  static const int _noncePrefixLength = 8;
  static const int _frameIndexLength = 4;
  static const int _macLength = 16;
  static const int _headerLength =
      7 + 1 + _saltLength + _noncePrefixLength + 4;

  /// Plaintext bytes per frame. Large enough that the per-frame tag overhead is
  /// negligible, small enough that only one frame is ever in memory.
  static const int defaultChunkSize = 1 << 20; // 1 MiB

  /// Largest frame accepted while decrypting. Guards against a corrupted length
  /// prefix asking for a multi-gigabyte allocation.
  static const int _maxFrameLength = 16 << 20; // 16 MiB

  static const String _secretStorageKey = 'offline_video_install_secret_v2';
  static const String _hkdfInfoPrefix = 'learnoo-offline-video-v2';

  static final AesGcm _aead = AesGcm.with256bits();

  Uint8List? _cachedSecret;

  // ------------------------------------------------------------------
  // Installation secret
  // ------------------------------------------------------------------

  /// The installation secret, created on first use.
  ///
  /// Generated with [SecretKeyData.random], which draws from the platform
  /// CSPRNG. A reinstall wipes the keystore entry on iOS only if the keychain
  /// item is cleared; on Android the encrypted store is removed with the app.
  /// Either way a new secret is generated and old downloads stop decrypting,
  /// which is the correct outcome — the plaintext was never meant to outlive
  /// the install.
  Future<Uint8List> installSecret() async {
    final cached = _cachedSecret;
    if (cached != null) return cached;

    final existing = await _storage.read(key: _secretStorageKey);
    if (existing != null && existing.isNotEmpty) {
      try {
        final bytes = Uint8List.fromList(base64Decode(existing));
        if (bytes.length == 32) {
          _cachedSecret = bytes;
          return bytes;
        }
      } catch (_) {
        // Unreadable entry — fall through and mint a new one.
      }
    }

    // `SecretKeyData.random` draws from the platform CSPRNG.
    final generated =
        Uint8List.fromList(SecretKeyData.random(length: 32).bytes);
    await _storage.write(
      key: _secretStorageKey,
      value: base64Encode(generated),
    );
    _cachedSecret = generated;
    return generated;
  }

  /// Drops the in-memory copy of the secret. Used by tests and on logout.
  void forgetCachedSecret() => _cachedSecret = null;

  /// Per-file key: HKDF over the installation secret, salted with this file's
  /// own salt and bound to the video id.
  Future<SecretKey> _fileKey(Uint8List salt, String videoId) async {
    final secret = await installSecret();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: utf8.encode('$_hkdfInfoPrefix|$videoId'),
    );
  }

  // ------------------------------------------------------------------
  // Framing helpers
  // ------------------------------------------------------------------

  static Uint8List _uint32be(int value) {
    final out = Uint8List(4);
    ByteData.view(out.buffer).setUint32(0, value, Endian.big);
    return out;
  }

  static int _readUint32be(List<int> bytes, int offset) {
    return ByteData.view(Uint8List.fromList(bytes).buffer)
        .getUint32(offset, Endian.big);
  }

  /// Nonce for frame [index]: the file's random prefix followed by the index.
  static Uint8List _frameNonce(Uint8List noncePrefix, int index) {
    final nonce = Uint8List(_noncePrefixLength + _frameIndexLength);
    nonce.setRange(0, _noncePrefixLength, noncePrefix);
    nonce.setRange(_noncePrefixLength, nonce.length, _uint32be(index));
    return nonce;
  }

  /// Associated data for frame [index].
  ///
  /// Binding the version, index, final-frame flag and video id is what makes
  /// reordering, splicing between files and truncation detectable.
  static Uint8List _frameAad({
    required int index,
    required bool isFinal,
    required String videoId,
  }) {
    final id = utf8.encode(videoId);
    final aad = BytesBuilder(copy: false)
      ..addByte(kFormatVersion)
      ..add(_uint32be(index))
      ..addByte(isFinal ? 1 : 0)
      ..add(id);
    return aad.toBytes();
  }

  // ------------------------------------------------------------------
  // Encrypt
  // ------------------------------------------------------------------

  /// Encrypts [source] into [destination].
  ///
  /// The output is written to a sibling `.part` file and renamed only once the
  /// final frame is on disk, so an interrupted encryption never leaves a file
  /// that looks complete.
  Future<void> encryptFile({
    required File source,
    required File destination,
    required String videoId,
    int chunkSize = defaultChunkSize,
    void Function(int processed, int total)? onProgress,
  }) async {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be positive');
    }

    final salt =
        Uint8List.fromList(SecretKeyData.random(length: _saltLength).bytes);
    final noncePrefix = Uint8List.fromList(
      SecretKeyData.random(length: _noncePrefixLength).bytes,
    );
    final key = await _fileKey(salt, videoId);

    final total = await source.length();
    final partial = File('${destination.path}.part');

    final input = await source.open();
    final output = await partial.open(mode: FileMode.write);

    try {
      await output.writeFrom(kMagic);
      await output.writeFrom([kFormatVersion]);
      await output.writeFrom(salt);
      await output.writeFrom(noncePrefix);
      await output.writeFrom(_uint32be(chunkSize));

      var offset = 0;
      var index = 0;

      // An empty source still gets one final frame, so a zero-length file is a
      // valid container rather than a header with nothing to authenticate.
      do {
        final remaining = total - offset;
        final take = remaining > chunkSize ? chunkSize : remaining;
        final plain = take > 0 ? await input.read(take) : const <int>[];
        final isFinal = offset + plain.length >= total;

        final box = await _aead.encrypt(
          plain,
          secretKey: key,
          nonce: _frameNonce(noncePrefix, index),
          aad: _frameAad(index: index, isFinal: isFinal, videoId: videoId),
        );

        final frame = BytesBuilder(copy: false)
          ..add(box.cipherText)
          ..add(box.mac.bytes);
        final frameBytes = frame.toBytes();

        await output.writeFrom(_uint32be(frameBytes.length));
        await output.writeFrom(frameBytes);

        offset += plain.length;
        index++;
        onProgress?.call(offset, total);

        if (isFinal) break;
      } while (offset < total);
    } finally {
      await input.close();
      await output.close();
    }

    if (await destination.exists()) {
      await destination.delete();
    }
    await partial.rename(destination.path);
  }

  // ------------------------------------------------------------------
  // Decrypt
  // ------------------------------------------------------------------

  /// True when [file] is a container written by this class.
  ///
  /// Used to keep legacy downloads out of the authenticated path: a file
  /// without the magic is never treated as securely encrypted.
  Future<bool> isSecureContainer(File file) async {
    try {
      if (!await file.exists()) return false;
      if (await file.length() < _headerLength) return false;
      final handle = await file.open();
      try {
        final head = await handle.read(kMagic.length);
        for (var i = 0; i < kMagic.length; i++) {
          if (head[i] != kMagic[i]) return false;
        }
        return true;
      } finally {
        await handle.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Decrypts [source] into [destination], verifying every frame.
  ///
  /// Throws [OfflineCipherException] when the file is not a container, was
  /// written by a different installation, has been altered, or is truncated.
  /// The partially written plaintext is removed on failure so a rejected file
  /// can never be played.
  Future<void> decryptFile({
    required File source,
    required File destination,
    required String videoId,
    void Function(int processed, int total)? onProgress,
  }) async {
    final totalCipherBytes = await source.length();
    if (totalCipherBytes < _headerLength) {
      throw const OfflineCipherException('file too short to be a container');
    }

    final input = await source.open();
    RandomAccessFile? output;

    try {
      final header = await input.read(_headerLength);

      for (var i = 0; i < kMagic.length; i++) {
        if (header[i] != kMagic[i]) {
          throw const OfflineCipherException('missing container magic');
        }
      }

      final version = header[kMagic.length];
      if (version != kFormatVersion) {
        throw OfflineCipherException('unsupported format version $version');
      }

      var cursor = kMagic.length + 1;
      final salt =
          Uint8List.fromList(header.sublist(cursor, cursor + _saltLength));
      cursor += _saltLength;
      final noncePrefix = Uint8List.fromList(
        header.sublist(cursor, cursor + _noncePrefixLength),
      );
      cursor += _noncePrefixLength;
      final chunkSize = _readUint32be(header, cursor);
      if (chunkSize <= 0 || chunkSize > _maxFrameLength) {
        throw const OfflineCipherException('implausible chunk size');
      }

      final key = await _fileKey(salt, videoId);

      output = await destination.open(mode: FileMode.write);

      var index = 0;
      var produced = 0;
      var sawFinal = false;
      var position = _headerLength;

      while (position < totalCipherBytes) {
        final lengthBytes = await input.read(4);
        if (lengthBytes.length < 4) {
          throw const OfflineCipherException('truncated frame length');
        }
        position += 4;

        final frameLength = _readUint32be(lengthBytes, 0);
        if (frameLength < _macLength || frameLength > _maxFrameLength) {
          throw const OfflineCipherException('implausible frame length');
        }

        final frame = await input.read(frameLength);
        if (frame.length < frameLength) {
          throw const OfflineCipherException('truncated frame');
        }
        position += frameLength;

        final isFinal = position >= totalCipherBytes;
        final cipherText = frame.sublist(0, frame.length - _macLength);
        final mac = Mac(frame.sublist(frame.length - _macLength));

        final List<int> plain;
        try {
          plain = await _aead.decrypt(
            SecretBox(
              cipherText,
              nonce: _frameNonce(noncePrefix, index),
              mac: mac,
            ),
            secretKey: key,
            aad: _frameAad(index: index, isFinal: isFinal, videoId: videoId),
          );
        } on SecretBoxAuthenticationError {
          throw const OfflineCipherException('authentication failed');
        }

        await output.writeFrom(plain);
        produced += plain.length;
        index++;
        if (isFinal) sawFinal = true;
        onProgress?.call(produced, produced);
      }

      if (!sawFinal) {
        throw const OfflineCipherException('no final frame');
      }
    } catch (_) {
      await output?.close();
      output = null;
      if (await destination.exists()) {
        try {
          await destination.delete();
        } catch (_) {
          // Nothing useful to do; the caller treats the file as unusable.
        }
      }
      rethrow;
    } finally {
      await input.close();
      await output?.close();
    }
  }

  /// Best-effort cleanup of a `.part` file left by an interrupted encryption.
  Future<void> discardPartial(File destination) async {
    final partial = File('${destination.path}.part');
    try {
      if (await partial.exists()) await partial.delete();
    } catch (error) {
      // Not fatal — the next download overwrites it.
      debugPrint('[OfflineVideoCipher] could not remove partial file');
    }
  }
}
