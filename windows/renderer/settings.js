'use strict';

/** 设置窗口：所有控件都只通过 preload 的 IPC 调主进程，主进程回推完整状态。 */

const api = window.pethub;

let current = null;
let sliderThrottle = null;

const $ = (id) => document.getElementById(id);

function send(command) {
  api.settingsCommand(command);
}

function setChecked(id, value) {
  const element = $(id);
  if (!element) return;
  if (document.activeElement !== element) element.checked = Boolean(value);
}

function renderVisibility(state) {
  const root = $('visibility-list');
  root.replaceChildren();
  for (const pet of state.pets) {
    const item = document.createElement('label');
    item.className = 'visibility-item';

    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = pet.visible;
    checkbox.dataset.action = 'toggle-visible';
    checkbox.dataset.id = pet.id;

    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = pet.title;

    const kind = document.createElement('span');
    kind.className = 'kind';
    kind.textContent = pet.kind === 'jelly' ? '形变（无语音）' : `${pet.clipCount} 句原声`;

    item.append(checkbox, name, kind);
    root.append(item);
  }
}

function volumeLabel(value) {
  return value === 0 ? '静音' : `${Math.round(value * 100)}%`;
}

const sizeBlocks = new Map();
const sliderBusy = new Set();

function buildSizeBlocks(state) {
  const root = $('size-list');
  root.replaceChildren();
  sizeBlocks.clear();
  for (const pet of state.pets) {
    const block = document.createElement('div');
    block.className = 'pet-block';

    const head = document.createElement('div');
    head.className = 'pet-head';
    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = pet.title;
    const meta = document.createElement('span');
    meta.className = 'meta';
    head.append(name, meta);

    const sliderRow = document.createElement('div');
    sliderRow.className = 'pet-slider';
    const sliderLabel = document.createElement('span');
    sliderLabel.className = 'label';
    sliderLabel.textContent = '大小';
    const range = document.createElement('input');
    range.type = 'range';
    range.min = '50';
    range.max = '180';
    range.step = '1';
    range.dataset.action = 'pet-scale';
    range.dataset.id = pet.id;
    const output = document.createElement('output');
    sliderRow.append(sliderLabel, range, output);

    block.append(head, sliderRow);

    let volumeSelect = null;
    let styleSelect = null;
    if (pet.kind === 'audio') {
      const volumeRow = document.createElement('div');
      volumeRow.className = 'pet-slider';
      const volumeLabelElement = document.createElement('span');
      volumeLabelElement.className = 'label';
      volumeLabelElement.textContent = '音量';
      volumeSelect = document.createElement('select');
      volumeSelect.dataset.action = 'pet-volume';
      volumeSelect.dataset.id = pet.id;
      for (const value of [0, 0.25, 0.5, 0.65, 0.8, 1]) {
        const option = document.createElement('option');
        option.value = String(value);
        option.textContent = volumeLabel(value);
        volumeSelect.append(option);
      }
      volumeRow.append(volumeLabelElement, volumeSelect);
      block.append(volumeRow);
    } else {
      const styleRow = document.createElement('div');
      styleRow.className = 'pet-slider';
      const styleLabel = document.createElement('span');
      styleLabel.className = 'label';
      styleLabel.textContent = '图标';
      styleSelect = document.createElement('select');
      styleSelect.dataset.action = 'jelly-style';
      for (const [value, label] of [
        ['0', 'Claude'],
        ['1', 'GPT'],
        ['2', 'Gemini'],
      ]) {
        const option = document.createElement('option');
        option.value = value;
        option.textContent = label;
        styleSelect.append(option);
      }
      styleRow.append(styleLabel, styleSelect);
      block.append(styleRow);
    }

    sizeBlocks.set(pet.id, { block, meta, range, output, volumeSelect, styleSelect });
    root.append(block);
  }
}

/**
 * 只更新数值，不重建 DOM：拖滑块时主进程会持续回推状态，
 * 重建 DOM 会把正在拖的 range 换掉，手感直接断掉。
 */
function updateSizeBlocks(state) {
  if (sizeBlocks.size !== state.pets.length) buildSizeBlocks(state);
  for (const pet of state.pets) {
    const entry = sizeBlocks.get(pet.id);
    if (!entry) continue;
    entry.meta.textContent =
      pet.kind === 'jelly' ? 'Q 弹标志' : `${pet.visible ? '显示中' : '已隐藏'} · 音量 ${volumeLabel(pet.volume)}`;
    const editing = document.activeElement === entry.range || sliderBusy.has(pet.id);
    if (!editing) {
      const percent = Math.round(pet.scale * 100);
      entry.range.value = String(percent);
      entry.output.textContent = `${percent}%`;
    }
    if (entry.volumeSelect && document.activeElement !== entry.volumeSelect) {
      entry.volumeSelect.value = String(pet.volume);
    }
    if (entry.styleSelect && document.activeElement !== entry.styleSelect) {
      entry.styleSelect.value = String(pet.style);
    }
  }
}

