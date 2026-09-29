// TabMediaMonitor：页面级音视频播放探测，供标签栏喇叭图标使用。
//
// 为什么不能只靠内核：ArkWeb 自己的音频信号（getMediaPlaybackState /
// onAudioStateChanged）只描述「当前是否真的在出声」。像 B 站那样由页面自己
// 把 <video> 设成 muted 的自动播放，内核始终返回 MediaPlaybackState.NONE，
// 标签栏就完全看不到视频在放，右键菜单里的静音项也一直是被禁用的。
//
// 所以这里在 document start 注入一个只读探针，监听页面里的 media 元素，
// 有变化就通过 JavaScriptProxy 回一个布尔值。
//
// 关键约束：只观察，绝不插手播放。不写 muted、不调 play()。页面的自动播放
// 策略、用户自己按下的暂停、音量大小都是页面的事，浏览器代它做决定只会
// 制造「暂停了又自己播」这种鬼故事。

export const TAB_MEDIA_BRIDGE_NAME: string = 'ohTabMediaBridge';
export const TAB_MEDIA_PLAYING_METHOD: string = 'onPlayingChanged';

export type TabMediaPlayingListener = (tabId: string, playing: boolean) => void;

export class TabMediaBridge {
  private tabId: string;
  private listener: TabMediaPlayingListener;

  constructor(tabId: string, listener: TabMediaPlayingListener) {
    this.tabId = tabId;
    this.listener = listener;
  }

  // 由注入脚本调用。参数刻意保持原始类型：proxy 需要把页面侧的 JS 值搬进
  // ArkTS，一个 boolean 是最窄、最不容易在各 SDK 版本上翻车的契约。
  onPlayingChanged(playing: boolean): void {
    this.listener(this.tabId, playing === true);
  }
}

// 注入到每个文档开头的探针。media 事件不冒泡，但捕获阶段仍然会经过
// document，所以在 document 上用 capture 监听就能收到任意深度的
// <audio>/<video> 的 play/pause/ended/volumechange。
export const TAB_MEDIA_MONITOR_SCRIPT: string = `
(function () {
  if (window.__ohTabMediaMonitor) { return; }
  window.__ohTabMediaMonitor = true;

  var BRIDGE_NAME = '${TAB_MEDIA_BRIDGE_NAME}';
  var METHOD_NAME = '${TAB_MEDIA_PLAYING_METHOD}';
  var last = null;
  var scheduled = false;

  // 「在播」= 没暂停、没播完、且已经有当前帧的数据。刻意不看 muted/volume：
  // 页面自己静音的视频同样应该让标签栏出现可静音控件。
  function isPlaying(element) {
    if (element.paused || element.ended) { return false; }
    if (element.readyState < 2) { return false; }
    return true;
  }

  function scan() {
    var playing = false;
    var nodes = document.querySelectorAll('audio, video');
    for (var i = 0; i < nodes.length; i++) {
      if (isPlaying(nodes[i])) { playing = true; break; }
    }
    var flag = playing ? '1' : '0';
    if (flag === last) { return; }
    var bridge = window[BRIDGE_NAME];
    if (!bridge || typeof bridge[METHOD_NAME] !== 'function') {
      // proxy 可能比首次扫描晚一步挂上。不缓存结果，交给下一轮重试。
      last = null;
      return;
    }
    last = flag;
    try {
      bridge[METHOD_NAME](playing);
    } catch (error) {
      last = null;
    }
  }

  function schedule() {
    if (scheduled) { return; }
    scheduled = true;
    setTimeout(function () { scheduled = false; scan(); }, 80);
  }

  var EVENTS = ['play', 'playing', 'pause', 'ended', 'emptied', 'loadedmetadata',
    'loadeddata', 'canplay', 'waiting', 'stalled', 'seeking', 'seeked',
    'volumechange', 'ratechange'];
  for (var i = 0; i < EVENTS.length; i++) {
    document.addEventListener(EVENTS[i], schedule, true);
  }
  document.addEventListener('DOMContentLoaded', schedule, true);
  window.addEventListener('pageshow', schedule, true);
  // 兜底扫描：事件被节流或漏掉时，状态仍然会在一秒半内归位。
  setInterval(scan, 1500);
  schedule();
})();
`;
