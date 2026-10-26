'use strict';

/**
 * 桌宠合集 PetHub · Windows 跨平台版（Electron 主进程）
 *
 * 目标：在 Windows 上复刻 macOS 原生版 v2.0.0 的四只桌宠 + 捧哏链 + PetPack + 托盘/设置。
 * 硬约束（与 macOS 版保持一致，不要改语义）：
 *   - hop/root：用户点击 hop 0、root 自己；接话者 hop+1、root 原样；hop 到 3 收链，没有第五句；
 *   - 薄肌永不接；太对了接薄肌/峰哥；峰哥只在 root==shaolan 时接太对了；
 *   - 自定义 PetPack 只替换薄肌槽位，PetID / root 仍然是 shaolan，显示名只走 displayTitle。
 *
 * 只写 windows/ 与 docs/WINDOWS.md；不碰 macOS 的 Sources/ build.sh dist/PetHub-2.0.0.dmg。
 */

const {
  app,
  BrowserWindow,
  Menu,
  Tray,
  dialog,
  ipcMain,
  nativeImage,
  screen,
  shell,
} = require('electron');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { pathToFileURL } = require('url');

const {
  ORDER,
  SLOT_WIDTH,
  LAYOUT,
  VOLUME_STEPS,
  PET_PROFILES,
  CREDIT_LINE,
  CREDIT_DETAIL,
  UPSTREAM,
} = require('./lib/pets');
const { SettingsStore, clampScale, pickVolume } = require('./lib/settings');
const layout = require('./lib/layout');
const petpack = require('./lib/petpack');
const { AssetProbe } = require('./lib/probe');

const IS_SMOKE = process.argv.includes('--smoke');
const TRACE = process.argv.includes('--trace') || IS_SMOKE;
/** 只为 QA / 自动化开的口子：安装内容包、恢复原版、dump 状态、实测四步链。 */
const INSTALL_PACK_DIR = (() => {
  const index = process.argv.indexOf('--install-pack');
  if (index < 0) return null;
  return process.argv[index + 1] && !process.argv[index + 1].startsWith('--') ? process.argv[index + 1] : null;
})();
const RESTORE_BUILTIN = process.argv.includes('--restore-builtin');
const DUMP_STATE = process.argv.includes('--dump-state');
const IS_CHAIN_TEST = process.argv.includes('--chain-test');
/** 不把窗口弹到用户桌面的模式。 */
const HIDDEN_MODE = IS_SMOKE || IS_CHAIN_TEST;
/** `--screenshot <目录>`：QA 用，把四只窗口 + 设置窗口各截一张 png 后退出。 */
const SCREENSHOT_DIR = (() => {
  const index = process.argv.indexOf('--screenshot');
  if (index < 0) return null;
  return process.argv[index + 1] && !process.argv[index + 1].startsWith('--') ? process.argv[index + 1] : null;
})();
const IS_SCREENSHOT = Boolean(SCREENSHOT_DIR);
/** `--settings`：正常启动后直接打开设置窗口（`npm start -- --settings` 用来验收）。 */
const OPEN_SETTINGS = process.argv.includes('--settings');
const APP_VERSION = app.getVersion();
const RENDERER_DIR = path.join(__dirname, 'renderer');
const PRELOAD = path.join(__dirname, 'preload.js');

/** dev / 打包两种模式的素材与文档路径。 */
const ASSETS_DIR = app.isPackaged ? path.join(process.resourcesPath, 'assets') : path.join(__dirname, 'assets');
const DOC_DIR = app.isPackaged ? path.join(process.resourcesPath, 'docs') : path.join(__dirname, '..', 'docs');
const CREDITS_FILE = app.isPackaged
  ? path.join(process.resourcesPath, 'CREDITS.md')
  : path.join(__dirname, '..', 'CREDITS.md');

// smoke 用临时 userData，绝不碰用户真实设置 / 内容包；dev 也和 macOS 原生版分开目录。
if (IS_SMOKE) {
  app.setPath('userData', path.join(os.tmpdir(), `pethub-windows-smoke-${process.pid}`));
} else if (!app.isPackaged) {
  app.setPath('userData', path.join(app.getPath('appData'), 'PetHub-Windows-Dev'));
}

const state = {
  settings: null,
  store: null,
  probe: null,
  tray: null,
  settingsWin: null,
  pets: new Map(),
  custom: { content: null, error: null, signature: null },
  quitting: false,
  smoke: null,
};

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function log(...args) {
  if (TRACE) console.log(...args);
}

function fileUrl(file) {
  return pathToFileURL(file).href;
}

function docPath(name) {
  return path.join(DOC_DIR, name);
}

function repoDocPath(name) {
  return path.join(__dirname, '..', name);
}

function readImageSize(file) {
  try {
    const image = nativeImage.createFromPath(file);
    if (!image.isEmpty()) {
      const size = image.getSize();
      if (size.width > 0 && size.height > 0) return size;
    }
  } catch {
    /* 交给调用方兜底 */
  }
  return null;
}

function shuffle(list) {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

function safeUnlink(file) {
  try {
    fs.rmSync(file, { recursive: true, force: true });
  } catch {
    /* ignore */
  }
}

// ---------------------------------------------------------------------------
// 设置与内容
// ---------------------------------------------------------------------------

/** 读取内置素材的 clips.json，转成运行时 clip（带 file:// URL）。 */
function loadBuiltinClips(id) {
  const profile = PET_PROFILES[id];
  const folder = path.join(ASSETS_DIR, profile.assetsFolder);
  const manifestPath = path.join(folder, 'clips.json');
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`素材缺失：${manifestPath}（先在 windows/ 里跑 npm run copy-assets）`);
  }
  const raw = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (!Array.isArray(raw)) throw new Error(`素材格式不对：${manifestPath} 不是数组`);
  return raw.map((entry) => {
    const file = path.join(folder, 'Clips', entry.file);
    if (!fs.existsSync(file)) throw new Error(`素材缺失：${file}`);
    return {
      id: Number(entry.id),
      label: String(entry.label),
      file: entry.file,
      absPath: file,
      url: fileUrl(file),
      duration: Number(entry.duration) || 0.8,
      answer: entry.answer !== false,
      defaultOff: entry.defaultOff === true,
    };
  });
}

function loadBuiltinAvatar(id) {
  const profile = PET_PROFILES[id];
  const file = path.join(ASSETS_DIR, profile.assetsFolder, 'face.png');
  if (!fs.existsSync(file)) throw new Error(`素材缺失：${file}`);
  const size = readImageSize(file);
  const ratio = size ? size.height / size.width : 1;
  return { file, ratio, size };
}

function jellyMarkPaths() {
  const profile = PET_PROFILES.jelly;
  const marks = {};
  for (const [style, name] of Object.entries(profile.marks)) {
    const file = path.join(ASSETS_DIR, profile.assetsFolder, name);
    if (!fs.existsSync(file)) throw new Error(`素材缺失：${file}`);
    marks[style] = fileUrl(file);
  }
  return marks;
}

/** 给一只桌宠建运行时的内容描述（语音桌宠：头像 + clips）。 */
function buildContentFor(id) {
  const profile = PET_PROFILES[id];
  if (id === 'shaolan' && state.custom.content) {
    const content = state.custom.content;
    return {
      id,
      custom: true,
      displayTitle: content.name,
      author: content.author,
      avatarPath: content.avatar.absPath,
      avatarUrl: fileUrl(content.avatar.absPath),
      faceRatio: content.avatar.ratio,
      clips: content.clips.map((clip) => ({
        id: clip.id,
        label: clip.label,
        file: clip.file,
        absPath: clip.absPath,
        url: fileUrl(clip.absPath),
        duration: clip.duration,
        defaultOff: false,
      })),
      signature: state.custom.signature,
    };
  }
  const builtin = loadBuiltinClips(id);
  const avatar = loadBuiltinAvatar(id);
  return {
    id,
    custom: false,
    displayTitle: profile.title,
    author: '',
    avatarPath: avatar.file,
    avatarUrl: fileUrl(avatar.file),
    faceRatio: avatar.ratio,
    clips: builtin,
    signature: null,
  };
}

function initialExcludedIds(pet, content) {
  const stored = state.settings.pets[pet.id]?.excludedIDs;
  if (Array.isArray(stored)) return new Set(stored);
  if (pet.profile.initialDefaultOffExclusions) {
    return new Set(content.clips.filter((clip) => clip.defaultOff).map((clip) => clip.id));
  }
  return new Set();
}