function renderSubmit(state) {
  $('version').textContent = state.version;
  $('footer-version').textContent = `PetHub ${state.version} · Windows`;

  if (!document.activeElement || document.activeElement.id !== 'global-scale') {
    const reference = state.pets.find((pet) => pet.id === 'shaolan') || state.pets[0];
    const percent = Math.round((reference?.scale ?? 1) * 100);
    $('global-scale').value = String(percent);
    $('global-scale-value').textContent = `${percent}%`;
  }

  setChecked('link-size', state.linkSize);
  setChecked('relay-enabled', state.relayEnabled);
  setChecked('group-drag', state.groupDrag);

  const custom = state.custom;
  const status = $('custom-status');
  if (custom.installed) {
    status.textContent = `当前：${custom.name}（替换薄肌，${custom.clipCount} 句）`;
  } else if (custom.error) {
    status.textContent = `当前：原版薄肌（已安装的内容包读不出来：${custom.error}）`;
  } else {
    status.textContent = '当前：原版薄肌';
  }
  $('restore-builtin').disabled = !custom.installed;

  $('credit-line').textContent = state.credits;
  $('credit-detail').textContent = state.creditDetail;
  $('footer-credit').textContent = state.credits;

  const upstream = $('upstream-list');
  upstream.replaceChildren();
  for (const item of state.upstream || []) {
    const li = document.createElement('li');
    li.textContent = `${item.name} —— ${item.author}（${item.license}） ${item.url}`;
    upstream.append(li);
  }

  renderVisibility(state);
  updateSizeBlocks(state);
  current = state;
}

function throttleGlobalScale(value) {
  if (sliderThrottle) return;
  sliderThrottle = setTimeout(() => {
    sliderThrottle = null;
    send({ type: 'set-global-scale', value });
  }, 60);
}

function wire() {
  $('visibility-list').addEventListener('change', (event) => {
    const target = event.target;
    if (!target.matches('input[data-action="toggle-visible"]')) return;
    send({ type: 'set-visible', id: target.dataset.id, visible: target.checked });
  });

  $('show-all').addEventListener('click', () => send({ type: 'set-all-visible', visible: true }));
  $('hide-all').addEventListener('click', () => send({ type: 'set-all-visible', visible: false }));

  $('arrange-default').addEventListener('click', () => send({ type: 'arrange', mode: 'default' }));
  $('arrange-compact').addEventListener('click', () => send({ type: 'arrange', mode: 'compact' }));
  $('arrange-stage').addEventListener('click', () => send({ type: 'arrange', mode: 'stage' }));

  $('global-scale').addEventListener('input', (event) => {
    const value = Number(event.target.value);
    $('global-scale-value').textContent = `${value}%`;
    throttleGlobalScale(value / 100);
  });

  $('link-size').addEventListener('change', (event) => {
    send({ type: 'set-link-size', value: event.target.checked });
  });

  $('relay-enabled').addEventListener('change', (event) => {
    send({ type: 'set-relay', value: event.target.checked });
  });

  $('group-drag').addEventListener('change', (event) => {
    send({ type: 'set-group-drag', value: event.target.checked });
  });

  $('size-list').addEventListener('input', (event) => {
    const target = event.target;
    if (target.matches('input[data-action="pet-scale"]')) {
      const percent = Number(target.value);
      const output = target.parentElement.querySelector('output');
      if (output) output.textContent = `${percent}%`;
      sliderBusy.add(target.dataset.id);
      send({ type: 'set-pet-scale', id: target.dataset.id, value: percent / 100 });
    }
  });

  $('size-list').addEventListener('change', (event) => {
    const target = event.target;
    if (target.matches('input[data-action="pet-scale"]')) {
      const id = target.dataset.id;
      setTimeout(() => sliderBusy.delete(id), 250);
    } else if (target.matches('select[data-action="pet-volume"]')) {
      send({ type: 'set-pet-volume', id: target.dataset.id, value: Number(target.value) });
    } else if (target.matches('select[data-action="jelly-style"]')) {
      send({ type: 'set-jelly-style', value: Number(target.value) });
    }
  });

  $('import-pack').addEventListener('click', () => send({ type: 'import-petpack' }));
  $('restore-builtin').addEventListener('click', () => send({ type: 'restore-builtin' }));
  $('open-pack-folder').addEventListener('click', () => send({ type: 'open-pack-folder' }));
  $('open-credits').addEventListener('click', () => send({ type: 'open-credits' }));
  $('about').addEventListener('click', () => send({ type: 'about' }));

  api.onSettingsState((state) => renderSubmit(state));
}

wire();
api.settingsGetState().then((state) => renderSubmit(state)).catch((error) => {
  console.error(`[settings] 读取状态失败：${error.message}`);
});