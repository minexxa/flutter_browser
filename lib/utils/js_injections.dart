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

/// 长按图片：捕获长按/右键图片事件，把图片地址通过 ImageBridge 送回 Flutter
const String kImageLongPressJs = '''
(function(){
  if (window.__viaImgHook) return; window.__viaImgHook = true;
  var timer = null, img = null;
  function fire(t){
    if (window.ImageBridge) ImageBridge.postMessage(t.currentSrc || t.src || '');
  }
  document.addEventListener('touchstart', function(e){
    var t = e.target;
    if (t && t.tagName === 'IMG') {
      img = t;
      timer = setTimeout(function(){ fire(img); }, 550);
    }
  }, true);
  document.addEventListener('touchend', function(){ clearTimeout(timer); }, true);
  document.addEventListener('touchmove', function(){ clearTimeout(timer); }, true);
  document.addEventListener('touchcancel', function(){ clearTimeout(timer); }, true);
  document.addEventListener('contextmenu', function(e){
    var t = e.target;
    if (t && t.tagName === 'IMG') {
      e.preventDefault();
      fire(t);
    }
  }, true);
})();
''';

/// 页内查找：纯 JS 高亮全部匹配，支持上一个/下一个，计数通过 FindBridge 回传
const String kFindInPageJs = '''
(function(){
  if (window.__viaFindInit) return; window.__viaFindInit = true;
  var style = document.createElement('style');
  style.textContent = 'mark.via-find{background:#ffe066;color:#000;border-radius:2px;}' +
    'mark.via-find-current{background:#ff8f00;color:#fff;outline:2px solid #ff8f00;}';
  (document.head || document.documentElement).appendChild(style);
  var state = { matches: [], current: -1, query: '' };
  function report(){
    if (window.FindBridge) {
      FindBridge.postMessage(state.matches.length === 0 ? '0/0' : (state.current + 1) + '/' + state.matches.length);
    }
  }
  window.__viaFindClear = function(){
    var marks = document.querySelectorAll('mark.via-find');
    for (var i = 0; i < marks.length; i++) {
      var m = marks[i], parent = m.parentNode;
      if (!parent) continue;
      parent.replaceChild(document.createTextNode(m.textContent), m);
      if (parent.normalize) parent.normalize();
    }
    state = { matches: [], current: -1, query: '' };
    report();
  };
  window.__viaFindGo = function(i){
    if (state.matches.length === 0) return;
    if (i < 0) i = state.matches.length - 1;
    if (i >= state.matches.length) i = 0;
    if (state.current >= 0 && state.matches[state.current]) {
      state.matches[state.current].classList.remove('via-find-current');
    }
    state.current = i;
    state.matches[i].classList.add('via-find-current');
    state.matches[i].scrollIntoView({ block: 'center' });
    report();
  };
  window.__viaFind = function(q){
    window.__viaFindClear();
    if (!q) return;
    state.query = q;
    var lower = q.toLowerCase();
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: function(node){
        if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        var p = node.parentNode;
        if (!p) return NodeFilter.FILTER_REJECT;
        var tag = p.nodeName ? p.nodeName.toLowerCase() : '';
        if (tag === 'script' || tag === 'style' || tag === 'noscript' || tag === 'mark') {
          return NodeFilter.FILTER_REJECT;
        }
        return node.nodeValue.toLowerCase().indexOf(lower) >= 0 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (var n = 0; n < nodes.length; n++) {
      var node = nodes[n], text = node.nodeValue, lt = text.toLowerCase();
      var frag = document.createDocumentFragment(), idx = 0, pos;
      while ((pos = lt.indexOf(lower, idx)) >= 0) {
        if (pos > idx) frag.appendChild(document.createTextNode(text.substring(idx, pos)));
        var mark = document.createElement('mark');
        mark.className = 'via-find';
        mark.textContent = text.substring(pos, pos + q.length);
        frag.appendChild(mark);
        idx = pos + q.length;
      }
      if (idx < text.length) frag.appendChild(document.createTextNode(text.substring(idx)));
      node.parentNode.replaceChild(frag, node);
    }
    state.matches = Array.prototype.slice.call(document.querySelectorAll('mark.via-find'));
    if (state.matches.length > 0) window.__viaFindGo(0); else report();
  };
  window.__viaFindNext = function(){ window.__viaFindGo(state.current + 1); };
  window.__viaFindPrev = function(){ window.__viaFindGo(state.current - 1); };
})();
''';

