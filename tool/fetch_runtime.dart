// 开发期工具：把 Real-ESRGAN 推理引擎下载到 `.devtools/runtime`。
//
// 应用本身会在首次运行时自动完成同样的下载，这个脚本只是为了在本地跑
// 端到端测试或离线调试时，省去反复等待下载。
//
// 用法：dart run tool/fetch_runtime.dart
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const String _url =
    'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip';
const String _sha256 = 'abc02804e17982a3be33675e4d471e91ea374e65b70167abc09e31acb412802d';

Future<void> main() async {
  final target = Directory(p.join(Directory.current.path, '.devtools', 'runtime'));
  final marker = File(p.join(target.path, 'realesrgan-ncnn-vulkan.exe'));

  if (marker.existsSync()) {
    stdout.writeln('引擎已存在：${target.path}');
    return;
  }

  final cache = File(p.join(Directory.current.path, '.devtools', 'runtime.zip'));

  if (!cache.existsSync() || await _sha256Of(cache) != _sha256) {
    stdout.writeln('正在下载 $_url');
    await _download(Uri.parse(_url), cache);
  }

  final digest = await _sha256Of(cache);
  if (digest != _sha256) {
    stderr.writeln('校验失败：期望 $_sha256，实际 $digest');
    exitCode = 1;
    return;
  }
  stdout.writeln('校验通过');

  await target.create(recursive: true);
  final archive = ZipDecoder().decodeBytes(await cache.readAsBytes());
  var extracted = 0;
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    final base = p.basename(name);
    final isModel = name.contains('models/');
    final isRuntime = !name.contains('/') && (base.endsWith('.exe') || base.endsWith('.dll'));
    if (!isModel && !isRuntime) continue;

    final data = entry.readBytes();
    if (data == null) continue;
    final dest = File(p.join(target.path, isModel ? 'models' : '', base));
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(data);
    extracted++;
  }

  stdout.writeln('已解压 $extracted 个文件到 ${target.path}');
}

Future<void> _download(Uri url, File destination) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..findProxy = HttpClient.findProxyFromEnvironment;

  final request = await client.getUrl(url);
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}');
  }

  destination.parent.createSync(recursive: true);
  final sink = destination.openWrite();
  var received = 0;
  var lastReport = 0;
  await for (final chunk in response) {
    sink.add(chunk);
    received += chunk.length;
    if (received - lastReport > 4 * 1024 * 1024) {
      lastReport = received;
      stdout.writeln('  ${(received / 1024 / 1024).toStringAsFixed(1)} MB');
    }
  }
  await sink.close();
  client.close();
}

Future<String> _sha256Of(File file) async {
  if (!file.existsSync()) return '';
  return (await sha256.bind(file.openRead()).first).toString();
}