function createPetRuntime(id, content) {
  const profile = PET_PROFILES[id];
  const saved = state.settings.pets[id];
  const pet = {
    id,
    profile,
    kind: profile.kind,
    content,
    displayTitle: content ? content.displayTitle : profile.title,
    avatarPath: content ? content.avatarPath : null,
    faceRatio: content ? content.faceRatio : 1,
    clips: content ? content.clips : [],
    clipById: new Map(),
    bags: {},
    scale: saved.scale,
    volume: saved.volume ?? 0.65,
    randomMode: saved.randomMode !== false,
    pinnedID: saved.pinnedID ?? null,
    excludedIDs: new Set(),
    style: saved.style ?? 0,
    visible: saved.visible !== false,
    win: null,
    ready: false,
    playing: false,
    playTimer: null,
    currentClip: null,
    pending: null,
    drag: null,
    validateWaiters: [],
    validateResult: null,
  };
  if (pet.kind === 'audio') {
    pet.excludedIDs = initialExcludedIds(pet, content);
    pet.clipById = new Map(pet.clips.map((clip) => [clip.id, clip]));
  }
  return pet;
}

// ---------------------------------------------------------------------------
// 窗口 / 布局
// ---------------------------------------------------------------------------

function statesForLayout() {
  const states = {};
  for (const id of ORDER) {
    const pet = state.pets.get(id);
    states[id] = { profile: pet.profile, scale: pet.scale, faceRatio: pet.faceRatio };
  }
  return states;
}

function arrangementArea() {
  const shaolan = state.pets.get('shaolan');
  let display = null;
  if (shaolan && shaolan.win && !shaolan.win.isDestroyed()) {
    display = screen.getDisplayMatching(shaolan.win.getBounds());
  }
  if (!display) display = screen.getPrimaryDisplay();
  return display.workArea;
}

function windowSizeFor(pet) {
  if (pet.kind === 'jelly') {
    return layout.jellyWindowSize(layout.iconSideFor(pet.profile, pet.scale));
  }
  return layout.audioSize(pet.profile, pet.scale, pet.faceRatio);
}

function applyBounds(pet, bounds, persist = false) {
  if (!pet.win || pet.win.isDestroyed()) return;
  const rounded = {
    x: Math.round(bounds.x),
    y: Math.round(bounds.y),
    width: Math.round(bounds.width),
    height: Math.round(bounds.height),
  };
  pet.win.setBounds(rounded, false);
  if (persist) {
    state.settings.pets[pet.id].x = rounded.x;
    state.settings.pets[pet.id].y = rounded.y;
    state.store.save();
  }
}

function createPetWindow(pet) {
  const size = windowSizeFor(pet);
  const defaults = layout.defaultLayout(statesForLayout(), arrangementArea());
  const saved = state.settings.pets[pet.id];
  let bounds = defaults[pet.id];
  if (saved.x != null && saved.y != null) {
    const candidate = { x: saved.x, y: saved.y, width: size.width, height: size.height };
    if (layout.isReasonablePosition(candidate, screen.getAllDisplays())) bounds = candidate;
  }

  const window = new BrowserWindow({
    x: bounds.x,
    y: bounds.y,
    width: size.width,
    height: size.height,
    show: false,
    frame: false,
    transparent: true,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    hasShadow: false,
    focusable: pet.kind === 'audio',
    alwaysOnTop: true,
    backgroundColor: '#00000000',
    title: `${pet.displayTitle} · 桌宠合集（${CREDIT_LINE}）`,
    icon: path.join(ASSETS_DIR, 'AppIcon.png'),
    webPreferences: {
      preload: PRELOAD,
      contextIsolation: true,
      nodeIntegration: false,
      backgroundThrottling: false,
    },
  });
  pet.win = window;
  if (pet.kind === 'audio') {
    window.setAlwaysOnTop(true, 'screen-saver');
    try {
      window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    } catch {
      /* Windows 上部分版本不支持，忽略 */
    }
  } else {
    window.setFocusable(false);
    window.setIgnoreMouseEvents(true, { forward: true });
  }

  window.loadFile(path.join(RENDERER_DIR, 'pet.html'), { query: { id: pet.id } });
  window.on('closed', () => {
    pet.win = null;
  });
  return bounds;
}

function buildInitPayload(pet) {
  const base = {
    id: pet.id,
    kind: pet.kind,
    title: pet.displayTitle,
    fullName: pet.profile.fullName,
    hint: pet.profile.hint,
    credits: CREDIT_LINE,
    version: APP_VERSION,
    scale: pet.scale,
  };
  if (pet.kind === 'jelly') {
    return {
      ...base,
      style: pet.style,
      iconSide: layout.iconSideFor(pet.profile, pet.scale),
      marks: jellyMarkPaths(),
      styleNames: pet.profile.styleNames,
    };
  }
  return {
    ...base,
    avatarUrl: pet.content.avatarUrl,
    author: pet.content.author,
    custom: pet.content.custom,
    faceRatio: pet.faceRatio,
    animation: pet.profile.animation,
    insetX: pet.profile.insetX,
    insetY: pet.profile.insetY,
    captionBand: pet.profile.captionBand,
    fontSize: pet.profile.fontSize,
    captionRadius: pet.profile.captionRadius,
    captionBg: pet.profile.captionBg,
    volume: IS_SMOKE ? 0 : pet.volume,
    clips: pet.clips.map((clip) => ({
      id: clip.id,
      label: clip.label,
      url: clip.url,
      duration: clip.duration,
      excluded: pet.excludedIDs.has(clip.id),
    })),
  };
}

function sendToPet(pet, channel, payload) {
  if (!pet.win || pet.win.isDestroyed()) return;
  pet.win.webContents.send(channel, payload);
}

function showPetWindow(pet) {
  if (!pet.win || pet.win.isDestroyed() || !pet.visible) return;
  // smoke / chain-test 用隐藏窗口跑管线，不弹到用户桌面上。
  if (HIDDEN_MODE) return;
  if (pet.ready) pet.win.showInactive();
}

function setPetVisible(id, visible, { persist = true } = {}) {
  const pet = state.pets.get(id);
  if (!pet) return;
  pet.visible = visible;
  if (persist) {
    state.settings.pets[id].visible = visible;
    state.store.save();
  }
  if (!visible) {
    stopPlayback(pet);
    cancelCompanion(pet);
    if (pet.win && !pet.win.isDestroyed()) pet.win.hide();
  } else {
    if (pet.win && !pet.win.isDestroyed()) {
      if (pet.ready) pet.win.showInactive();
    }
  }
  refreshUi();
}

function stopPlayback(pet) {
  cancelCompanion(pet);
  if (pet.playTimer) {
    clearTimeout(pet.playTimer);
    pet.playTimer = null;
  }
  pet.playing = false;
  pet.currentClip = null;
  sendToPet(pet, 'pet-stop', {});
}

// ---------------------------------------------------------------------------
// 联动（hop / root）
// ---------------------------------------------------------------------------

function nextFromBag(pet, clips, key) {
  if (!clips.length) return null;
  const ids = clips.map((clip) => clip.id).sort((a, b) => a - b);
  const idKey = ids.join(',');
  let bag = pet.bags[key];
  if (!bag || bag.idKey !== idKey) {
    bag = pet.bags[key] = { idKey, remaining: [], last: null };
  }
  bag.remaining = bag.remaining.filter((id) => ids.includes(id));
  if (!bag.remaining.length) {
    bag.remaining = shuffle(ids);
    if (ids.length > 1 && bag.remaining[bag.remaining.length - 1] === bag.last) {
      const first = bag.remaining[0];
      bag.remaining[0] = bag.remaining[bag.remaining.length - 1];
      bag.remaining[bag.remaining.length - 1] = first;
    }
  }
  const id = bag.remaining.pop();
  bag.last = id;
  return pet.clipById.get(id) || null;
}

function manualPool(pet) {
  const pool = pet.clips.filter((clip) => !pet.excludedIDs.has(clip.id));
  return pool.length ? pool : pet.clips;
}

function companionPool(pet) {
  const profile = pet.profile;
  if (profile.companionIds) {
    return pet.clips.filter(
      (clip) =>
        profile.companionIds.includes(clip.id) &&
        (!profile.companionRespectsExclusions || !pet.excludedIDs.has(clip.id))
    );
  }
  return profile.companionRespectsExclusions
    ? pet.clips.filter((clip) => !pet.excludedIDs.has(clip.id))
    : pet.clips;
}

function pickManualClip(pet) {
  if (!pet.randomMode && pet.pinnedID != null && pet.clipById.has(pet.pinnedID)) {
    return pet.clipById.get(pet.pinnedID);
  }
  return nextFromBag(pet, manualPool(pet), 'manual') || pet.clips[0] || null;
}

function cancelCompanion(pet) {
  if (pet.pending) {
    clearTimeout(pet.pending);
    pet.pending = null;
  }
}

/** 播放一句，并在开口时广播 hop/root。 */
function playSpeech(pet, clip, hop, root) {
  if (!pet.visible || !pet.win || pet.win.isDestroyed()) return false;
  cancelCompanion(pet);
  if (pet.playTimer) {
    clearTimeout(pet.playTimer);
    pet.playTimer = null;
  }
  pet.playing = true;
  pet.currentClip = clip;
  sendToPet(pet, 'pet-play', {
    clip: {
      id: clip.id,
      label: clip.label,
      url: clip.url,
      duration: clip.duration,
    },
    volume: IS_SMOKE ? 0 : pet.volume,
    hop,
  });
  pet.playTimer = setTimeout(() => {
    pet.playing = false;
    pet.currentClip = null;
    pet.playTimer = null;
  }, Math.max(150, clip.duration * 1000 + 120));

  announce({ from: pet.id, clipID: clip.id, label: clip.label, duration: clip.duration, hop, root }, pet.id);
  return true;
}

