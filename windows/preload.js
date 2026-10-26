'use strict';

/**
 * preload：只暴露必要的 IPC。renderer 不开 nodeIntegration。
 * 桌宠窗口和设置窗口共用这一份，按用到的 API 区分即可。
 */

const { contextBridge, ipcRenderer } = require('electron');

function subscribe(channel, callback) {
  const handler = (_event, payload) => callback(payload);
  ipcRenderer.on(channel, handler);
  return () => ipcRenderer.removeListener(channel, handler);
}

contextBridge.exposeInMainWorld('pethub', {
  // ---- 桌宠窗口 ----
  ready: () => ipcRenderer.send('pet-ready'),
  onInit: (callback) => subscribe('pet-init', callback),
  onReload: (callback) => subscribe('pet-reload', callback),
  onPlay: (callback) => subscribe('pet-play', callback),
  onStop: (callback) => subscribe('pet-stop', callback),
  onNotice: (callback) => subscribe('pet-notice', callback),
  onStyle: (callback) => subscribe('pet-style', callback),
  onValidate: (callback) => subscribe('pet-validate', callback),
  pointer: (payload) => ipcRenderer.send('pet-pointer', payload),
  contextMenu: () => ipcRenderer.send('pet-context-menu'),
  jellyInteractive: (inside) => ipcRenderer.send('pet-jelly-interactive', Boolean(inside)),
  playbackEnded: () => ipcRenderer.send('pet-playback-ended'),
  validateResult: (result) => ipcRenderer.send('pet-validate-result', result),

  // ---- 设置窗口 ----
  settingsGetState: () => ipcRenderer.invoke('settings:get-state'),
  onSettingsState: (callback) => subscribe('settings:state', callback),
  settingsCommand: (command) => ipcRenderer.send('settings:command', command),
});