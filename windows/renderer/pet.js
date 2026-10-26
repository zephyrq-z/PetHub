'use strict';

/**
 * 桌宠 renderer（语音三只 + 果冻共用）。
 *
 * 分工：
 *  - 主进程决定「播哪一句 / 谁接话 / hop-root」，renderer 只负责播放、字幕、动画、指针事件；
 *  - 点击 / 拖动交给主进程判定（用 screen.getCursorScreenPoint 算位移，跨 DPI 更稳）；
 *  - 果冻额外做按压放大 + 拖动拉长 + 图标切换 + 透明区域点击穿透。
 */

const api = window.pethub;
const params = new URLSearchParams(window.location.search);
const petId = params.get('id') || 'shaolan';

const audioRoot = document.getElementById('audio-root');
const jellyRoot = document.getElementById('jelly-root');
const face = document.getElementById('face');
const caption = document.querySelector('.caption');
const captionText = document.getElementById('caption-text');
const jellyIcon = document.getElementById('jelly-icon');
const credit = document.getElementById('credit');

let initData = null;
let audio = null;
let playToken = 0;
let captionHideTimer = null;
let noticeTimer = null;
let endFallbackTimer = null;
let pressed = false;
let pressedPointerId = null;
let jellyPressed = false;
let jellyStart = null;
let jellyInside = null;

const CREDIT_TEXT = '整合自 ShaolanPet / SunPet / FengGe-Desktop-Pet / JellyPet，版权归原作者；JellyPet 无 LICENSE。';
credit.textContent = CREDIT_TEXT;

// ---------------------------------------------------------------------------
// 初始化
// ---------------------------------------------------------------------------

api.onInit((payload) => {
  initData = payload;
  document.title = `${payload.title} · 桌宠合集（整合自 ShaolanPet / SunPet / FengGe-Desktop-Pet / JellyPet）`;
  if (payload.kind === 'jelly') {
    setupJelly(payload);
  } else {
    setupAudio(payload);
  }
});

api.onReload((payload) => {
  initData = payload;
  document.title = `${payload.title} · 桌宠合集（整合自 ShaolanPet / SunPet / FengGe-Desktop-Pet / JellyPet）`;
  applyAudioContent(payload);
});

api.onPlay(({ clip, volume }) => {
  playClip(clip, volume);
});

api.onStop(() => {
  stopVisualOnly();
});

api.onNotice(({ text, duration }) => {
  showNotice(text, duration);
});

api.onStyle(({ style }) => {
  applyJellyStyle(style);
});

api.onValidate(() => {
  validateAsset();
});

// ---------------------------------------------------------------------------
// 语音桌宠
// ---------------------------------------------------------------------------

function setupAudio(payload) {
  audioRoot.hidden = false;
  jellyRoot.hidden = true;
  applyAudioContent(payload);

  audio = new Audio();
  audio.preload = 'auto';
  audio.addEventListener('ended', () => {
    finishPlayback('ended');
  });
  audio.addEventListener('error', () => {
    finishPlayback('error');
  });
}

function applyAudioContent(payload) {
  audioRoot.hidden = false;
  jellyRoot.hidden = true;
  audioRoot.classList.remove('speaking');
  const style = document.documentElement.style;
  style.setProperty('--inset-x', `${payload.insetX ?? 8}px`);
  style.setProperty('--inset-y', `${payload.insetY ?? 8}px`);
  style.setProperty('--caption-band', `${payload.captionBand ?? 44}px`);
  style.setProperty('--caption-font', `${payload.fontSize ?? 13}px`);
  style.setProperty('--caption-radius', `${payload.captionRadius ?? 9}px`);
  style.setProperty('--caption-bg', payload.captionBg || 'rgba(0,0,0,0.76)');
  audioRoot.dataset.animation = payload.animation || 'squash';
  face.src = payload.avatarUrl;
  face.alt = payload.title || '';
  hideCaptionNow();
}

function playClip(clip, volume) {
  if (!audio) return;
  const token = ++playToken;
  clearTimeout(endFallbackTimer);
  hideNotice();
  audio.pause();
  try {
    audio.currentTime = 0;
  } catch {
    /* 还没加载好，忽略 */
  }
  audio.src = clip.url;
  audio.volume = Math.max(0, Math.min(1, Number(volume) || 0));
  setSpeaking(true);
  showCaption(clip.label);
  const promise = audio.play();
  if (promise && typeof promise.catch === 'function') {
    promise.catch((error) => {
      // 没有音频设备 / 解码失败时，视觉和主进程计时仍然要收尾。
      console.warn(`[pet] ${petId} 播放失败：${error.message}`);
      if (token === playToken) {
        endFallbackTimer = setTimeout(() => finishPlayback('fallback'), Math.max(250, clip.duration * 1000 + 150));
      }
    });
  }
  endFallbackTimer = setTimeout(() => {
    if (token === playToken) finishPlayback('fallback');
  }, Math.max(250, clip.duration * 1000 + 250));
  if (initData?.kind === 'audio') initData.volume = volume;
}