function announce(speech, fromId) {
  if (!state.settings.hub.relayEnabled) return;
  if (TRACE) {
    console.log(
      `[relay] ${new Date().toISOString()} from=${speech.from} clip=${speech.clipID} hop=${speech.hop} root=${speech.root} duration=${speech.duration.toFixed(2)}`
    );
  }
  if (state.smoke) state.smoke.steps.push({ ...speech });
  for (const [id, pet] of state.pets) {
    if (id === fromId || pet.kind !== 'audio') continue;
    if (!pet.visible) continue;
    if (!pet.profile.reaction(speech)) continue;
    if (speech.hop >= 3) continue;
    scheduleCompanion(pet, speech);
  }
}

function scheduleCompanion(pet, speech) {
  cancelCompanion(pet);
  const clip = nextFromBag(pet, companionPool(pet), 'companion');
  if (!clip) return;
  // 和 macOS 一致：收到 hop==1 的话时把接话压紧到 0.2s，其余 0.3s。
  const overlap = speech.hop === 1 ? 0.2 : 0.3;
  const delay = Math.max(20, (speech.duration - overlap) * 1000);
  log(`[trace] ${pet.id} 准备接话：${delay.toFixed(0)}ms 后播 ${clip.id}（root=${speech.root} hop=${speech.hop + 1}）`);
  pet.pending = setTimeout(() => {
    pet.pending = null;
    if (!pet.visible) return;
    // 到点时自己正在播（手点/上一捧）→ 放弃这一捧，不叠音。
    if (pet.playing) {
      log(`[trace] ${pet.id} 正在播放，放弃这一捧`);
      return;
    }
    playSpeech(pet, clip, speech.hop + 1, speech.root);
  }, delay);
}

function manualPlay(id) {
  const pet = state.pets.get(id);
  if (!pet || pet.kind !== 'audio' || !pet.visible) return;
  cancelCompanion(pet);
  const clip = pickManualClip(pet);
  if (!clip) return;
  playSpeech(pet, clip, 0, id);
  if (IS_SMOKE) log(`[smoke] 模拟点击 ${id} → clip ${clip.id}`);
}

// ---------------------------------------------------------------------------
// 大小 / 排列 / 拖动
// ---------------------------------------------------------------------------

function setPetScale(id, scale, { propagate = false, persist = true } = {}) {
  const pet = state.pets.get(id);
  if (!pet) return;
  const next = clampScale(scale, pet.scale);
  pet.scale = next;
  if (persist) {
    state.settings.pets[id].scale = next;
    state.store.save();
  }
  if (pet.win && !pet.win.isDestroyed()) {
    const size = windowSizeFor(pet);
    const bounds = layout.resizeAnchored(pet.win.getBounds(), size, pet.kind);
    applyBounds(pet, bounds, persist);
  }
  if (propagate) {
    for (const otherId of ORDER) {
      if (otherId === id) continue;
      setPetScale(otherId, next, { propagate: false, persist });
    }
  }
  if (pet.kind === 'jelly') sendToPet(pet, 'pet-style', { style: pet.style, scale: next });
  refreshUi();
}

function applyGlobalScale(scale) {
  for (const id of ORDER) setPetScale(id, scale, { propagate: false, persist: true });
}

function arrange(mode) {
  const area = arrangementArea();
  const states = statesForLayout();
  let targets = null;
  if (mode === 'compact') {
    targets = layout.compactLayout(states, area);
  } else if (mode === 'stage') {
    for (const [id, scale] of Object.entries(LAYOUT.stageScales)) {
      state.pets.get(id).scale = scale;
      state.settings.pets[id].scale = scale;
    }
    const stageStates = statesForLayout();
    targets = layout.stageLayout(stageStates, area);
  } else {
    targets = layout.defaultLayout(states, area);
  }
  for (const id of ORDER) {
    const pet = state.pets.get(id);
    if (!pet.win || pet.win.isDestroyed()) continue;
    applyBounds(pet, targets[id], true);
  }
  if (mode === 'stage') {
    // 后放的在上层：果冻 → 太对了 → 峰哥 → 薄肌
    for (const id of ['jelly', 'sunpet', 'fengge', 'shaolan']) {
      const pet = state.pets.get(id);
      if (pet.visible && pet.win && !pet.win.isDestroyed()) pet.win.moveTop();
    }
    state.settings.hub.groupDrag = true;
  }
  state.store.save();
  refreshUi();
  log(`[layout] ${mode} 排列完成`);
}

function resetPetPosition(id) {
  const pet = state.pets.get(id);
  if (!pet) return;
  const targets = layout.defaultLayout(statesForLayout(), arrangementArea());
  applyBounds(pet, targets[id], true);
  refreshUi();
}

function resetAllPositions() {
  arrange('default');
}

function beginDrag(pet) {
  const cursor = screen.getCursorScreenPoint();
  const starts = new Map();
  for (const id of ORDER) {
    const other = state.pets.get(id);
    if (other.win && !other.win.isDestroyed()) starts.set(id, other.win.getBounds());
  }
  pet.drag = { startCursor: cursor, starts, dragged: false };
}

function moveDrag(pet) {
  const drag = pet.drag;
  if (!drag || pet.kind !== 'audio') return;
  const cursor = screen.getCursorScreenPoint();
  const dx = cursor.x - drag.startCursor.x;
  const dy = cursor.y - drag.startCursor.y;
  if (!drag.dragged && Math.hypot(dx, dy) > 4) drag.dragged = true;
  if (!drag.dragged) return;
  const targets = state.settings.hub.groupDrag ? drag.starts : new Map([[pet.id, drag.starts.get(pet.id)]]);
  for (const [id, start] of targets) {
    const target = state.pets.get(id);
    if (!target || !target.win || target.win.isDestroyed()) continue;
    target.win.setPosition(Math.round(start.x + dx), Math.round(start.y + dy), false);
  }
}

function endDrag(pet) {
  const drag = pet.drag;
  pet.drag = null;
  if (!drag) return;
  if (drag.dragged) {
    for (const id of ORDER) {
      const target = state.pets.get(id);
      if (!target || !target.win || target.win.isDestroyed()) continue;
      const bounds = target.win.getBounds();
      state.settings.pets[id].x = bounds.x;
      state.settings.pets[id].y = bounds.y;
    }
    state.store.save();
    return;
  }
  // 没拖动 → 当成点击（左键）
  manualPlay(pet.id);
}

// ---------------------------------------------------------------------------
// 菜单
// ---------------------------------------------------------------------------

function refreshUi() {
  rebuildTray();
  pushSettingsState();
}

function buildVisibilityMenu() {
  return ORDER.map((id) => {
    const pet = state.pets.get(id);
    return {
      label: pet.displayTitle,
      type: 'checkbox',
      checked: pet.visible,
      click: () => setPetVisible(id, !pet.visible),
    };
  });
}

function buildVolumeMenu(pet) {
  return VOLUME_STEPS.map((value) => ({
    label: value === 0 ? '静音' : `${Math.round(value * 100)}%`,
    type: 'radio',
    checked: Math.abs(pet.volume - value) < 0.01,
    click: () => {
      pet.volume = value;
      state.settings.pets[pet.id].volume = value;
      state.store.save();
      refreshUi();
      log(`[audio] ${pet.id} 音量 ${value}`);
    },
  }));
}

function buildSizeMenu(pet) {
  const presets = [0.5, 0.75, 1, 1.25, 1.5, 1.8];
  return presets.map((value) => ({
    label: `${Math.round(value * 100)}%`,
    type: 'radio',
    checked: Math.abs(pet.scale - value) < 0.01,
    click: () =>
      setPetScale(pet.id, value, { propagate: state.settings.hub.linkSize }),
  }));
}

function buildClipChoiceMenu(pet) {
  return pet.clips.map((clip) => ({
    label: `${String(clip.id).padStart(2, '0')}  ${clip.label}`,
    type: 'radio',
    checked: !pet.randomMode && pet.pinnedID === clip.id,
    click: () => {
      pet.randomMode = false;
      pet.pinnedID = clip.id;
      state.settings.pets[pet.id].randomMode = false;
      state.settings.pets[pet.id].pinnedID = clip.id;
      state.store.save();
      refreshUi();
      playSpeech(pet, clip, 0, pet.id);
    },
  }));
}

