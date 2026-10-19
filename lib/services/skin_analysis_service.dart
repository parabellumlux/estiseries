import 'dart:convert';
import 'dart:io';

import '../models.dart';

/// App-level configuration for the backend proxy.
class AppConfig {
  const AppConfig({this.backendBaseUrl = defaultBackendBaseUrl});

  /// Android emulator loopback to the machine running the backend proxy.
  static const String defaultBackendBaseUrl = 'http://192.168.1.223:8787';

  final String backendBaseUrl;
}

/// A failed analysis, carrying a YouCam-style error code
/// (e.g. `error_lighting_dark`).
class ScanException implements Exception {
  const ScanException(this.errorCode, [this.message]);

  final String errorCode;
  final String? message;

  @override
  String toString() =>
      'ScanException($errorCode${message == null ? '' : ': $message'})';
}

/// Runs a skin analysis for a series stage and returns the scored result.
abstract class SkinAnalysisService {
  /// Analyzes the scan for [stage] (`baseline`, `session3`, `session6`, ...).
  Future<ScanResult> analyze({required String stage});
}

/// Returns the seeded scan for the requested stage after a short delay.
class DemoSkinAnalysisService implements SkinAnalysisService {
  DemoSkinAnalysisService(
    List<SkinScan> scans, {
    this.delay = const Duration(milliseconds: 400),
  }) : _byStage = {for (final scan in scans) scan.stage: scan};

  /// Simulated analysis latency.
  final Duration delay;

  final Map<String, SkinScan> _byStage;

  @override
  Future<ScanResult> analyze({required String stage}) async {
    await Future<void>.delayed(delay);
    final scan = _byStage[stage];
    if (scan == null) {
      throw ScanException(
        'error_invalid_stage',
        'No seeded scan for stage "$stage".',
      );
    }
    return scan.result;
  }
}

/// Talks to the backend proxy's real, asynchronous flow:
/// `POST /api/scans` -> `GET /api/scans/<taskId>` until the result is ready.
///
/// NOT exercised in this build — no YouCam API key exists yet, so nothing in
/// the app instantiates this class. It is real code waiting on configuration
/// (`YOUCAM_API_KEY` on the backend); deliberately left untested here.
class LiveSkinAnalysisService implements SkinAnalysisService {
  LiveSkinAnalysisService({AppConfig config = const AppConfig()})
      : _config = config;

  final AppConfig _config;

  @override
  Future<ScanResult> analyze({required String stage}) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('${_config.backendBaseUrl}/api/scans');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, dynamic>{'stage': stage}));
      final response = await request.close();
      final decoded = _asMap(await utf8.decoder.bind(response).join());

      if (response.statusCode == 200 && decoded.containsKey('scores')) {
        return ScanResult.fromJson(decoded);
      }
      if (response.statusCode >= 400) {
        throw ScanException(
          decoded['errorCode'] as String? ?? 'error_server',
          decoded['message'] as String?,
        );
      }

      final taskId = decoded['taskId'] as String?;
      if (taskId == null) {
        throw const ScanException('error_server', 'Missing task id.');
      }
      return await _pollForResult(client, taskId);
    } on ScanException {
      rethrow;
    } on SocketException {
      throw const ScanException('error_network');
    } on HttpException {
      throw const ScanException('error_network');
    } on FormatException {
      throw const ScanException('error_server');
    } finally {
      client.close(force: true);
    }
  }

  Future<ScanResult> _pollForResult(HttpClient client, String taskId) async {
    final uri = Uri.parse('${_config.backendBaseUrl}/api/scans/$taskId');
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final request = await client.getUrl(uri);
      final response = await request.close();
      final decoded = _asMap(await utf8.decoder.bind(response).join());

      if (response.statusCode >= 400) {
        throw ScanException(
          decoded['errorCode'] as String? ?? 'error_server',
          decoded['message'] as String?,
        );
      }
      if (response.statusCode == 200 && decoded.containsKey('scores')) {
        return ScanResult.fromJson(decoded);
      }
      final status = decoded['status'] as String?;
      if (status == 'failed' || status == 'error') {
        throw ScanException(
          decoded['errorCode'] as String? ?? 'error_analysis_failed',
          decoded['message'] as String?,
        );
      }
    }
    throw const ScanException('error_timeout');
  }

  Map<String, dynamic> _asMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }
}