function finishPlayback(reason) {
  if (!audio) return;
  setSpeaking(false);
  scheduleHideCaption(420);
  api.playbackEnded();
  void reason;
}

function stopVisualOnly() {
  playToken += 1;
  clearTimeout(endFallbackTimer);
  if (audio) {
    try {
      audio.pause();
      audio.removeAttribute('src');
      audio.load();
    } catch {
      /* ignore */
    }
  }
  setSpeaking(false);
  hideCaptionNow();
}

function setSpeaking(speaking) {
  if (!initData || initData.kind === 'jelly') return;
  audioRoot.classList.toggle('speaking', Boolean(speaking));
  const animation = initData.animation || 'squash';
  audioRoot.classList.toggle('squash', animation === 'squash');
  audioRoot.classList.toggle('tilt', animation === 'tilt');
}

function showCaption(text) {
  if (!text) return;
  clearTimeout(captionHideTimer);
  captionText.textContent = text;
  caption.classList.add('show');
}

function scheduleHideCaption(delay) {
  clearTimeout(captionHideTimer);
  captionHideTimer = setTimeout(() => {
    caption.classList.remove('show');
  }, delay);
}

function hideCaptionNow() {
  clearTimeout(captionHideTimer);
  caption.classList.remove('show');
  captionText.textContent = '';
}

function showNotice(text, duration = 3000) {
  if (!text) return;
  hideNotice();
  showCaption(text);
  noticeTimer = setTimeout(() => {
    noticeTimer = null;
    scheduleHideCaption(0);
  }, Math.max(400, duration));
}

function hideNotice() {
  if (noticeTimer) {
    clearTimeout(noticeTimer);
    noticeTimer = null;
  }
}

// ---------------------------------------------------------------------------
// 指针：点击 / 拖动都交给主进程判定
// ---------------------------------------------------------------------------

function wireAudioPointer() {
  audioRoot.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    pressed = true;
    pressedPointerId = event.pointerId;
    try {
      audioRoot.setPointerCapture(event.pointerId);
    } catch {
      /* ignore */
    }
    api.pointer({ type: 'down', button: 0, screenX: event.screenX, screenY: event.screenY });
  });

  window.addEventListener('pointermove', (event) => {
    if (!pressed) return;
    api.pointer({ type: 'move', screenX: event.screenX, screenY: event.screenY });
  });

  window.addEventListener('pointerup', (event) => {
    if (!pressed) return;
    pressed = false;
    try {
      audioRoot.releasePointerCapture(pressedPointerId);
    } catch {
      /* ignore */
    }
    api.pointer({ type: 'up', button: event.button, screenX: event.screenX, screenY: event.screenY });
  });

  window.addEventListener('pointercancel', () => {
    if (!pressed) return;
    pressed = false;
    api.pointer({ type: 'cancel' });
  });

  window.addEventListener('contextmenu', (event) => {
    event.preventDefault();
    api.contextMenu();
  });
}

// ---------------------------------------------------------------------------
// 果冻
// ---------------------------------------------------------------------------

function setupJelly(payload) {
  audioRoot.hidden = true;
  jellyRoot.hidden = false;
  applyJellyStyle(payload.style);
  jellyIcon.alt = payload.title || '果冻';
  jellyRoot.classList.add('rebound');
  setTimeout(() => jellyRoot.classList.remove('rebound'), 500);

  jellyRoot.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    jellyPressed = true;
    pressed = true;
    pressedPointerId = event.pointerId;
    jellyStart = { x: event.screenX, y: event.screenY };
    jellyRoot.classList.add('pressed', 'dragging');
    try {
      jellyRoot.setPointerCapture(event.pointerId);
    } catch {
      /* ignore */
    }
    api.pointer({ type: 'down', button: 0, screenX: event.screenX, screenY: event.screenY });
  });

  window.addEventListener('pointermove', (event) => {
    if (!jellyPressed) {
      updateJellyHover(event);
      return;
    }
    const dx = event.screenX - jellyStart.x;
    const dy = event.screenY - jellyStart.y;
    const distance = Math.hypot(dx, dy);
    const iconSize = jellyIcon.getBoundingClientRect().width || 1;
    const amount = Math.min(0.32, distance / (iconSize * 2.2));
    const angle = (Math.atan2(dy, dx) * 180) / Math.PI;
    jellyIcon.style.transform = `rotate(${angle.toFixed(2)}deg) scale(${(1 + amount).toFixed(3)}, ${(
      1 -
      amount * 0.45
    ).toFixed(3)}) rotate(${(-angle).toFixed(2)}deg)`;
    api.pointer({ type: 'move', screenX: event.screenX, screenY: event.screenY });
  });

  window.addEventListener('pointerup', (event) => {
    if (!jellyPressed) return;
    jellyPressed = false;
    pressed = false;
    jellyRoot.classList.remove('pressed', 'dragging');
    jellyRoot.classList.add('rebound');
    jellyIcon.style.transform = '';
    setTimeout(() => jellyRoot.classList.remove('rebound'), 480);
    try {
      jellyRoot.releasePointerCapture(pressedPointerId);
    } catch {
      /* ignore */
    }
    api.pointer({ type: 'up', button: event.button, screenX: event.screenX, screenY: event.screenY });
  });

  window.addEventListener('pointercancel', () => {
    if (!jellyPressed) return;
    jellyPressed = false;
    pressed = false;
    jellyRoot.classList.remove('pressed', 'dragging');
    jellyIcon.style.transform = '';
    api.pointer({ type: 'cancel' });
  });

  window.addEventListener('mousemove', (event) => {
    if (!jellyPressed) updateJellyHover(event);
  });
  window.addEventListener('mouseleave', () => {
    if (!jellyPressed) setJellyInteractive(false);
  });

  window.addEventListener('contextmenu', (event) => {
    event.preventDefault();
    api.contextMenu();
  });

  setJellyInteractive(false);
}