function buildExclusionMenu(pet) {
  const items = pet.clips.map((clip) => ({
    label: `${String(clip.id).padStart(2, '0')}  ${clip.label}`,
    type: 'checkbox',
    checked: !pet.excludedIDs.has(clip.id),
    click: () => {
      if (pet.excludedIDs.has(clip.id)) pet.excludedIDs.delete(clip.id);
      else pet.excludedIDs.add(clip.id);
      state.settings.pets[pet.id].excludedIDs = [...pet.excludedIDs].sort((a, b) => a - b);
      state.store.save();
      refreshUi();
    },
  }));
  items.push({ type: 'separator' });
  items.push({
    label: '全部恢复',
    click: () => {
      pet.excludedIDs.clear();
      state.settings.pets[pet.id].excludedIDs = [];
      state.store.save();
      refreshUi();
    },
  });
  return items;
}

function buildAudioPetMenu(pet) {
  const customSuffix = pet.content.custom ? '自定义' : '原声';
  return [
    { label: `${pet.profile.menuHeader} · ${customSuffix} · ${pet.clips.length} 句`, enabled: false },
    {
      label: pet.randomMode ? '点击随机播放 · 一轮内不重复' : '点击播放固定那句',
      enabled: false,
    },
    { type: 'separator' },
    { label: '随机说一句', click: () => manualPlay(pet.id) },
    { label: '挑一句', submenu: buildClipChoiceMenu(pet) },
    {
      label: '播放方式',
      submenu: [
        {
          label: '随机一句（一轮不重复）',
          type: 'radio',
          checked: pet.randomMode,
          click: () => {
            pet.randomMode = true;
            state.settings.pets[pet.id].randomMode = true;
            state.store.save();
            refreshUi();
          },
        },
        {
          label: pet.pinnedID != null ? `固定播放第 ${pet.pinnedID} 句` : '固定播放（先挑一句）',
          type: 'radio',
          checked: !pet.randomMode,
          click: () => {
            pet.randomMode = false;
            if (pet.pinnedID == null) pet.pinnedID = manualPool(pet)[0]?.id ?? null;
            state.settings.pets[pet.id].randomMode = false;
            state.settings.pets[pet.id].pinnedID = pet.pinnedID;
            state.store.save();
            refreshUi();
          },
        },
      ],
    },
    { label: '轮播内容（取消勾选＝不参与随机）', submenu: buildExclusionMenu(pet) },
    { label: '停止播放', click: () => stopPlayback(pet) },
    { type: 'separator' },
    { label: pet.profile.idleRelayStatus, enabled: false },
    { label: '音量', submenu: buildVolumeMenu(pet) },
    { label: '大小', submenu: buildSizeMenu(pet) },
    { label: '移回屏幕右下角', click: () => resetPetPosition(pet.id) },
    { type: 'separator' },
    { label: `隐藏${pet.profile.title}`, click: () => setPetVisible(pet.id, false) },
  ];
}

function buildJellyMenu() {
  const pet = state.pets.get('jelly');
  const styleNames = pet.profile.styleNames;
  return [
    { label: '果冻桌宠 · Claude / GPT / Gemini 标志', enabled: false },
    { label: '按一下会肿 · 拖开会拉长 · 松手弹回', enabled: false },
    { type: 'separator' },
    { label: '回到原位', click: () => resetPetPosition('jelly') },
    { label: '大小', submenu: buildSizeMenu(pet) },
    {
      label: '图标',
      submenu: [0, 1, 2].map((style) => ({
        label: styleNames[style],
        type: 'radio',
        checked: pet.style === style,
        click: () => {
          pet.style = style;
          state.settings.pets.jelly.style = style;
          state.store.save();
          sendToPet(pet, 'pet-style', { style, scale: pet.scale });
          refreshUi();
        },
      })),
    },
    { type: 'separator' },
    { label: '隐藏果冻', click: () => setPetVisible('jelly', false) },
  ];
}

function buildPetMenu(id) {
  const pet = state.pets.get(id);
  if (!pet) return [];
  return pet.kind === 'audio' ? buildAudioPetMenu(pet) : buildJellyMenu();
}

function buildTrayMenu() {
  const custom = state.custom.content;
  const globalScale = state.pets.get('shaolan')?.scale ?? 1;
  const sizePresets = [0.5, 0.75, 1, 1.25, 1.5, 1.8].map((value) => ({
    label: `${Math.round(value * 100)}%`,
    type: 'radio',
    checked: Math.abs(globalScale - value) < 0.01,
    click: () => applyGlobalScale(value),
  }));

  return [
    { label: '桌宠合集 · 四只', enabled: false },
    { label: '显示 / 隐藏', submenu: buildVisibilityMenu() },
    { type: 'separator' },
    ...ORDER.map((id) => ({
      label: state.pets.get(id).displayTitle,
      submenu: buildPetMenu(id),
    })),
    { type: 'separator' },
    {
      label: '自定义桌宠',
      submenu: [
        {
          label: custom ? `当前：${custom.name}（替换薄肌）` : '当前：原版薄肌',
          enabled: false,
        },
        { label: '导入 petpack.json 文件夹…', click: () => importPetPack() },
        { label: '打开内容包文件夹', click: () => openPackFolder() },
        ...(custom ? [{ label: '恢复原版薄肌', click: () => restoreBuiltinHead() }] : []),
      ],
    },
    { type: 'separator' },
    {
      label: '捧哏联动',
      type: 'checkbox',
      checked: state.settings.hub.relayEnabled,
      click: () => setRelayEnabled(!state.settings.hub.relayEnabled),
    },
    {
      label: '大小联动（改一只，四只一起变）',
      type: 'checkbox',
      checked: state.settings.hub.linkSize,
      click: () => {
        state.settings.hub.linkSize = !state.settings.hub.linkSize;
        state.store.save();
        refreshUi();
      },
    },
    {
      label: '绑定相对位置（拖一只，四只一起动）',
      type: 'checkbox',
      checked: state.settings.hub.groupDrag,
      click: () => {
        state.settings.hub.groupDrag = !state.settings.hub.groupDrag;
        state.store.save();
        refreshUi();
      },
    },
    { label: '大小', submenu: sizePresets },
    { label: '全部显示', click: () => ORDER.forEach((id) => setPetVisible(id, true)) },
    { label: '全部隐藏', click: () => ORDER.forEach((id) => setPetVisible(id, false)) },
    { label: '全部归位', click: () => resetAllPositions() },
    { label: '紧凑排列（一键收拢）', click: () => arrange('compact') },
    { label: '捧哏排列（合影）', click: () => arrange('stage') },
    { type: 'separator' },
    { label: '设置…', click: () => showSettings() },
    { label: '关于桌宠合集', click: () => showAbout() },
    { label: '退出桌宠合集', click: () => quitApp() },
  ];
}

function rebuildTray() {
  if (!state.tray || state.tray.isDestroyed()) return;
  state.tray.setContextMenu(Menu.buildFromTemplate(buildTrayMenu()));
}

function installTray() {
  const iconPath = path.join(ASSETS_DIR, 'AppIcon.png');
  let image = nativeImage.createEmpty();
  if (fs.existsSync(iconPath)) {
    const size = process.platform === 'darwin' ? 18 : 16;
    image = nativeImage.createFromPath(iconPath).resize({ width: size, height: size });
  }
  state.tray = new Tray(image);
  state.tray.setToolTip('桌宠合集 · 右键打开菜单');
  rebuildTray();
  state.tray.on('double-click', () => showSettings());
}

function setRelayEnabled(enabled) {
  state.settings.hub.relayEnabled = enabled;
  state.store.save();
  if (!enabled) {
    for (const pet of state.pets.values()) if (pet.kind === 'audio') cancelCompanion(pet);
  }
  refreshUi();
  log(`[relay] enabled=${enabled}`);
}

function showPetContextMenu(id) {
  const pet = state.pets.get(id);
  if (!pet || !pet.win || pet.win.isDestroyed()) return;
  const menu = Menu.buildFromTemplate(buildPetMenu(id));
  menu.popup({ window: pet.win });
}

// ---------------------------------------------------------------------------
// 设置窗口 / 关于
// ---------------------------------------------------------------------------

function settingsSnapshot() {
  return {
    version: APP_VERSION,
    platform: process.platform,
    relayEnabled: state.settings.hub.relayEnabled,
    linkSize: state.settings.hub.linkSize,
    groupDrag: state.settings.hub.groupDrag,
    custom: {
      installed: Boolean(state.custom.content),
      name: state.custom.content?.name ?? null,
      author: state.custom.content?.author ?? '',
      clipCount: state.custom.content?.clips.length ?? 0,
      error: state.custom.error,
    },
    credits: CREDIT_LINE,
    creditDetail: CREDIT_DETAIL,
    upstream: UPSTREAM,
    pets: ORDER.map((id) => {
      const pet = state.pets.get(id);
      return {
        id,
        title: pet.displayTitle,
        kind: pet.kind,
        visible: pet.visible,
        scale: pet.scale,
        volume: pet.volume,
        randomMode: pet.randomMode,
        pinnedID: pet.pinnedID,
        excludedCount: pet.excludedIDs.size,
        clipCount: pet.clips.length,
        style: pet.style,
      };
    }),
  };
}

