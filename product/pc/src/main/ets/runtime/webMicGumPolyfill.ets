/**
 * 文档起始注入的麦克风适配脚本。
 * 仅替换带 audio 约束的 getUserMedia，video 仍然走 ArkWeb 原生链路。
 */
export const WEB_MIC_GUM_POLYFILL: string = `
(function () {
  try {
    if (window.__ohBrowserMicGumV2) { return; }
    window.__ohBrowserMicGumV2 = true;
    var bridgeName = 'ohTabMicBridge';
    function waitBridge(timeoutMs) {
      return new Promise(function (resolve, reject) {
        var elapsed = 0;
        var timer = setInterval(function () {
          var bridge = window[bridgeName];
          if (bridge && typeof bridge.startNativeMic === 'function') {
            clearInterval(timer);
            resolve(bridge);
            return;
          }
          elapsed += 50;
          if (elapsed >= timeoutMs) {
            clearInterval(timer);
            reject(new Error('mic_bridge_unavailable'));
          }
        }, 50);
      });
    }
    function waitReady(bridge, timeoutMs) {
      return new Promise(function (resolve, reject) {
        var startedAt = Date.now();
        var timer = setInterval(function () {
          var state = bridge.getNativeMicState();
          if (state === 'ready') {
            clearInterval(timer);
            resolve();
            return;
          }
          if (typeof state === 'string' && state.indexOf('error:') === 0) {
            clearInterval(timer);
            reject(new Error(state));
            return;
          }
          if (Date.now() - startedAt >= timeoutMs) {
            clearInterval(timer);
            reject(new Error('mic_capture_timeout'));
          }
        }, 50);
      });
    }
    function decodePcm(base64) {
      var binary = atob(base64);
      var bytes = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      var samples = bytes.byteLength >> 1;
      var result = new Float32Array(samples);
      var view = new DataView(bytes.buffer);
      for (var j = 0; j < samples; j++) {
        result[j] = view.getInt16(j * 2, true) / 32768;
      }
      return result;
    }
    function createNativeStream() {
      return waitBridge(3000).then(function (bridge) {
        bridge.startNativeMic(String(location.origin || ''));
        return waitReady(bridge, 15000).then(function () { return bridge; });
      }).then(function (bridge) {
        var AudioContextCtor = window.AudioContext || window.webkitAudioContext;
        if (!AudioContextCtor) { throw new Error('audio_context_unavailable'); }
        var context = new AudioContextCtor({ sampleRate: 48000 });
        var destination = context.createMediaStreamDestination();
        var processor = context.createScriptProcessor(2048, 1, 1);
        var ring = [];
        processor.onaudioprocess = function (event) {
          try {
            var needed = event.outputBuffer.length * 2;
            var encoded = bridge.pullMicPcm(String(needed));
            if (encoded) {
              var decoded = decodePcm(encoded);
              for (var i = 0; i < decoded.length; i++) { ring.push(decoded[i]); }
            }
            var output = event.outputBuffer.getChannelData(0);
            for (var j = 0; j < output.length; j++) {
              output[j] = ring.length > 0 ? ring.shift() : 0;
            }
          } catch (_) {
            // Keep the audio callback alive; the next callback can recover.
          }
        };
        var silentBuffer = context.createBuffer(1, 1024, context.sampleRate);
        var source = context.createBufferSource();
        source.buffer = silentBuffer;
        source.loop = true;
        source.connect(processor);
        processor.connect(destination);
        source.start();
        if (typeof context.resume === 'function') {
          context.resume().catch(function () {});
        }
        var stream = destination.stream;
        var stopped = false;
        function stopNativeStream() {
          if (stopped) { return; }
          stopped = true;
          try { bridge.stopNativeMic(); } catch (_) {}
          try { context.close(); } catch (_) {}
        }
        stream.__ohNativeMic = true;
        stream.getTracks().forEach(function (track) {
          track.addEventListener('ended', function () {
            stopNativeStream();
          });
          try {
            var originalStop = track.stop.bind(track);
            track.stop = function () {
              originalStop();
              stopNativeStream();
            };
          } catch (_) {
            // Some WebView builds expose MediaStreamTrack.stop as read-only.
            // Navigation and the ended event still release the native capturer.
          }
        });
        return stream;
      });
    }
    function patchMediaDevices() {
      var mediaDevices = navigator.mediaDevices;
      if (!mediaDevices || typeof mediaDevices.getUserMedia !== 'function') { return false; }
      if (window.__ohBrowserMicMediaDevicesPatched) { return true; }
      var originalGetUserMedia = mediaDevices.getUserMedia.bind(mediaDevices);
      mediaDevices.getUserMedia = function (constraints) {
        var request = constraints ? Object.assign({}, constraints) : {};
        var wantsAudio = !!request.audio;
        var wantsVideo = !!request.video;
        if (!wantsAudio) { return originalGetUserMedia(request); }
        var videoPromise = wantsVideo
          ? originalGetUserMedia({ video: request.video, audio: false })
          : Promise.resolve(null);
        return Promise.all([videoPromise, createNativeStream()]).then(function (parts) {
          var tracks = [];
          if (parts[0]) { parts[0].getTracks().forEach(function (track) { tracks.push(track); }); }
          parts[1].getTracks().forEach(function (track) { tracks.push(track); });
          return new MediaStream(tracks);
        });
      };
      window.__ohBrowserMicMediaDevicesPatched = true;
      return true;
    }
    patchMediaDevices();
    var patchAttempts = 0;
    var patchTimer = setInterval(function () {
      if (patchMediaDevices() || ++patchAttempts >= 60) {
        clearInterval(patchTimer);
      }
    }, 50);
    function patchLegacyGetUserMedia() {
      if (typeof navigator.getUserMedia !== 'function' ||
          window.__ohBrowserLegacyMicPatched) { return window.__ohBrowserLegacyMicPatched === true; }
      var originalLegacyGetUserMedia = navigator.getUserMedia.bind(navigator);
      navigator.getUserMedia = function (constraints, success, failure) {
        var request = constraints ? Object.assign({}, constraints) : {};
        var promise = request.audio
          ? (window.navigator.mediaDevices && window.navigator.mediaDevices.getUserMedia
            ? window.navigator.mediaDevices.getUserMedia(request)
            : createNativeStream())
          : new Promise(function (resolve, reject) {
            originalLegacyGetUserMedia(request, resolve, reject);
          });
        promise.then(success).catch(failure);
      };
      window.__ohBrowserLegacyMicPatched = true;
      return true;
    }
    patchLegacyGetUserMedia();
    var legacyPatchAttempts = 0;
    var legacyPatchTimer = setInterval(function () {
      if (patchLegacyGetUserMedia() || ++legacyPatchAttempts >= 60) {
        clearInterval(legacyPatchTimer);
      }
    }, 50);
  } catch (_) {
    // Never break pages that do not use getUserMedia.
  }
})();
`;
