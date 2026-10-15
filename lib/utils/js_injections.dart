// 网页内容注入脚本（广告拦截 CSS / 无图 / 省流 / 强制缩放 / 下载拦截）

/// 内建广告拦截 CSS（仅拦截常见广告，参考 Via「内建规则仅拦截常见广告」）
const String kAdBlockCss = '''
ins.adsbygoogle, [id^="ad-"], [id^="ad_"], [class^="ad-"], [class^="ad_"],
[class*="adsense"], [class*="adsbygoogle"], [id*="google_ads"],
iframe[src*="doubleclick.net"], iframe[src*="googlesyndication.com"],
iframe[src*="googleadservices.com"], iframe[src*="admob"],
iframe[src*="pos.baidu.com"], iframe[src*="cbjs.baidu.com"],
iframe[src*="cpro.baidu.com"], iframe[src*="pos.baidu"],
img[src*="pos.baidu.com"], img[src*="cpro.baidu.com"],
.a_p, .ad, .ads, .advert, .advertisement, .ad-box, .ad_wrap,
.baiduad, .baidu-ad, #BAIDU_SSP__wrapper, #BAIDU_DUP_wrapper,
.community_ad, .news-ad, .open-app, .openapp, .download-app,
.act-open, .btn-app, .app-open
{ display: none !important; }
''';

/// 无图模式：隐藏图片并阻止加载
const String kNoImageJs = '''
(function(){
  if (window.__viaNoImage) return; window.__viaNoImage = true;
  var style = document.createElement('style');
  style.textContent = 'img, image { display: none !important; }';
  (document.head || document.documentElement).appendChild(style);
  document.querySelectorAll('img').forEach(function(img){
    img.removeAttribute('src'); img.removeAttribute('srcset');
  });
})();
''';

/// 省流模式：隐藏图片与视频，禁止自动播放
const String kSaveDataJs = '''
(function(){
  if (window.__viaSaveData) return; window.__viaSaveData = true;
  var style = document.createElement('style');
  style.textContent = 'img, image, video { display: none !important; }';
  (document.head || document.documentElement).appendChild(style);
  document.querySelectorAll('img').forEach(function(img){
    img.removeAttribute('src'); img.removeAttribute('srcset');
  });
  document.querySelectorAll('video').forEach(function(v){ v.pause(); v.removeAttribute('src'); });
})();
''';

/// 强制缩放：强制开启 user-scalable
const String kForceZoomJs = '''
(function(){
  var m = document.querySelector('meta[name="viewport"]');
  var content = 'width=device-width, initial-scale=1.0, minimum-scale=0.25, maximum-scale=5.0, user-scalable=yes';
  if (m) { m.setAttribute('content', content); }
  else {
    var mt = document.createElement('meta');
    mt.name = 'viewport'; mt.content = content;
    (document.head || document.documentElement).appendChild(mt);
  }
})();
''';

/// 广告拦截 CSS 注入
const String kAdBlockInjectJs = '''
(function(){
  if (window.__viaAdBlock) return; window.__viaAdBlock = true;
  var style = document.createElement('style');
  style.textContent = %AD_CSS%;
  (document.head || document.documentElement).appendChild(style);
})();
''';

String adBlockInjectScript() {
  final css = kAdBlockCss.replaceAll("'", "\\'").replaceAll('\n', ' ');
  return kAdBlockInjectJs.replaceAll('%AD_CSS%', "'$css'");
}

/// 下载拦截：捕获带 download 属性的链接及常见文件扩展名链接点击
const String kDownloadHookJs = '''
(function(){
  if (window.__viaDlHook) return; window.__viaDlHook = true;
  var exts = ['apk','zip','rar','7z','gz','tar','bz2','xz','pdf','doc','docx',
    'xls','xlsx','ppt','pptx','mp3','wav','flac','aac','m4a','mp4','avi','mkv',
    'flv','mov','wmv','ts','jpg','jpeg','png','gif','webp','bmp','exe','dmg',
    'iso','torrent'];
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a') : null;
    if (!a || !a.href) return;
    var href = a.href;
    var isDownload = a.hasAttribute('download');
    var m = href.match(/\\.([a-z0-9]{1,6})(?:[?#]|\$)/i);
    var isFile = m && exts.indexOf(m[1].toLowerCase()) >= 0;
    if (isDownload || isFile) {
      e.preventDefault(); e.stopPropagation();
      if (window.DownloadBridge) DownloadBridge.postMessage(href);
    }
  }, true);
})();
''';

/// 密码捕获：表单提交时把用户名/密码通过 PasswordBridge 送回 Flutter 保存
const String kPasswordCaptureJs = '''
(function(){
  if (window.__viaPwdHook) return; window.__viaPwdHook = true;
  var fieldSelector = 'input[type=text],input[type=email],input[name*=user i],input[name*=email i],input[name*=account i],input[name*=login i],input[name*=name i]';
  document.addEventListener('submit', function(e){
    var form = e.target;
    if (!form || !form.querySelector) return;
    var pw = form.querySelector('input[type=password]');
    if (!pw || !pw.value) return;
    var user = form.querySelector(fieldSelector);
    if (!user || !user.value) return;
    if (window.PasswordBridge) {
      PasswordBridge.postMessage(JSON.stringify({
        action: 'save',
        host: location.host,
        username: user.value,
        password: pw.value
      }));
    }
  }, true);
})();
''';

/// 生成密码自动填充脚本（对已保存凭据的站点生效）
String passwordFillScript(String username, String password) {
  final u = _jsString(username);
  final p = _jsString(password);
  return '''
(function(){
  var pw = document.querySelector('input[type=password]');
  if (!pw) return;
  var form = pw.form || document;
  var fieldSelector = 'input[type=text],input[type=email],input[name*=user i],input[name*=email i],input[name*=account i],input[name*=login i],input[name*=name i]';
  var user = form.querySelector(fieldSelector);
  function setValue(el, v) {
    if (!el) return;
    el.value = v;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  setValue(user, $u);
  setValue(pw, $p);
})();
''';
}

/// 剪贴板桥接：把网页的 navigator.clipboard.writeText 转到系统剪贴板
const String kClipboardOverrideJs = '''
(function(){
  if (window.__viaClipboardHook) return; window.__viaClipboardHook = true;
  if (!navigator.clipboard) navigator.clipboard = {};
  navigator.clipboard.writeText = function(t) {
    if (window.ClipboardBridge) ClipboardBridge.postMessage(String(t));
    return Promise.resolve();
  };
})();
''';

/// 将字符串打包为 JS 字符串字面量
String _jsString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', '');
  return "'$escaped'";
}

/// 组装页面加载完成后需要执行的注入脚本
String buildPageFinishedScript({
  required bool adBlock,
  required bool noImage,
  required bool saveData,
  required bool forceZoom,
  bool passwordCapture = false,
  bool clipboardOverride = false,
}) {
  final scripts = <String>[];
  if (adBlock) scripts.add(adBlockInjectScript());
  if (noImage) scripts.add(kNoImageJs);
  if (saveData) scripts.add(kSaveDataJs);
  if (forceZoom) scripts.add(kForceZoomJs);
  if (passwordCapture) scripts.add(kPasswordCaptureJs);
  if (clipboardOverride) scripts.add(kClipboardOverrideJs);
  scripts.add(kDownloadHookJs);
  return scripts.join('\n');
}