function pushSettingsState() {
  if (!state.settingsWin || state.settingsWin.isDestroyed()) return;
  state.settingsWin.webContents.send('settings:state', settingsSnapshot());
}

function showSettings(shouldShow = true) {
  if (state.settingsWin && !state.settingsWin.isDestroyed()) {
    if (shouldShow) {
      state.settingsWin.show();
      state.settingsWin.focus();
    }
    pushSettingsState();
    return state.settingsWin;
  }
  const win = new BrowserWindow({
    width: 640,
    height: 860,
    minWidth: 520,
    minHeight: 620,
    show: false,
    title: '桌宠合集 · 设置（整合自 ShaolanPet / SunPet / FengGe-Desktop-Pet / JellyPet）',
    backgroundColor: '#16181d',
    autoHideMenuBar: true,
    icon: path.join(ASSETS_DIR, 'AppIcon.png'),
    webPreferences: {
      preload: PRELOAD,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  state.settingsWin = win;
  win.loadFile(path.join(RENDERER_DIR, 'settings.html'));
  win.once('ready-to-show', () => {
    if (shouldShow) win.show();
    pushSettingsState();
  });
  win.on('close', (event) => {
    if (!state.quitting) {
      event.preventDefault();
      win.hide();
    }
  });
  win.on('closed', () => {
    state.settingsWin = null;
  });
  return win;
}

function openCreditsFile() {
  const candidates = [CREDITS_FILE, repoDocPath('CREDITS.md'), docPath('WINDOWS.md'), repoDocPath('docs/WINDOWS.md')];
  for (const candidate of candidates) {
    try {
      if (fs.existsSync(candidate)) {
        shell.openPath(candidate);
        return;
      }
    } catch {
      /* 继续试下一个 */
    }
  }
  dialog.showMessageBox({
    type: 'info',
    title: 'CREDITS',
    message: '整合来源',
    detail: `${CREDIT_LINE}\n\n${CREDIT_DETAIL}`,
  });
}

function showAbout() {
  const upstreamLines = UPSTREAM.map(
    (item) => `· ${item.name} —— ${item.author}（${item.license}）\n  ${item.url}`
  ).join('\n');
  const detail = [
    CREDIT_LINE,
    '',
    CREDIT_DETAIL,
    '',
    '四个上游项目：',
    upstreamLines,
    '',
    `版本 ${APP_VERSION} · Windows 版（Electron）· 不联网 · 只读本地素材`,
  ].join('\n');
  dialog
    .showMessageBox({
      type: 'info',
      title: '关于桌宠合集',
      message: `桌宠合集 PetHub ${APP_VERSION} · Windows 版`,
      detail,
      buttons: ['打开 CREDITS.md', '确定'],
      defaultId: 1,
      cancelId: 1,
      noLink: true,
    })
    .then((result) => {
      if (result.response === 0) openCreditsFile();
    });
}

// ---------------------------------------------------------------------------
// PetPack 导入 / 恢复
// ---------------------------------------------------------------------------

function openPackFolder() {
  const base = app.getPath('userData');
  fs.mkdirSync(base, { recursive: true });
  shell.openPath(base);
}

async function importPetPack() {
  const parent =
    state.settingsWin && !state.settingsWin.isDestroyed() && state.settingsWin.isVisible()
      ? state.settingsWin
      : undefined;
  const picked = await dialog.showOpenDialog(parent, {
    title: '选择包含 petpack.json 的文件夹',
    properties: ['openDirectory'],
    buttonLabel: '导入',
  });
  if (picked.canceled || !picked.filePaths.length) return;
  const base = app.getPath('userData');
  try {
    const result = await petpack.installPack(picked.filePaths[0], base, state.probe);
    state.custom.content = result.content;
    state.custom.error = null;
    state.custom.signature = petpack.contentSignature(result.content);
    state.settings.customPack = {
      installed: true,
      name: result.content.name,
      signature: state.custom.signature,
    };
    // 内容变了：旧的勾选 / 固定句 id 对不上，重置（音量/大小/位置保留）。
    resetShaolanClipState();
    reloadHeadPetContent();
    state.store.save();
    refreshUi();
    sendToPet(state.pets.get('shaolan'), 'pet-notice', {
      text: `已换成 ${result.content.name}`,
      duration: 3500,
    });
    log(`[petpack] 已导入 ${result.content.name}（${result.content.clips.length} 句）`);
  } catch (error) {
    console.error(`[petpack] 导入失败：${error.message}`);
    const options = {
      type: 'error',
      title: '导入桌宠包失败',
      message: '这个内容包没有通过校验',
      detail: error.message,
    };
    if (parent) dialog.showMessageBox(parent, options);
    else dialog.showMessageBox(options);
  }
}

function restoreBuiltinHead() {
  try {
    petpack.removePack(app.getPath('userData'));
  } catch (error) {
    dialog.showMessageBox({
      type: 'error',
      title: '恢复原版薄肌失败',
      message: error.message,
    });
    return;
  }
  state.custom.content = null;
  state.custom.signature = null;
  state.custom.error = null;
  state.settings.customPack = { installed: false, name: null, signature: null };
  resetShaolanClipState();
  reloadHeadPetContent();
  state.store.save();
  refreshUi();
  sendToPet(state.pets.get('shaolan'), 'pet-notice', { text: '已恢复原版薄肌', duration: 3500 });
}

function resetShaolanClipState() {
  const pet = state.pets.get('shaolan');
  state.settings.pets.shaolan.pinnedID = null;
  state.settings.pets.shaolan.randomMode = true;
  pet.pinnedID = null;
  pet.randomMode = true;
  pet.excludedIDs.clear();
  state.settings.pets.shaolan.excludedIDs = [];
}

function reloadHeadPetContent() {
  const pet = state.pets.get('shaolan');
  if (!pet || !pet.win || pet.win.isDestroyed()) return;
  stopPlayback(pet);
  const content = buildContentFor('shaolan');
  pet.content = content;
  pet.displayTitle = content.displayTitle;
  pet.avatarPath = content.avatarPath;
  pet.faceRatio = content.faceRatio;
  pet.clips = content.clips;
  pet.clipById = new Map(content.clips.map((clip) => [clip.id, clip]));
  pet.bags = {};
  // 按新头像比例重算窗口高度，底边/水平中心不动。
  const size = windowSizeFor(pet);
  applyBounds(pet, layout.resizeAnchored(pet.win.getBounds(), size, pet.kind), true);
  sendToPet(pet, 'pet-reload', buildInitPayload(pet));
  refreshUi();
}

/** 启动时读取已安装内容包；坏包只告警并回退内置，不阻塞 App 启动。 */
async function loadInstalledPack() {
  const headDir = path.join(app.getPath('userData'), 'HeadPet');
  if (!fs.existsSync(headDir)) {
    state.settings.customPack = { installed: false, name: null, signature: null };
    return;
  }
  try {
    const content = await petpack.validatePack(headDir, state.probe);
    const signature = petpack.contentSignature(content);
    state.custom.content = content;
    state.custom.signature = signature;
    const stored = state.settings.customPack;
    state.settings.customPack = { installed: true, name: content.name, signature };
    if (stored.signature !== signature) {
      state.settings.pets.shaolan.pinnedID = null;
      state.settings.pets.shaolan.randomMode = true;
      state.settings.pets.shaolan.excludedIDs = [];
      log('[petpack] 内容指纹变化，重置薄肌的勾选/固定句');
    }
  } catch (error) {
    state.custom.error = error.message;
    state.custom.content = null;
    state.settings.customPack = { installed: false, name: null, signature: null };
    console.error(`[petpack] 已安装内容包无效：${error.message}`);
    dialog.showMessageBox({
      type: 'warning',
      title: '自定义桌宠读不出来',
      message: '已回退到原版薄肌；内容包文件夹保留，方便你修复或删除。',
      detail: `${error.message}\n\n文件夹：${headDir}`,
      buttons: ['打开文件夹', '继续用原版'],
      defaultId: 1,
      cancelId: 1,
    }).then((result) => {
      if (result.response === 0) shell.openPath(app.getPath('userData'));
    });
  }
}

// ---------------------------------------------------------------------------
// IPC
// ---------------------------------------------------------------------------

function petFromSender(event) {
  const sender = event.sender;
  for (const pet of state.pets.values()) {
    if (pet.win && !pet.win.isDestroyed() && pet.win.webContents === sender) return pet;
  }
  return null;
}

function registerIpc() {
  ipcMain.on('pet-ready', (event) => {
    const pet = petFromSender(event);
    if (!pet) return;
    pet.ready = true;
    sendToPet(pet, 'pet-init', buildInitPayload(pet));
    if (pet.visible) showPetWindow(pet);
  });

  ipcMain.on('pet-pointer', (event, payload) => {
    const pet = petFromSender(event);
    if (!pet || !payload) return;
    if (payload.type === 'down') {
      if (payload.button !== 0) return;
      if (pet.drag) return;
      if (pet.kind === 'jelly') return; // 果冻只在原地 Q 弹，窗口不跟着走
      beginDrag(pet);
    } else if (payload.type === 'move') {
      moveDrag(pet);
    } else if (payload.type === 'up') {
      endDrag(pet);
    } else if (payload.type === 'cancel') {
      pet.drag = null;
    }
  });

  ipcMain.on('pet-context-menu', (event) => {
    const pet = petFromSender(event);
    if (pet) showPetContextMenu(pet.id);
  });

  ipcMain.on('pet-jelly-interactive', (event, inside) => {
    const pet = petFromSender(event);
    if (!pet || pet.kind !== 'jelly' || !pet.win || pet.win.isDestroyed()) return;
    try {
      pet.win.setIgnoreMouseEvents(!inside, { forward: true });
    } catch {
      /* 部分平台不支持 forward，退回整窗可点 */
      try {
        pet.win.setIgnoreMouseEvents(!inside);
      } catch {
        /* ignore */
      }
    }
  });

  ipcMain.on('pet-playback-ended', (event) => {
    const pet = petFromSender(event);
    if (!pet) return;
    if (pet.playTimer) {
      clearTimeout(pet.playTimer);
      pet.playTimer = null;
    }
    pet.playing = false;
    pet.currentClip = null;
  });

  ipcMain.on('pet-validate-result', (event, result) => {
    const pet = petFromSender(event);
    if (!pet) return;
    pet.validateResult = result;
    resolveValidateWaiter(pet, result);
  });

  ipcMain.handle('settings:get-state', () => settingsSnapshot());

  ipcMain.on('settings:command', (event, command) => {
    handleSettingsCommand(command).catch((error) => {
      console.error(`[settings] 命令 ${command?.type} 失败：${error.message}`);
    });
  });
}

function resolveValidateWaiter(pet, result) {
  if (!pet.validateWaiters.length) return;
  const waiters = pet.validateWaiters.splice(0);
  for (const resolve of waiters) resolve(result);
}

function waitForValidation(pet, timeoutMs = 30000) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(null), timeoutMs);
    pet.validateWaiters.push((result) => {
      clearTimeout(timer);
      resolve(result);
    });
    sendToPet(pet, 'pet-validate', {});
  });
}

