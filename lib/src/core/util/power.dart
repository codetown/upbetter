import 'dart:ffi';
import 'dart:io';

/// 阻止系统在处理长任务时进入睡眠。
///
/// 直接调用 `kernel32!SetThreadExecutionState`，无需额外依赖。
/// 这是 Win32 的约定用法：状态绑定在线程上，必须在同一 isolate 中成对调用。
class PowerGuard {
  PowerGuard._();

  // 常量按 32 位有符号整数书写：`0x80000000` 在 Dart 里是正的，
  // 但传给 Win32 的 `ES_CONTINUOUS` 位模式恰好是 Int32 的最小值。
  static const int _esContinuous = -2147483648;
  static const int _esSystemRequired = 0x00000001;

  static final DynamicLibrary? _kernel32 = _openKernel32();
  static final int Function(int)? _setThreadExecutionState = _bind();

  static bool _active = false;

  static DynamicLibrary? _openKernel32() {
    if (!Platform.isWindows) return null;
    try {
      return DynamicLibrary.open('kernel32.dll');
    } on Object {
      return null;
    }
  }

  static int Function(int)? _bind() {
    try {
      return _kernel32
          ?.lookupFunction<Int32 Function(Int32), int Function(int)>('SetThreadExecutionState');
    } on Object {
      return null;
    }
  }

  /// 开始阻止休眠。重复调用是安全的。
  static void acquire() {
    if (_active || _setThreadExecutionState == null) return;
    final result = _setThreadExecutionState!(_esContinuous | _esSystemRequired);
    _active = result != 0;
  }

  /// 恢复系统的默认电源行为。
  static void release() {
    if (!_active || _setThreadExecutionState == null) return;
    _setThreadExecutionState!(_esContinuous);
    _active = false;
  }
}