/// 站点级图片阻止（网站设置中按站点覆盖）
const String kSiteNoImageJs = '''
(function(){
  if (window.__viaSiteNoImage) return; window.__viaSiteNoImage = true;
  var style = document.createElement('style');
  style.textContent = 'img, image { display: none !important; }';
  (document.head || document.documentElement).appendChild(style);
  document.querySelectorAll('img').forEach(function(img){
    img.removeAttribute('src'); img.removeAttribute('srcset');
  });
})();
''';

/// 阅读模式：提取网页正文（article/main 优先，其次文本密度），经 ReaderBridge 回传
const String kReaderExtractJs = '''
(function(){
  function textLen(el){
    return (el.innerText || el.textContent || '').replace(/\\s+/g, '').length;
  }
  function pickMain(){
    var candidates = document.querySelectorAll(
      'article, main, [role=main], .article, .article-content, .content, .post, .post-content, .rich_media_content, #content, #js_content');
    var best = null, bestLen = 0;
    for (var i = 0; i < candidates.length; i++) {
      var len = textLen(candidates[i]);
      if (len > bestLen) { bestLen = len; best = candidates[i]; }
    }
    if (best && bestLen >= 200) return best;
    var blocks = document.querySelectorAll('div, section');
    for (var j = 0; j < blocks.length; j++) {
      var b = blocks[j];
      if (b.querySelectorAll('p').length < 3) continue;
      var len2 = textLen(b);
      if (len2 > bestLen) { bestLen = len2; best = b; }
    }
    return best || document.body;
  }
  var main = pickMain();
  var html = '';
  if (main) {
    var clone = main.cloneNode(true);
    clone.querySelectorAll('script,style,iframe,noscript,form,button,svg').forEach(function(el){
      el.parentNode && el.parentNode.removeChild(el);
    });
    html = clone.innerHTML || '';
  }
  if (window.ReaderBridge) {
    ReaderBridge.postMessage(JSON.stringify({ title: document.title || '', html: html }));
  }
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

/// 网页资源嗅探：收集页面内媒体资源（performance + DOM），经 ResourceBridge 回传
const String kResourceSnifferJs = '''
(function(){
  if (window.__viaSniffer) return; window.__viaSniffer = true;
  var exts = /\\.(m3u8|mp4|flv|mkv|avi|mov|ts|m4s|mpd|webm|mp3|flac|m4a|aac|wav|ogg)(\\?|#|\$)/i;
  function match(u){ return !!u && exts.test(u.split('#')[0]); }
  function collect(){
    var out = {};
    try {
      performance.getEntriesByType('resource').forEach(function(r){
        if (match(r.name)) out[r.name] = 1;
      });
    } catch(e) {}
    document.querySelectorAll('video,audio,source').forEach(function(el){
      [el.currentSrc, el.src].forEach(function(u){ if (match(u)) out[u] = 1; });
    });
    document.querySelectorAll('a[href]').forEach(function(a){
      if (match(a.href)) out[a.href] = 1;
    });
    return Object.keys(out);
  }
  window.__viaSniff = function(){
    if (window.ResourceBridge) ResourceBridge.postMessage(JSON.stringify(collect()));
  };
  setTimeout(window.__viaSniff, 1200);
})();
''';

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
  scripts.add(kImageLongPressJs);
  scripts.add(kFindInPageJs);
  scripts.add(kResourceSnifferJs);
  scripts.add(kDownloadHookJs);
  return scripts.join('\n');
}