async function handleSettingsCommand(command) {
  if (!command || typeof command.type !== 'string') return;
  switch (command.type) {
    case 'set-visible':
      setPetVisible(command.id, Boolean(command.visible));
      break;
    case 'set-all-visible':
      for (const id of ORDER) setPetVisible(id, Boolean(command.visible), { persist: false });
      state.store.save();
      break;
    case 'arrange':
      arrange(command.mode === 'compact' || command.mode === 'stage' ? command.mode : 'default');
      break;
    case 'reset-positions':
      resetAllPositions();
      break;
    case 'set-global-scale':
      applyGlobalScale(command.value);
      break;
    case 'set-pet-scale':
      setPetScale(command.id, command.value, { propagate: state.settings.hub.linkSize });
      break;
    case 'set-pet-volume':
      if (state.pets.has(command.id)) {
        const pet = state.pets.get(command.id);
        pet.volume = pickVolume(command.value, pet.volume);
        state.settings.pets[command.id].volume = pet.volume;
        state.store.save();
        refreshUi();
      }
      break;
    case 'set-link-size':
      state.settings.hub.linkSize = Boolean(command.value);
      state.store.save();
      refreshUi();
      break;
    case 'set-relay':
      setRelayEnabled(Boolean(command.value));
      break;
    case 'set-group-drag':
      state.settings.hub.groupDrag = Boolean(command.value);
      state.store.save();
      refreshUi();
      break;
    case 'set-jelly-style':
      if ([0, 1, 2].includes(command.value)) {
        const pet = state.pets.get('jelly');
        pet.style = command.value;
        state.settings.pets.jelly.style = command.value;
        state.store.save();
        sendToPet(pet, 'pet-style', { style: pet.style, scale: pet.scale });
        refreshUi();
      }
      break;
    case 'import-petpack':
      await importPetPack();
      break;
    case 'restore-builtin':
      restoreBuiltinHead();
      break;
    case 'open-pack-folder':
      openPackFolder();
      break;
    case 'open-credits':
      openCreditsFile();
      break;
    case 'about':
      showAbout();
      break;
    case 'quit':
      quitApp();
      break;
    default:
      log(`[settings] 未知命令：${command.type}`);
  }
}

// ---------------------------------------------------------------------------
// 启动 / 退出
// ---------------------------------------------------------------------------

function printState() {
  const custom = state.custom.content;
  console.log(
    `version=${APP_VERSION} relay=${state.settings.hub.relayEnabled ? 'on' : 'off'} linkSize=${
      state.settings.hub.linkSize ? 'on' : 'off'
    } groupDrag=${state.settings.hub.groupDrag ? 'on' : 'off'} pets=4 custom=${custom ? custom.name : 'builtin'}`
  );
  for (const id of ORDER) {
    const pet = state.pets.get(id);
    if (!pet || !pet.win || pet.win.isDestroyed()) {
      console.log(`${id} visible=${pet?.visible} window=off`);
      continue;
    }
    const bounds = pet.win.getBounds();
    const base = `${id} visible=${pet.visible} window=on size=${bounds.width}x${bounds.height} pos=${bounds.x},${bounds.y}`;
    if (pet.kind === 'audio') {
      console.log(
        `${base} clips=${pet.clips.length} scale=${pet.scale.toFixed(2)} volume=${pet.volume} mode=${
          pet.randomMode ? 'random' : 'fixed'
        } relay=${state.settings.hub.relayEnabled ? 'on' : 'off'} title=${pet.displayTitle} content=${
          pet.content.custom ? 'custom' : 'builtin'
        }`
      );
    } else {
      console.log(`${base} style=${pet.profile.styleNames[pet.style]} scale=${pet.scale.toFixed(2)}`);
    }
  }
}

/** 实测四步链（用当前 userData，可带已安装的自定义包）。 */
async function runChainTest() {
  const smoke = { started: Date.now(), steps: [], finished: false };
  state.smoke = smoke;
  let exitCode = 1;
  try {
    const ready = await waitForAllReady(20000);
    if (!ready) throw new Error('四只窗口没有全部加载完成');
    const shaolan = state.pets.get('shaolan');
    console.log(`[chain] 点薄肌起头：content=${shaolan.content.custom ? `custom:${shaolan.displayTitle}` : 'builtin'} clips=${shaolan.clips.length}`);
    const clickAt = Date.now();
    manualPlay('shaolan');
    let lastStepAt = clickAt;
    let lastCount = 0;
    while (Date.now() < clickAt + 30000) {
      if (smoke.steps.length !== lastCount) {
        lastCount = smoke.steps.length;
        lastStepAt = Date.now();
      }
      if (smoke.steps.length >= 4 && Date.now() - lastStepAt > 2000) break;
      await sleep(100);
    }
    await sleep(1500);
    const expected = [
      ['shaolan', 0],
      ['sunpet', 1],
      ['fengge', 2],
      ['sunpet', 3],
    ];
    if (smoke.steps.length !== 4) throw new Error(`应该有 4 步，实际 ${smoke.steps.length} 步`);
    smoke.steps.forEach((step, index) => {
      const [from, hop] = expected[index];
      if (step.from !== from || step.hop !== hop || step.root !== 'shaolan') {
        throw new Error(
          `第 ${index + 1} 步不对：from=${step.from} hop=${step.hop} root=${step.root}，期望 from=${from} hop=${hop} root=shaolan`
        );
      }
      console.log(
        `[chain] ${index + 1}/4 from=${step.from} hop=${step.hop} root=${step.root} clip=${String(step.clipID).padStart(2, '0')} “${step.label}”`
      );
    });
    console.log(
      `PASS 四步捧哏链：shaolan > sunpet > fengge > sunpet，root 全 shaolan（content=${
        shaolan.content.custom ? `custom:${shaolan.displayTitle}` : 'builtin'
      }）`
    );
    exitCode = 0;
  } catch (error) {
    console.log(`FAIL ${error.message}`);
  } finally {
    state.quitting = true;
    if (state.store) state.store.saveNow();
    if (state.probe) state.probe.destroy();
    for (const pet of state.pets.values()) {
      if (pet.win && !pet.win.isDestroyed()) pet.win.destroy();
    }
    app.exit(exitCode);
  }
}

async function createAllPets() {
  state.probe = new AssetProbe();
  await loadInstalledPack();

  // 先起薄肌（链头）的内容，其它两只照旧；果冻只有标志。
  for (const id of ORDER) {
    const profile = PET_PROFILES[id];
    const content = profile.kind === 'audio' ? buildContentFor(id) : null;
    const pet = createPetRuntime(id, content);
    state.pets.set(id, pet);
  }
  for (const id of ORDER) createPetWindow(state.pets.get(id));
  for (const id of ORDER) {
    const pet = state.pets.get(id);
    if (pet.kind === 'audio') {
      state.settings.pets[id].excludedIDs = [...pet.excludedIDs].sort((a, b) => a - b);
    }
  }
  state.store.save();
  await waitForAllReady(20000);
}

