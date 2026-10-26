'use strict';

const fs = require('fs');
const path = require('path');
const { SIZE_MIN, SIZE_MAX, VOLUME_STEPS, ORDER } = require('./pets');

/** settings.json 的默认值。第一次启动 / 字段缺失时按这个补齐。 */
function defaultSettings() {
  return {
    version: 1,
    hub: {
      relayEnabled: true,
      linkSize: true,
      groupDrag: false,
    },
    pets: {
      shaolan: { x: null, y: null, scale: 1, volume: 0.65, randomMode: true, pinnedID: null, excludedIDs: null, visible: true },
      sunpet: { x: null, y: null, scale: 1, volume: 0.65, randomMode: true, pinnedID: null, excludedIDs: [], visible: true },
      fengge: { x: null, y: null, scale: 1, volume: 0.65, randomMode: true, pinnedID: null, excludedIDs: [], visible: true },
      jelly: { x: null, y: null, scale: 1, style: 0, visible: true },
    },
    customPack: { installed: false, name: null, signature: null },
  };
}

function clampScale(value, fallback = 1) {
  if (value == null || value === '') return fallback;
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(SIZE_MAX, Math.max(SIZE_MIN, Math.round(n * 1000) / 1000));
}

function pickVolume(value, fallback = 0.65) {
  if (value == null || value === '') return fallback;
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  let best = VOLUME_STEPS[0];
  for (const step of VOLUME_STEPS) {
    if (Math.abs(step - n) < Math.abs(best - n)) best = step;
  }
  return best;
}

function finiteOrNull(value) {
  // 注意：Number(null) === 0，不能把「没有保存过位置」变成坐标 0,0。
  if (value == null || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
}

function intSet(value) {
  if (!Array.isArray(value)) return [];
  const out = new Set();
  for (const entry of value) {
    const n = Number(entry);
    if (Number.isInteger(n) && n > 0) out.add(n);
  }
  return [...out].sort((a, b) => a - b);
}

/** 把磁盘上的 JSON 夹成一份可用的设置：范围、类型都收紧，坏值走默认。 */
function sanitize(raw) {
  const base = defaultSettings();
  if (!raw || typeof raw !== 'object') return base;
  const out = base;

  const hub = raw.hub && typeof raw.hub === 'object' ? raw.hub : {};
  out.hub.relayEnabled = typeof hub.relayEnabled === 'boolean' ? hub.relayEnabled : base.hub.relayEnabled;
  out.hub.linkSize = typeof hub.linkSize === 'boolean' ? hub.linkSize : base.hub.linkSize;
  out.hub.groupDrag = typeof hub.groupDrag === 'boolean' ? hub.groupDrag : base.hub.groupDrag;

  const pets = raw.pets && typeof raw.pets === 'object' ? raw.pets : {};
  for (const id of ['shaolan', 'sunpet', 'fengge']) {
    const src = pets[id] && typeof pets[id] === 'object' ? pets[id] : {};
    const dst = out.pets[id];
    dst.x = finiteOrNull(src.x);
    dst.y = finiteOrNull(src.y);
    dst.scale = clampScale(src.scale, 1);
    dst.volume = pickVolume(src.volume, 0.65);
    dst.randomMode = typeof src.randomMode === 'boolean' ? src.randomMode : true;
    dst.pinnedID = Number.isInteger(src.pinnedID) && src.pinnedID > 0 ? src.pinnedID : null;
    dst.excludedIDs = Array.isArray(src.excludedIDs) ? intSet(src.excludedIDs) : id === 'shaolan' ? null : [];
    dst.visible = typeof src.visible === 'boolean' ? src.visible : true;
  }
  const jellySrc = pets.jelly && typeof pets.jelly === 'object' ? pets.jelly : {};
  const jellyDst = out.pets.jelly;
  jellyDst.x = finiteOrNull(jellySrc.x);
  jellyDst.y = finiteOrNull(jellySrc.y);
  jellyDst.scale = clampScale(jellySrc.scale, 1);
  jellyDst.style = [0, 1, 2].includes(jellySrc.style) ? jellySrc.style : 0;
  jellyDst.visible = typeof jellySrc.visible === 'boolean' ? jellySrc.visible : true;

  const pack = raw.customPack && typeof raw.customPack === 'object' ? raw.customPack : {};
  out.customPack.installed = pack.installed === true;
  out.customPack.name = typeof pack.name === 'string' ? pack.name : null;
  out.customPack.signature = typeof pack.signature === 'string' ? pack.signature : null;

  return out;
}

class SettingsStore {
  constructor(file) {
    this.file = file;
    this.dir = path.dirname(file);
    this.data = null;
    this._timer = null;
  }

  load() {
    let raw = null;
    try {
      raw = JSON.parse(fs.readFileSync(this.file, 'utf8'));
    } catch {
      raw = null;
    }
    this.data = sanitize(raw);
    return this.data;
  }

  /** 同步写盘；设置很小，直接覆盖写，先写临时文件再 rename，避免半截文件。 */
  saveNow() {
    if (this._timer) {
      clearTimeout(this._timer);
      this._timer = null;
    }
    try {
      fs.mkdirSync(this.dir, { recursive: true });
      const tmp = `${this.file}.tmp`;
      fs.writeFileSync(tmp, `${JSON.stringify(this.data, null, 2)}\n`, 'utf8');
      fs.renameSync(tmp, this.file);
    } catch (error) {
      console.error('[settings] 保存失败:', error.message);
    }
  }

  /** 防抖保存：拖滑块/拖窗口时不要每一帧都写盘。 */
  save() {
    if (this._timer) clearTimeout(this._timer);
    this._timer = setTimeout(() => {
      this._timer = null;
      this.saveNow();
    }, 350);
  }
}

module.exports = { SettingsStore, defaultSettings, clampScale, pickVolume, sanitize, ORDER };