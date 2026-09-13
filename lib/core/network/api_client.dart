import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../session/session_manager.dart';
import 'api_constants.dart';
import 'api_exception.dart';

/// One HTTP client for the whole app, mirroring `src/lib/api.ts`.
///
/// Every request carries `Accept`, `Authorization` and — the piece that was
/// missing everywhere — the `lang` header, so the backend returns Arabic or
/// English content to match the app's locale exactly like the web dashboard.
///
/// A 401 clears the session and fires [onUnauthorized] once, unless the call
/// opts out with `skipAuthRedirect`. That opt-out matters: several endpoints
/// answer 403/401 as a *business* rule (chapter view limits, exhausted quiz
/// attempts, a wrong OTP), and signing the student out on those would be wrong.
class ApiClient {
  ApiClient._internal();
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  static const Duration _timeout = Duration(seconds: 30);

  final SessionManager _session = SessionManager();

  /// Current UI locale, sent as the `lang` header. Kept in sync by the app root.
  static String locale = 'ar';

  /// Invoked once when a request is rejected with 401 and the session is
  /// dropped. The app root wires this to "return to login".
  static VoidCallback? onUnauthorized;

  bool _handlingUnauthorized = false;

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = ApiConstants.baseUrl.endsWith('/')
        ? ApiConstants.baseUrl.substring(0, ApiConstants.baseUrl.length - 1)
        : ApiConstants.baseUrl;
    final clean = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$clean');

    if (query == null || query.isEmpty) return uri;

    final params = <String, String>{...uri.queryParameters};
    query.forEach((key, value) {
      if (value == null) return;
      final s = value.toString();
      if (s.isEmpty) return;
      params[key] = s;
    });
    return uri.replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<Map<String, String>> _headers({
    bool includeAuth = true,
    bool isMultipart = false,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'lang': locale,
    };

    if (!isMultipart) {
      headers['Content-Type'] = 'application/json';
    }

    if (includeAuth) {
      final token = await _session.currentToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  void _fireUnauthorized() {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    _session.clear().whenComplete(() {
      onUnauthorized?.call();
      _handlingUnauthorized = false;
    });
  }

  /// Decodes the body, throwing [ApiException] on any non-2xx status.
  dynamic _handle(
    http.Response response, {
    required bool skipAuthRedirect,
    String fallback = 'Request failed',
  }) {
    final status = response.statusCode;

    if (status >= 200 && status < 300) {
      if (status == 204 || response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return null;
      }
    }

    if (status == 401 && !skipAuthRedirect) {
      _fireUnauthorized();
    }

    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = null;
      }
    }

    throw ApiException.fromBody(status, body, fallback: fallback);
  }

  Never _rethrowTransport(Object error) {
    if (error is ApiException) throw error;
    if (error is SocketException) {
      throw ApiException(0, 'No internet connection');
    }
    if (error is HttpException || error is FormatException) {
      throw ApiException(0, 'Bad response from server');
    }
    throw ApiException(0, error.toString());
  }

