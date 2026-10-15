import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// WebView 平台能力扩展：安全转型 AndroidWebViewController（非 Android 平台返回 null）
AndroidWebViewController? androidControllerOf(WebViewController controller) {
  final platform = controller.platform;
  if (platform is AndroidWebViewController) return platform;
  return null;
}

/// 应用字体大小（textZoom）
Future<void> applyFontSize(WebViewController controller, int textZoom) async {
  final android = androidControllerOf(controller);
  if (android != null) {
    try {
      await android.setTextZoom(textZoom);
      return;
    } catch (_) {}
  }
  // 非 Android 平台降级：注入 JS 缩放根字号
  final percent = textZoom / 100;
  try {
    await controller.runJavaScript(
      'document.documentElement.style.fontSize = '
      '${(16 * percent).toStringAsFixed(1)} + "px";',
    );
  } catch (_) {}
}

/// 应用强制缩放（开启双指缩放，覆盖网页 user-scalable=no 的场景由 JS 兜底）
Future<void> applyForceZoom(WebViewController controller, bool enabled) async {
  final android = androidControllerOf(controller);
  if (android == null) return;
  try {
    await android.enableZoom(enabled);
  } catch (_) {}
}

/// 应用媒体自动播放策略（省流模式下要求用户手势）
Future<void> applyMediaGesture(
  WebViewController controller,
  bool requireGesture,
) async {
  final android = androidControllerOf(controller);
  if (android == null) return;
  try {
    await android.setMediaPlaybackRequiresUserGesture(requireGesture);
  } catch (_) {}
}

/// 应用地理位置权限开关
Future<void> applyGeolocationEnabled(
  WebViewController controller,
  bool enabled,
) async {
  final android = androidControllerOf(controller);
  if (android == null) return;
  try {
    await android.setGeolocationEnabled(enabled);
  } catch (_) {}
}
