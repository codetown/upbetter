import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用目录布局。
///
/// 所有路径在 [init] 中一次性解析，之后均为同步访问，
/// 避免在任何热路径（渲染、任务回调）上触碰异步 IO。
class AppPaths {
  AppPaths._();

  static Directory _support = Directory.current;
  static Directory _runtime = Directory.current;
  static Directory _models = Directory.current;
  static Directory _cache = Directory.current;
  static Directory _logs = Directory.current;
  static Directory _output = Directory.current;

  static String? _portableRoot;

  /// 应用数据根目录（`%APPDATA%\upbetter`）。
  static Directory get support => _support;

  /// 推理运行时目录：存放 `realesrgan-ncnn-vulkan.exe` 及其依赖的 DLL。
  ///
  /// 若检测到绿色版布局（`<exe 所在目录>/runtime`），则优先使用它，
  /// 这样整个应用可以连同引擎一起打包分发。
  static Directory get runtime =>
      _portableRoot == null ? _runtime : Directory(_portableRoot!);

  /// 模型权重目录，作为 `-m` 参数传给推理进程。
  ///
  /// 便携模式下优先使用引擎目录自带的 `models/`，没有时才回退到应用数据目录，
  /// 这样「只指定引擎、模型仍在应用目录」的用户也能正常工作。
  static Directory get models {
    final root = _portableRoot;
    if (root != null) {
      final bundled = Directory(p.join(root, 'models'));
      if (bundled.existsSync()) return bundled;
    }
    return _models;
  }

  /// 切换到便携模式：运行时与模型都从 [path] 读取。
  static set portableRuntimeOverride(String? path) => _portableRoot = path;

  /// 缩略图与预览缓存。
  static Directory get cache => _cache;

  static Directory get thumbs => Directory(p.join(_cache.path, "thumbs"));

  /// 日志目录。
  static Directory get logs => _logs;

  /// 默认输出目录（用户图片库下的 `Upbetter`）。
  static Directory get output => _output;

  static File get settingsFile => File(p.join(_support.path, 'settings.json'));
  static File get windowStateFile => File(p.join(_support.path, 'window.json'));
  static File get logFile => File(p.join(_logs.path, 'upbetter.log'));

  /// 数据目录名。刻意写死而不是交给 `path_provider` 推导。
  ///
  /// Windows 上 `getApplicationSupportDirectory()` 会返回
  /// `%APPDATA%\<CompanyName>\<ProductName>`，也就是说**改一次可执行文件的
  /// 版本信息就会把用户的数据目录搬到别处**——设置、模型、引擎全部「消失」。
  /// 这个坑在开发期真实踩到过，所以这里把路径固定下来：
  /// 版本信息从此只影响属性对话框里显示什么，不再决定数据存在哪里。
  static const String _appDataFolderName = 'Upbetter';

  /// 解析全部路径并确保目录存在。应在 `runApp` 之前调用一次。
  static Future<void> init() async {
    _support = await _resolveSupportDir();
    _output = await _resolveOutputDir();
    _wireUp();
  }

  static Future<Directory> _resolveSupportDir() async {
    // Windows 上直接用 %APPDATA%，得到干净且稳定的单一目录。
    final appData = Platform.environment['APPDATA'];
    if (Platform.isWindows && appData != null && appData.isNotEmpty) {
      return Directory(p.join(appData, _appDataFolderName));
    }
    // 其它平台退回平台约定目录，便于核心层被移植或测试。
    return getApplicationSupportDirectory();
  }

  /// 直接指定数据根目录，跳过平台查询。
  ///
  /// 供测试与便携模式使用：不依赖 `path_provider`，因此可以在纯 Dart 环境中初始化。
  static void initWithRoot(Directory root) {
    _support = root;
    _output = Directory(p.join(root.path, 'output'));
    _wireUp();
  }

  static void _wireUp() {
    _runtime = Directory(p.join(_support.path, 'runtime'));
    _models = Directory(p.join(_support.path, 'models'));
    _cache = Directory(p.join(_support.path, 'cache'));
    _logs = Directory(p.join(_support.path, 'logs'));

    for (final dir in [_support, _runtime, _models, _cache, _logs, output, thumbs]) {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    }
  }

  static Future<Directory> _resolveOutputDir() async {
    try {
      final pictures = await getDownloadsDirectory();
      if (pictures != null) {
        return Directory(p.join(pictures.path, 'Upbetter'));
      }
    } on Object {
      // 某些环境下 Downloads 不可用，回退到应用数据目录。
    }
    return Directory(p.join(_support.path, 'output'));
  }
}