function applyJellyStyle(style) {
  if (!initData || !initData.marks) return;
  const key = String(style ?? 0);
  const url = initData.marks[key] || initData.marks['0'];
  if (url) jellyIcon.src = url;
  jellyRoot.classList.remove('rebound');
  void jellyRoot.offsetWidth;
  jellyRoot.classList.add('rebound');
  setTimeout(() => jellyRoot.classList.remove('rebound'), 450);
}

function updateJellyHover(event) {
  const rect = jellyRoot.getBoundingClientRect();
  const centerX = rect.left + rect.width / 2;
  const centerY = rect.top + rect.height / 2;
  const radius = rect.width * 0.27; // 图标半径的 0.47：只让标志附近接收点击
  const inside = Math.hypot(event.clientX - centerX, event.clientY - centerY) <= radius;
  setJellyInteractive(inside);
}

function setJellyInteractive(inside) {
  if (jellyInside === inside) return;
  jellyInside = inside;
  api.jellyInteractive(inside);
}

// ---------------------------------------------------------------------------
// 素材校验（npm run smoke 用）
// ---------------------------------------------------------------------------

function loadImage(url) {
  return new Promise((resolve) => {
    const image = new Image();
    let settled = false;
    const finish = (width, height) => {
      if (settled) return;
      settled = true;
      resolve({ ok: width > 0 && height > 0, width, height });
    };
    image.onload = () => finish(image.naturalWidth, image.naturalHeight);
    image.onerror = () => finish(0, 0);
    image.src = url;
    setTimeout(() => finish(image.naturalWidth || 0, image.naturalHeight || 0), 8000);
  });
}

function probeAudioDuration(url) {
  return new Promise((resolve) => {
    const element = new Audio();
    let settled = false;
    const finish = (duration) => {
      if (settled) return;
      settled = true;
      element.removeAttribute('src');
      resolve(Number.isFinite(duration) ? duration : 0);
    };
    element.preload = 'metadata';
    element.onloadedmetadata = () => finish(element.duration);
    element.onerror = () => finish(0);
    element.src = url;
    setTimeout(() => finish(element.duration || 0), 8000);
  });
}

async function validateAsset() {
  try {
    if (!initData) {
      api.validateResult({ id: petId, ok: false, reason: 'init 未到达' });
      return;
    }
    if (initData.kind === 'jelly') {
      const marks = {};
      for (const [style, url] of Object.entries(initData.marks || {})) {
        const image = await loadImage(url);
        marks[style] = image.ok ? `${image.width}x${image.height}` : 'bad';
      }
      const ok = Object.values(marks).every((value) => value !== 'bad');
      api.validateResult({ id: petId, ok, marks, clipCount: 0 });
      return;
    }
    const avatar = await loadImage(initData.avatarUrl);
    const clips = initData.clips || [];
    const durations = await Promise.all(clips.map((clip) => probeAudioDuration(clip.url)));
    const badClips = [];
    clips.forEach((clip, index) => {
      if (!(durations[index] > 0.1)) badClips.push(`${clip.id}:${clip.label}`);
    });
    api.validateResult({
      id: petId,
      ok: avatar.ok && badClips.length === 0 && clips.length > 0,
      avatar,
      clipCount: clips.length,
      badClips,
    });
  } catch (error) {
    api.validateResult({ id: petId, ok: false, reason: error.message });
  }
}

// ---------------------------------------------------------------------------
// 启动
// ---------------------------------------------------------------------------

if (petId === 'jelly') {
  // 果冻的指针事件在 setupJelly 里接；init 到达前先不监听。
} else {
  wireAudioPointer();
}

api.ready();