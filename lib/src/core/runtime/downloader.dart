import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../util/log.dart';

/// 下载取消令牌。
class CancelToken {
  bool _canceled = false;

  bool get isCanceled => _canceled;

  void cancel() => _canceled = true;

  void throwIfCanceled() {
    if (_canceled) throw const DownloadCanceled();
  }
}

class DownloadCanceled implements Exception {
  const DownloadCanceled();

  @override
  String toString() => '下载已取消';
}

class DownloadException implements Exception {
  DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 带断点续传与大文件友好缓冲的流式下载器。
///
/// 刻意不使用额外依赖：直接基于 `dart:io` 的 [HttpClient]，
/// 这样可以完全控制代理、超时与缓冲区大小。
class Downloader {
  Downloader._();

  static const Duration _connectTimeout = Duration(seconds: 30);
  static const Duration _idleTimeout = Duration(seconds: 60);

  /// 尊重系统代理设置。国内用户经常依赖代理访问 GitHub。
  static void _applyProxy(HttpClient client) {
    final env = Platform.environment;
    String? pick(String lower, String upper) {
      final v = env[lower] ?? env[upper];
      return (v == null || v.isEmpty) ? null : v;
    }

    final httpProxy = pick('http_proxy', 'HTTP_PROXY');
    final httpsProxy = pick('https_proxy', 'HTTPS_PROXY');
    if (httpProxy == null && httpsProxy == null) {
      client.findProxy = HttpClient.findProxyFromEnvironment;
      return;
    }

    final noProxy = pick('no_proxy', 'NO_PROXY') ?? '';
    final excluded = noProxy
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    client.findProxy = (uri) {
      for (final host in excluded) {
        if (host == '*' || uri.host == host || uri.host.endsWith('.$host')) {
          return 'DIRECT';
        }
      }
      final proxy = uri.scheme == 'https' ? (httpsProxy ?? httpProxy) : (httpProxy ?? httpsProxy);
      if (proxy == null) return 'DIRECT';
      final normalized = proxy.contains('://') ? proxy : 'http://$proxy';
      return 'PROXY ${Uri.parse(normalized).authority}';
    };
  }

  static HttpClient _newClient() {
    final client = HttpClient()
      ..connectionTimeout = _connectTimeout
      ..idleTimeout = _idleTimeout
      ..userAgent = 'Upbetter/1.0';
    _applyProxy(client);
    return client;
  }

  /// 下载 [url] 到 [destination]，支持断点续传。
  ///
  /// [onProgress] 回调 `(已接收字节, 总字节或 null, 速度 B/s)`。
  /// [expectedSha256] 非空时会在完成后校验，不匹配则删除文件并抛错。
  static Future<void> download({
    required Uri url,
    required File destination,
    required CancelToken token,
    void Function(int received, int? total, double bytesPerSecond)? onProgress,
    String? expectedSha256,
    int? expectedSize,
  }) async {
    await destination.parent.create(recursive: true);
    final partFile = File('${destination.path}.part');

    var startOffset = 0;
    if (partFile.existsSync()) {
      startOffset = await partFile.length();
      // 已经完整下载过了，直接进入校验。
      if (expectedSize != null && startOffset == expectedSize) {
        await _finalize(partFile, destination, expectedSha256, expectedSize);
        onProgress?.call(startOffset, startOffset, 0);
        return;
      }
      if (expectedSize != null && startOffset > expectedSize) {
        await partFile.delete();
        startOffset = 0;
      }
    }

    final client = _newClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(url);
      if (startOffset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startOffset-');
      }
      final response = await request.close();

      // 服务器不支持续传时从头开始。
      final resumed = response.statusCode == HttpStatus.partialContent;
      if (startOffset > 0 && !resumed) {
        Log.w('Download', '服务器不支持断点续传，重新下载');
        startOffset = 0;
        if (partFile.existsSync()) await partFile.delete();
      }
      if (response.statusCode != HttpStatus.ok && !resumed) {
        throw DownloadException('服务器返回 HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      final total = contentLength > 0 ? startOffset + contentLength : null;

      sink = partFile.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );

      var received = startOffset;
      final stopwatch = Stopwatch()..start();
      var lastEmit = 0;
      onProgress?.call(received, total, 0);

      await for (final chunk in response) {
        token.throwIfCanceled();
        sink.add(chunk);
        received += chunk.length;

        // 限流通知频率，避免高频回调拖慢下载。
        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (elapsedMs >= 100) {
          final speed = elapsedMs == 0 ? 0.0 : received / (elapsedMs / 1000);
          onProgress?.call(received, total, speed);
          lastEmit = elapsedMs;
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (lastEmit == 0) onProgress?.call(received, total, 0);

      await _finalize(partFile, destination, expectedSha256, expectedSize);
    } on DownloadCanceled {
      await sink?.flush();
      await sink?.close();
      rethrow;
    } on Object catch (error) {
      await sink?.flush();
      await sink?.close();
      if (error is DownloadException) rethrow;
      throw DownloadException('下载失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _finalize(
    File partFile,
    File destination,
    String? expectedSha256,
    int? expectedSize,
  ) async {
    if (expectedSha256 != null) {
      final digest = await computeSha256(partFile);
      if (digest != expectedSha256.toLowerCase()) {
        await partFile.delete();
        throw DownloadException('文件校验失败，可能下载不完整或来源被篡改');
      }
    }
    if (expectedSize != null && await partFile.length() != expectedSize) {
      throw DownloadException('文件大小不符，下载可能不完整');
    }
    if (destination.existsSync()) await destination.delete();
    await partFile.rename(destination.path);
  }

  /// 流式计算 SHA-256，避免把整个文件读进内存。
  static Future<String> computeSha256(File file) async {
    if (!file.existsSync()) return '';
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 下载单个小文件到内存（用于清单等）。
  static Future<String> fetchText(Uri url, {CancelToken? token}) async {
    final client = _newClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw DownloadException('HTTP ${response.statusCode}');
      }
      token?.throwIfCanceled();
      return await response.transform(const SystemEncoding().decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}