function waitForAllReady(timeoutMs) {
  const started = Date.now();
  return new Promise((resolve) => {
    const tick = () => {
      const allReady = ORDER.every((id) => state.pets.get(id)?.ready);
      if (allReady || Date.now() - started > timeoutMs) {
        resolve(allReady);
        return;
      }
      setTimeout(tick, 100);
    };
    tick();
  });
}

function showStartupHints() {
  for (const pet of state.pets.values()) {
    if (pet.kind !== 'audio' || !pet.visible) continue;
    sendToPet(pet, 'pet-notice', { text: pet.profile.startupHint, duration: 5000 });
  }
}

function quitApp() {
  state.quitting = true;
  if (state.store) state.store.saveNow();
  if (state.probe) state.probe.destroy();
  if (state.tray) state.tray.destroy();
  for (const pet of state.pets.values()) {
    if (pet.win && !pet.win.isDestroyed()) pet.win.destroy();
  }
  if (state.settingsWin && !state.settingsWin.isDestroyed()) state.settingsWin.destroy();
  app.quit();
}

// ---------------------------------------------------------------------------
// smoke：自动验收（npm run smoke）
// ---------------------------------------------------------------------------

function smokeLine(message) {
  console.log(message);
}

async function runSmoke() {
  const smoke = {
    started: Date.now(),
    steps: [],
    finished: false,
  };
  state.smoke = smoke;
  const deadline = setTimeout(() => {
    smokeLine('FAIL smoke 超时：四步链没有在 60 秒内跑完');
    finishSmoke(1);
  }, 60000);

  const finishSmoke = (code) => {
    if (smoke.finished) return;
    smoke.finished = true;
    clearTimeout(deadline);
    try {
      state.store.saveNow();
    } catch {
      /* ignore */
    }
    if (state.probe) state.probe.destroy();
    for (const pet of state.pets.values()) {
      if (pet.win && !pet.win.isDestroyed()) pet.win.destroy();
    }
    if (IS_SMOKE) {
      try {
        fs.rmSync(app.getPath('userData'), { recursive: true, force: true });
      } catch {
        /* ignore */
      }
    }
    app.exit(code);
  };

  const fail = (message) => {
    smokeLine(`FAIL ${message}`);
    finishSmoke(1);
  };

  try {
    smokeLine(`[smoke] PetHub ${APP_VERSION} · electron ${process.versions.electron} · node ${process.versions.node}`);
    smokeLine(`[smoke] assets=${ASSETS_DIR} userData=${app.getPath('userData')}`);

    const ready = await waitForAllReady(20000);
    if (!ready) return fail('四只窗口没有全部加载完成');

    const windows = BrowserWindow.getAllWindows().filter((win) => !win.isDestroyed());

    // 一、窗口与布局
    const sizeLines = [];
    for (const id of ORDER) {
      const pet = state.pets.get(id);
      const bounds = pet.win.getBounds();
      if (!(bounds.width > 0 && bounds.height > 0)) return fail(`${id} 窗口尺寸异常：${bounds.width}x${bounds.height}`);
      const expect = windowSizeFor(pet);
      if (bounds.width !== expect.width || bounds.height !== expect.height) {
        return fail(`${id} 窗口尺寸和计算值不一致：${bounds.width}x${bounds.height} != ${expect.width}x${expect.height}`);
      }
      sizeLines.push(`${id}=${bounds.width}x${bounds.height}@${bounds.x},${bounds.y}`);
    }
    if (windows.length !== ORDER.length) {
      return fail(`窗口数量不对：${windows.length}（期望 ${ORDER.length}）`);
    }
    smokeLine(`[smoke] windows=${windows.length} ${sizeLines.join(' ')}`);

    // 二、素材可读：让每个 renderer 解码头像/全部音频/标志
    const validationResults = await Promise.all(
      ORDER.map(async (id) => {
        const pet = state.pets.get(id);
        const result = await waitForValidation(pet, 30000);
        return { id, result };
      })
    );
    const expectedClips = { shaolan: 37, sunpet: 28, fengge: 11, jelly: 0 };
    for (const { id, result } of validationResults) {
      if (!result) return fail(`${id} 素材校验超时`);
      if (!result.ok) return fail(`${id} 素材校验失败：${JSON.stringify(result)}`);
      if (id === 'jelly') {
        const marks = Object.keys(result.marks || {}).length;
        if (marks !== 3) return fail(`果冻标志数量不对：${marks}`);
        smokeLine(`[smoke] validate jelly marks=${marks}/3 ok`);
        continue;
      }
      if (result.clipCount !== expectedClips[id]) {
        return fail(`${id} 素材句数不对：${result.clipCount}（期望 ${expectedClips[id]}）`);
      }
      if (result.badClips?.length) {
        return fail(`${id} 有 ${result.badClips.length} 条音频解码失败/过短：${result.badClips.slice(0, 3).join(', ')}`);
      }
      if (!(result.avatar?.ok && result.avatar.width > 0)) return fail(`${id} 头像解码失败`);
      smokeLine(
        `[smoke] validate ${id} clips=${result.clipCount}/${expectedClips[id]} avatar=${result.avatar.width}x${result.avatar.height} ok`
      );
    }

    // 三、四步捧哏链：模拟点薄肌
    smoke.steps = [];
    const clickAt = Date.now();
    manualPlay('shaolan');
    smokeLine('[smoke] click shaolan ...');
    const waitDeadline = clickAt + 30000;
    let lastStepAt = clickAt;
    let lastCount = 0;
    while (Date.now() < waitDeadline) {
      if (smoke.steps.length !== lastCount) {
        lastCount = smoke.steps.length;
        lastStepAt = Date.now();
      }
      if (smoke.steps.length >= 4 && Date.now() - lastStepAt > 2000) break;
      await sleep(100);
    }
    // 再多等 1.5 秒，确认没有第五句
    await sleep(1500);

    const expected = [
      { from: 'shaolan', hop: 0, root: 'shaolan' },
      { from: 'sunpet', hop: 1, root: 'shaolan' },
      { from: 'fengge', hop: 2, root: 'shaolan' },
      { from: 'sunpet', hop: 3, root: 'shaolan' },
    ];
    const steps = smoke.steps;
    smokeLine(`[smoke] relay steps=${steps.length}`);
    for (let index = 0; index < expected.length; index += 1) {
      const want = expected[index];
      const got = steps[index];
      if (!got) return fail(`四步链缺第 ${index + 1} 步（from=${want.from} hop=${want.hop}）`);
      if (got.from !== want.from || got.hop !== want.hop || got.root !== want.root) {
        return fail(
          `四步链第 ${index + 1} 步不对：from=${got.from} hop=${got.hop} root=${got.root}，期望 from=${want.from} hop=${want.hop} root=${want.root}`
        );
      }
      if (!(got.duration > 0.1) || !got.label) return fail(`第 ${index + 1} 步缺 label/duration`);
      smokeLine(
        `[smoke] step ${index + 1}/4 from=${got.from} hop=${got.hop} root=${got.root} clip=${String(got.clipID).padStart(2, '0')} “${got.label}”`
      );
    }
    const extra = steps.slice(expected.length).filter((speech) => speech.hop >= 0);
    if (extra.length) {
      return fail(`四步链之后不该再有接话，却多出 ${extra.length} 句：${extra.map((s) => `${s.from} hop${s.hop}`).join(', ')}`);
    }
    smokeLine('[smoke] 第 4 步之后 1.5s 内没有第五句');

    // 四、设置 / 隐藏 / 大小联动的小闭环，确认 IPC 与状态没坏
    const beforeScale = state.pets.get('sunpet').scale;
    setPetScale('sunpet', 1.25, { propagate: false });
    if (Math.abs(state.pets.get('sunpet').scale - 1.25) > 0.001) return fail('set-pet-scale 没有生效');
    setPetScale('sunpet', beforeScale, { propagate: false });
    setRelayEnabled(false);
    if (state.settings.hub.relayEnabled !== false) return fail('set-relay(false) 没有生效');
    setRelayEnabled(true);
    const jellyPet = state.pets.get('jelly');
    setPetVisible('jelly', false, { persist: false });
    if (jellyPet.visible !== false) return fail('set-visible(false) 没有生效');
    setPetVisible('jelly', true, { persist: false });
    state.store.saveNow();
    try {
      const saved = JSON.parse(fs.readFileSync(state.store.file, 'utf8'));
      if (!saved.hub || saved.hub.relayEnabled !== true) return fail('settings.json 没有写回 relayEnabled');
      if (!saved.pets || !saved.pets.shaolan) return fail('settings.json 缺少 pets.shaolan');
    } catch (error) {
      return fail(`settings.json 读写失败：${error.message}`);
    }
    smokeLine('[smoke] settings/scale/visibility/relay IPC ok; settings.json 持久化 ok');

    // 五、托盘菜单结构：不真的弹菜单，只构建一遍看有没有缺项
    const trayLabels = buildTrayMenu().map((item) => item.label).filter(Boolean);
    const requiredTray = ['显示 / 隐藏', '自定义桌宠', '捧哏联动', '设置…', '关于桌宠合集', '退出桌宠合集'];
    for (const required of requiredTray) {
      if (!trayLabels.includes(required)) return fail(`托盘菜单缺少「${required}」`);
    }
    for (const id of ORDER) buildPetMenu(id);
    smokeLine(`[smoke] tray menu ok（${trayLabels.length} 项，四只右键菜单可构建）`);

    // 六、设置窗口 IPC：开一个隐藏的设置窗口，从 DOM 上真的点/拖一下
    const settingsWin = showSettings(false);
    if (!settingsWin) return fail('设置窗口没有创建出来');
    if (settingsWin.webContents.isLoading()) {
      await new Promise((resolve) => settingsWin.webContents.once('did-finish-load', resolve));
    }
    await sleep(500);
    const ui = await settingsWin.webContents.executeJavaScript(
      `(async () => {
        const link = document.getElementById('link-size');
        const before = link.checked;
        link.click();
        await new Promise((r) => setTimeout(r, 250));
        const toggled = link.checked;
        link.click();
        await new Promise((r) => setTimeout(r, 250));
        const restored = link.checked;
        const credit = document.getElementById('credit-line').textContent || '';
        const slider = document.getElementById('global-scale');
        slider.value = '150';
        slider.dispatchEvent(new Event('input', { bubbles: true }));
        return { before, toggled, restored, credit };
      })()`,
      true
    );
    await sleep(700);
    if (!(ui.before === true && ui.toggled === false && ui.restored === true)) {
      return fail(`设置窗口「大小联动」没有走通：${JSON.stringify(ui)}`);
    }
    if (!ui.credit.includes('整合自') || !ui.credit.includes('JellyPet 无 LICENSE')) {
      return fail('设置窗口缺少「整合自 … / JellyPet 无 LICENSE」版权声明');
    }
    const scaled = ORDER.map((id) => state.pets.get(id).scale);
    if (!scaled.every((value) => Math.abs(value - 1.5) < 0.01)) {
      return fail(`设置窗口全局限滑块没有让四只一起变：${scaled.join(',')}`);
    }
    await settingsWin.webContents.executeJavaScript(
      `(() => { const s = document.getElementById('global-scale'); s.value = '100'; s.dispatchEvent(new Event('input', { bubbles: true })); })()`,
      true
    );
    await sleep(700);
    if (!ORDER.every((id) => Math.abs(state.pets.get(id).scale - 1) < 0.01)) {
      return fail('设置窗口全局限滑块恢复 100% 失败');
    }
    smokeLine('[smoke] settings window ok（大小联动 / 全局滑块 / 版权声明 / 四只缩放）');
    if (!settingsWin.isDestroyed()) settingsWin.destroy();

    const elapsed = ((Date.now() - smoke.started) / 1000).toFixed(1);
    smokeLine(`PASS windows=4 clips=37/28/11 chain=shaolan>sunpet>fengge>sunpet root=shaolan elapsed=${elapsed}s`);
    finishSmoke(0);
  } catch (error) {
    fail(`smoke 异常：${error.stack || error.message}`);
  }
}

