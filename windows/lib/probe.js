'use strict';

/**
 * 离屏探测窗口：用 Chromium 自己解码图片和音频，拿到头像尺寸 / 音频时长。
 *
 * 为什么要在 renderer 里做：Electron 主进程没有解码音频的 API，
 * 而内容包校验要求「头像可解码」「每条音频时长 > 0.1s」；用一个隐藏的
 * BrowserWindow 跑 HTMLAudioElement / Image 最接近实际播放时的行为。
 */

const path = require('path');
const { pathToFileURL } = require('url');
const { BrowserWindow } = require('electron');

class AssetProbe {
  constructor() {
    this.win = null;
    this.readyPromise = null;
  }

  async ensure() {
    if (this.readyPromise) return this.readyPromise;
    this.win = new BrowserWindow({
      show: false,
      width: 200,
      height: 200,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
        backgroundThrottling: false,
      },
    });
    this.readyPromise = this.win.loadFile(path.join(__dirname, '..', 'renderer', 'probe.html'));
    await this.readyPromise;
    return this.win;
  }

  async measure({ images = [], audios = [] } = {}) {
    await this.ensure();
    const toUrl = (file) => pathToFileURL(file).href;
    const payload = {
      images: images.map(toUrl),
      audios: audios.map(toUrl),
    };
    const raw = await this.win.webContents.executeJavaScript(
      `window.__probe(${JSON.stringify(payload)})`,
      true
    );
    const imagesByPath = {};
    const audiosByPath = {};
    images.forEach((file, index) => {
      imagesByPath[file] = raw.images[payload.images[index]] || { ok: false, width: 0, height: 0 };
    });
    audios.forEach((file, index) => {
      audiosByPath[file] = raw.audios[payload.audios[index]] || { duration: 0 };
    });
    return { images: imagesByPath, audios: audiosByPath };
  }

  destroy() {
    if (this.win && !this.win.isDestroyed()) this.win.destroy();
    this.win = null;
    this.readyPromise = null;
  }
}

module.exports = { AssetProbe };