import 'dart:convert';
import 'dart:io';

import '../models.dart';

/// Which analysis backend the app is configured to talk to.
enum BackendMode {
  /// Seeded results, served locally by [DemoSkinAnalysisService] — no
  /// network. The judging fallback: always works, always honest about
  /// being demo data.
  demo,

  /// The real backend proxy (`backend/server.js`) over HTTP, selected with
  /// `--dart-define=SKINSERIES_LIVE=true` at build time.
  live,
}

/// App-level configuration for the backend proxy.
class AppConfig {
  const AppConfig({
    this.backendBaseUrl = defaultBackendBaseUrl,
    this.mode = BackendMode.demo,
  });

  /// Android emulator loopback to the machine running the backend proxy;
  /// the shipped value points at luci on the home LAN for phone testing.
  static const String defaultBackendBaseUrl = 'http://192.168.1.223:8787';

  /// Whether this build was compiled with `--dart-define=SKINSERIES_LIVE=true`.
  static const bool liveBuild = bool.fromEnvironment('SKINSERIES_LIVE');

  /// Backend URL override from `--dart-define=SKINSERIES_BACKEND_URL=...`.
  static const String _envBackendBaseUrl =
      String.fromEnvironment('SKINSERIES_BACKEND_URL');

  /// The build-time configuration: live mode and the env backend URL when
  /// the dart-defines are passed, demo mode with the default URL otherwise.
  factory AppConfig.fromEnvironment() => AppConfig(
        backendBaseUrl:
            _envBackendBaseUrl.isEmpty ? defaultBackendBaseUrl : _envBackendBaseUrl,
        mode: liveBuild ? BackendMode.live : BackendMode.demo,
      );

  final String backendBaseUrl;
  final BackendMode mode;
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
  ///
  /// When [imageBase64] is provided it is the photo to analyze (base64-encoded
  /// JPEG/PNG, [contentType] its MIME type) and [stage] is bookkeeping only.
  /// Without an image, live backends are asked for the stage's result through
  /// the backend's demo-stage contract — which a live-mode backend refuses
  /// with a clear error (see [LiveSkinAnalysisService]).
  Future<ScanResult> analyze({
    required String stage,
    String? imageBase64,
    String? contentType,
  });
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
  Future<ScanResult> analyze({
    required String stage,
    String? imageBase64,
    String? contentType,
  }) async {
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

/// Talks to the backend proxy (`backend/server.js`) using its real contract:
///
/// * With a photo: `POST /api/scans {"imageBase64": ...}` -> `{taskId}`,
///   then `GET /api/scans/<taskId>` until `{status: "complete", result}`.
/// * Without a photo: `POST /api/scans {"demoStage": stage}` -> the stage's
///   seeded result, served only while the backend itself runs in demo mode.
///   A live-mode backend answers 400 with an explanatory message, surfaced
///   here as a [ScanException] — no result is ever faked client-side.
///
/// Any backend error body (`{"errorCode": ..., "message": ...}`, including
/// the 422 simulated-coaching errors) becomes a [ScanException] carrying the
/// backend's own code and message.
class LiveSkinAnalysisService implements SkinAnalysisService {
  LiveSkinAnalysisService({AppConfig config = const AppConfig()})
      : _config = config;

  final AppConfig _config;

  @override
  Future<ScanResult> analyze({
    required String stage,
    String? imageBase64,
    String? contentType,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('${_config.backendBaseUrl}/api/scans');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (imageBase64 != null) {
        request.write(jsonEncode(<String, dynamic>{
          'imageBase64': imageBase64,
          if (contentType != null) 'contentType': contentType,
        }));
      } else {
        request.write(jsonEncode(<String, dynamic>{'demoStage': stage}));
      }
      final response = await request.close();
      final decoded = _asMap(await utf8.decoder.bind(response).join());
      _throwIfError(decoded);

      if (decoded['status'] == 'complete' && decoded['result'] is Map) {
        return ScanResult.fromJson(
          Map<String, dynamic>.from(decoded['result'] as Map),
        );
      }
      final taskId = decoded['taskId'] as String?;
      if (taskId == null) {
        throw const ScanException(
          'error_server',
          'Backend response had neither a result nor a task id.',
        );
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
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final request = await client.getUrl(uri);
      final response = await request.close();
      final decoded = _asMap(await utf8.decoder.bind(response).join());
      _throwIfError(decoded);

      if (decoded['status'] == 'complete' && decoded['result'] is Map) {
        return ScanResult.fromJson(
          Map<String, dynamic>.from(decoded['result'] as Map),
        );
      }
      if (decoded['status'] == 'error') {
        throw const ScanException('error_analysis_failed');
      }
      // status == 'running' (or anything unrecognized): keep polling.
    }
    throw const ScanException('error_timeout');
  }

  /// The backend reports failures as a JSON body with an `errorCode`,
  /// on 4xx responses and inside 200 poll responses alike.
  void _throwIfError(Map<String, dynamic> decoded) {
    final errorCode = decoded['errorCode'] as String?;
    if (errorCode != null) {
      throw ScanException(errorCode, decoded['message'] as String?);
    }
  }

  Map<String, dynamic> _asMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }
}