// ---------------------------------------------------------------------------
// 截图诊断（--screenshot <目录>）
// ---------------------------------------------------------------------------

async function runScreenshot() {
  fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
  for (const pet of state.pets.values()) {
    if (pet.win && !pet.win.isDestroyed()) pet.win.showInactive();
  }
  if (!state.tray) installTray();
  showSettings();
  const settingsWin = state.settingsWin;
  if (settingsWin) {
    if (settingsWin.webContents.isLoading()) {
      await new Promise((resolve) => settingsWin.webContents.once('did-finish-load', resolve));
    }
  }
  await sleep(1200);
  const files = [];
  for (const id of ORDER) {
    const pet = state.pets.get(id);
    if (!pet.win || pet.win.isDestroyed()) continue;
    const image = await pet.win.webContents.capturePage();
    const file = path.join(SCREENSHOT_DIR, `pet-${id}.png`);
    fs.writeFileSync(file, image.toPNG());
    files.push(`${id}: ${file}`);
  }
  if (settingsWin && !settingsWin.isDestroyed()) {
    const image = await settingsWin.webContents.capturePage();
    const file = path.join(SCREENSHOT_DIR, 'settings.png');
    fs.writeFileSync(file, image.toPNG());
    files.push(`settings: ${file}`);
  }
  console.log(`[screenshot] 已写出 ${files.length} 张：`);
  for (const line of files) console.log(`  ${line}`);
  state.quitting = true;
  if (state.store) state.store.saveNow();
  if (state.probe) state.probe.destroy();
  if (state.tray) state.tray.destroy();
  for (const pet of state.pets.values()) {
    if (pet.win && !pet.win.isDestroyed()) pet.win.destroy();
  }
  if (settingsWin && !settingsWin.isDestroyed()) settingsWin.destroy();
  app.exit(0);
}

// ---------------------------------------------------------------------------
// 生命周期
// ---------------------------------------------------------------------------

const gotSingleInstanceLock = IS_SMOKE ? true : app.requestSingleInstanceLock();
if (!gotSingleInstanceLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    showSettings();
  });

  app.whenReady().then(async () => {
    try {
      app.setAppUserModelId('local.pethub.app');
      Menu.setApplicationMenu(null);

      state.store = new SettingsStore(path.join(app.getPath('userData'), 'settings.json'));
      state.settings = state.store.load();
      registerIpc();

      // --- QA / 自动化诊断入口（不影响正常启动） ---
      if (INSTALL_PACK_DIR) {
        state.probe = new AssetProbe();
        try {
          const result = await petpack.installPack(INSTALL_PACK_DIR, app.getPath('userData'), state.probe);
          state.settings.customPack = {
            installed: true,
            name: result.content.name,
            signature: petpack.contentSignature(result.content),
          };
          state.store.saveNow();
          console.log(
            `PASS petpack installed name=${result.content.name} author=${result.content.author || '-'} clips=${result.content.clips.length} avatar=${result.content.avatar.width}x${result.content.avatar.height} dir=${path.join(app.getPath('userData'), 'HeadPet')}`
          );
          state.probe.destroy();
          app.exit(0);
        } catch (error) {
          console.log(`FAIL ${error.message}`);
          state.probe.destroy();
          app.exit(1);
        }
        return;
      }
      if (RESTORE_BUILTIN) {
        const removed = petpack.removePack(app.getPath('userData'));
        state.settings.customPack = { installed: false, name: null, signature: null };
        state.settings.pets.shaolan.pinnedID = null;
        state.settings.pets.shaolan.randomMode = true;
        state.settings.pets.shaolan.excludedIDs = [];
        state.store.saveNow();
        console.log(`PASS restore-builtin removed=${removed}`);
        app.exit(0);
        return;
      }

      await createAllPets();

      if (DUMP_STATE) {
        printState();
        state.probe.destroy();
        state.quitting = true;
        for (const pet of state.pets.values()) {
          if (pet.win && !pet.win.isDestroyed()) pet.win.destroy();
        }
        app.exit(0);
        return;
      }
      if (IS_CHAIN_TEST) {
        await runChainTest();
        return;
      }

      if (IS_SMOKE) {
        // 隐藏窗口也能跑计时器/解码，smoke 不弹到用户桌面上。
        await runSmoke();
        return;
      }

      if (IS_SCREENSHOT) {
        await runScreenshot();
        return;
      }

      installTray();
      showStartupHints();
      if (OPEN_SETTINGS) showSettings();
      const positions = ORDER.map((id) => {
        const pet = state.pets.get(id);
        const bounds = pet.win.getBounds();
        return `${id}@${bounds.x},${bounds.y} ${bounds.width}x${bounds.height}`;
      }).join(' ');
      log(`[startup] ${APP_VERSION} pets=${state.pets.size} ${positions} userData=${app.getPath('userData')}`);
    } catch (error) {
      console.error(`[startup] 启动失败：${error.stack || error.message}`);
      dialog.showMessageBoxSync({
        type: 'error',
        title: '桌宠合集启动失败',
        message: '启动时出错了',
        detail: error.message,
      });
      app.exit(1);
    }
  });
}

app.on('before-quit', () => {
  state.quitting = true;
  if (state.store) state.store.saveNow();
});

app.on('window-all-closed', () => {
  if (state.quitting) app.quit();
});

process.on('uncaughtException', (error) => {
  console.error(`[uncaught] ${error.stack || error.message}`);
});