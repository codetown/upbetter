import 'dart:ffi';
import 'dart:io';

/// 任务完成时的系统提示音。
///
/// 用 Win32 的 `MessageBeep` 而不是往 stdout 写 `\a`——桌面应用通常没有控制台，
/// 写控制字符不会发出任何声音。
class Notify {
  Notify._();

  static const int _mbIconAsterisk = 0x00000040;

  static final int Function(int)? _messageBeep = _bind();

  static int Function(int)? _bind() {
    if (!Platform.isWindows) return null;
    try {
      return DynamicLibrary.open('user32.dll')
          .lookupFunction<Int32 Function(Uint32), int Function(int)>('MessageBeep');
    } on Object {
      return null;
    }
  }

  /// 播放系统提示音。失败时静默忽略——提示音永远不该影响主流程。
  static void beep() {
    try {
      _messageBeep?.call(_mbIconAsterisk);
    } on Object {
      // ignore
    }
  }
}