  // ------------------------------------------------------------------
  // Verbs
  // ------------------------------------------------------------------

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool includeAuth = true,
    bool skipAuthRedirect = false,
    String fallback = 'Request failed',
  }) async {
    try {
      final response = await http
          .get(_uri(path, query),
              headers: await _headers(includeAuth: includeAuth))
          .timeout(_timeout);
      return _handle(response,
          skipAuthRedirect: skipAuthRedirect, fallback: fallback);
    } catch (e) {
      _rethrowTransport(e);
    }
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool includeAuth = true,
    bool skipAuthRedirect = false,
    String fallback = 'Request failed',
  }) async {
    try {
      final response = await http
          .post(
            _uri(path, query),
            headers: await _headers(includeAuth: includeAuth),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(_timeout);
      return _handle(response,
          skipAuthRedirect: skipAuthRedirect, fallback: fallback);
    } catch (e) {
      _rethrowTransport(e);
    }
  }

  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool includeAuth = true,
    bool skipAuthRedirect = false,
    String fallback = 'Request failed',
  }) async {
    try {
      final response = await http
          .put(
            _uri(path, query),
            headers: await _headers(includeAuth: includeAuth),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(_timeout);
      return _handle(response,
          skipAuthRedirect: skipAuthRedirect, fallback: fallback);
    } catch (e) {
      _rethrowTransport(e);
    }
  }

  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool includeAuth = true,
    bool skipAuthRedirect = false,
    String fallback = 'Request failed',
  }) async {
    try {
      final response = await http
          .delete(
            _uri(path, query),
            headers: await _headers(includeAuth: includeAuth),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(_timeout);
      return _handle(response,
          skipAuthRedirect: skipAuthRedirect, fallback: fallback);
    } catch (e) {
      _rethrowTransport(e);
    }
  }

  /// Multipart upload. [files] maps a form field name to a local file path;
  /// [rawFiles] carries in-memory bytes (recorded audio, captured frames).
  Future<dynamic> multipart(
    String path, {
    String method = 'POST',
    Map<String, dynamic> fields = const {},
    Map<String, String> files = const {},
    List<MultipartUpload> rawFiles = const [],
    bool skipAuthRedirect = false,
    String fallback = 'Upload failed',
  }) async {
    try {
      final request = http.MultipartRequest(method, _uri(path));
      request.headers.addAll(await _headers(isMultipart: true));

      fields.forEach((key, value) {
        if (value == null) return;
        request.fields[key] = value.toString();
      });

      for (final entry in files.entries) {
        request.files.add(
          await http.MultipartFile.fromPath(
            entry.key,
            entry.value,
            contentType: _contentTypeForPath(entry.value),
          ),
        );
      }

      for (final upload in rawFiles) {
        request.files.add(
          http.MultipartFile.fromBytes(
            upload.field,
            upload.bytes,
            filename: upload.filename,
            contentType: upload.contentType,
          ),
        );
      }

      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      return _handle(response,
          skipAuthRedirect: skipAuthRedirect, fallback: fallback);
    } catch (e) {
      _rethrowTransport(e);
    }
  }

  MediaType? _contentTypeForPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
        return MediaType('image', 'heic');
      case 'm4a':
        return MediaType('audio', 'm4a');
      case 'aac':
        return MediaType('audio', 'aac');
      case 'mp3':
        return MediaType('audio', 'mpeg');
      case 'wav':
        return MediaType('audio', 'wav');
      case 'webm':
        return MediaType('audio', 'webm');
      case 'pdf':
        return MediaType('application', 'pdf');
      default:
        return null;
    }
  }
}

/// An in-memory file for [ApiClient.multipart].
class MultipartUpload {
  const MultipartUpload({
    required this.field,
    required this.bytes,
    required this.filename,
    this.contentType,
  });

  final String field;
  final List<int> bytes;
  final String filename;
  final MediaType? contentType;
}

// ---------------------------------------------------------------------------
// Payload helpers
// ---------------------------------------------------------------------------

/// Unwraps the JSON:API envelope. Handles `{data: ...}`, `{data: {data: ...}}`
/// and a bare payload, matching how the web normalizers read every list.
dynamic unwrapData(dynamic payload) {
  if (payload is Map) {
    final data = payload['data'];
    if (data is Map && data['data'] != null) return data['data'];
    if (data != null) return data;
  }
  return payload;
}

/// Unwraps to a list, tolerating single-object payloads.
List<dynamic> unwrapList(dynamic payload) {
  final data = unwrapData(payload);
  if (data is List) return data;
  if (data is Map) return [data];
  return const [];
}

/// Unwraps to a map, or `null`.
Map<String, dynamic>? unwrapMap(dynamic payload) {
  final data = unwrapData(payload);
  if (data is Map) return Map<String, dynamic>.from(data);
  return null;
}

/// Reads `meta` off a list response (pagination).
Map<String, dynamic>? readMeta(dynamic payload) {
  if (payload is Map && payload['meta'] is Map) {
    return Map<String, dynamic>.from(payload['meta'] as Map);
  }
  return null;
}
