import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _CreateHardLinkNative = Int32 Function(
  Pointer<Utf16> fileName,
  Pointer<Utf16> existingFileName,
  Pointer<Void> securityAttributes,
);
typedef _CreateHardLinkDart = int Function(
  Pointer<Utf16> fileName,
  Pointer<Utf16> existingFileName,
  Pointer<Void> securityAttributes,
);

/// NTFS 硬链接。
///
/// 批量处理时需要把所有待处理文件汇集到一个暂存目录，才能让推理进程
/// 用「目录模式」一次跑完（模型只加载一次）。对于动辄上百 MB 的原图，
/// 复制会带来可观的磁盘 IO 与瞬时空间占用；硬链接在 NTFS 上只是新增一条
/// 目录项，耗时恒定且不占额外空间，因此优先走这条路，失败再退化为复制。
class HardLink {
  HardLink._();

  static final _CreateHardLinkDart? _createHardLink = _bind();

  static _CreateHardLinkDart? _bind() {
    if (!Platform.isWindows) return null;
    try {
      return DynamicLibrary.open('kernel32.dll')
          .lookupFunction<_CreateHardLinkNative, _CreateHardLinkDart>('CreateHardLinkW');
    } on Object {
      return null;
    }
  }

  /// 在 [linkPath] 处创建指向 [existingPath] 的硬链接。
  ///
  /// 返回是否成功。跨卷、目标已存在或源文件位于不支持硬链接的文件系统时返回 `false`。
  static bool create(String linkPath, String existingPath) {
    final fn = _createHardLink;
    if (fn == null) return false;

    final linkPtr = linkPath.toNativeUtf16();
    final existingPtr = existingPath.toNativeUtf16();
    try {
      return fn(linkPtr, existingPtr, nullptr) != 0;
    } on Object {
      return false;
    } finally {
      malloc.free(linkPtr);
      malloc.free(existingPtr);
    }
  }
}
