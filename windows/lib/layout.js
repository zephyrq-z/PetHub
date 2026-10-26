'use strict';

/**
 * 四只的站位计算（Windows DIP 坐标，屏幕左上角为原点）。
 *
 * 对应 macOS 的 Sources/PetHub/PetLayout.swift：
 * 默认站位按固定槽位宽 260/180/260/128 → 间距 36 → 屏幕边距 24 从右下角排一行；
 * 紧凑排列把间距收到 6、边距收到 16；捧哏排列（合影）按 1.2/1.4/1.2/0.65 倍率叠放。
 */

const { ORDER, SLOT_WIDTH, LAYOUT } = require('./pets');

/** 语音桌宠窗口尺寸：宽 = 默认大小 × 比例；高 = 头像区 + 上边距 + 字幕带。 */
function audioSize(profile, scale, faceRatio) {
  const width = Math.max(40, Math.round(profile.defaultSize * scale));
  const faceWidth = Math.max(1, width - 2 * profile.insetX);
  const height = Math.max(
    40,
    Math.round(faceWidth * faceRatio + profile.insetY + profile.captionBand)
  );
  return { width, height };
}

/** 果冻窗口：比图标大一圈，留出形变空间；真正接收点击的只有中间图标圆。 */
function jellyWindowSize(iconSide) {
  return { width: Math.max(40, Math.round(iconSide * 1.75)), height: Math.max(40, Math.round(iconSide * 1.75)) };
}

function iconSideFor(profile, scale) {
  return Math.max(24, Math.round(profile.defaultSize * scale));
}

function visualWidth(id, state) {
  if (id === 'jelly') return iconSideFor(state.profile, state.scale);
  return audioSize(state.profile, state.scale, state.faceRatio).width;
}

function visualHeight(id, state) {
  if (id === 'jelly') return iconSideFor(state.profile, state.scale);
  return audioSize(state.profile, state.scale, state.faceRatio).height;
}

/** 一排的底边 y（窗口/图标下沿）。 */
function rowBottom(area, margin) {
  return area.y + area.height - margin;
}

function rowWidth(states, gap) {
  const widths = ORDER.map((id) => visualWidth(id, states[id]));
  return widths.reduce((sum, width) => sum + width, 0) + gap * (ORDER.length - 1);
}

function rowLeft(area, states, gap, margin) {
  return Math.max(area.x + margin, area.x + area.width - margin - rowWidth(states, gap));
}

function slotCenterX(id, area, states, gap, margin) {
  let x = rowLeft(area, states, gap, margin);
  for (const pet of ORDER) {
    const width = SLOT_WIDTH[pet];
    if (pet === id) return x + width / 2;
    x += width + gap;
  }
  return area.x + area.width / 2;
}

/** 把「图标左/下沿 + 边长」换成 BrowserWindow 的左上角坐标。 */
function jellyWindowBounds(iconLeft, iconBottom, iconSide) {
  const win = jellyWindowSize(iconSide);
  return {
    x: Math.round(iconLeft + iconSide / 2 - win.width / 2),
    y: Math.round(iconBottom + iconSide / 2 - win.height / 2),
    width: win.width,
    height: win.height,
  };
}

function audioBounds(profile, scale, faceRatio, left, bottom) {
  const size = audioSize(profile, scale, faceRatio);
  return { x: Math.round(left), y: Math.round(bottom - size.height), width: size.width, height: size.height };
}

/**
 * 默认排列：每只落在自己的固定槽位里居中，底边对齐一排。
 * 返回 { id: {x,y,width,height} }（语音桌宠是窗口，果冻是窗口，图标在窗口中心）。
 */
function defaultLayout(states, area, options = {}) {
  const gap = options.gap ?? LAYOUT.gap;
  const margin = options.margin ?? LAYOUT.margin;
  const bottom = rowBottom(area, margin);
  const result = {};
  for (const id of ORDER) {
    const state = states[id];
    if (id === 'jelly') {
      const side = iconSideFor(state.profile, state.scale);
      const centerX = slotCenterX(id, area, states, gap, margin);
      result[id] = jellyWindowBounds(centerX - side / 2, bottom - side, side);
    } else {
      const size = audioSize(state.profile, state.scale, state.faceRatio);
      const centerX = slotCenterX(id, area, states, gap, margin);
      result[id] = audioBounds(state.profile, state.scale, state.faceRatio, centerX - size.width / 2, bottom);
    }
  }
  return result;
}

/** 紧凑排列：按实际视觉宽度从左往右紧挨着摆，间距 6、边距 16。 */
function compactLayout(states, area) {
  const gap = LAYOUT.compactGap;
  const margin = LAYOUT.compactMargin;
  const bottom = rowBottom(area, margin);
  let x = rowLeft(area, states, gap, margin);
  const result = {};
  for (const id of ORDER) {
    const state = states[id];
    const width = visualWidth(id, state);
    if (id === 'jelly') {
      const side = iconSideFor(state.profile, state.scale);
      result[id] = jellyWindowBounds(x, bottom - side, side);
    } else {
      result[id] = audioBounds(state.profile, state.scale, state.faceRatio, x, bottom);
    }
    x += width + gap;
  }
  return result;
}

/**
 * 捧哏排列（合影）：薄肌左、太对了中间抬高、峰哥右、果冻缩在峰哥右肩后。
 * 和 macOS 一样先把四只尺寸切到 1.2 / 1.4 / 1.2 / 0.65，再摆位。
 */
function stageLayout(states, area) {
  const gap = LAYOUT.compactGap;
  const bottom = area.y + area.height - LAYOUT.stageBase;
  const firstWidth = visualWidth('shaolan', states.shaolan);
  const secondWidth = visualWidth('sunpet', states.sunpet);
  const thirdWidth = visualWidth('fengge', states.fengge);
  const jellySide = iconSideFor(states.jelly.profile, states.jelly.scale);
  const sceneWidth = firstWidth + gap + secondWidth + gap + thirdWidth;
  const left = area.x + (area.width - sceneWidth) / 2;
  const firstHeight = visualHeight('shaolan', states.shaolan);
  const raise = Math.max(LAYOUT.stageRaiseMin, firstHeight * LAYOUT.stageRaiseRatio);

  const result = {};
  result.shaolan = audioBounds(states.shaolan.profile, states.shaolan.scale, states.shaolan.faceRatio, left, bottom);
  result.sunpet = audioBounds(
    states.sunpet.profile,
    states.sunpet.scale,
    states.sunpet.faceRatio,
    left + firstWidth + gap,
    bottom + raise
  );
  result.fengge = audioBounds(
    states.fengge.profile,
    states.fengge.scale,
    states.fengge.faceRatio,
    left + firstWidth + gap + secondWidth + gap,
    bottom
  );

  const fenggeHeight = visualHeight('fengge', states.fengge);
  const jellyCenterX = left + firstWidth + gap + secondWidth + gap + thirdWidth - jellySide * 0.55;
  const jellyCenterY = bottom - fenggeHeight * 0.68; // bottom 是像素底，center 向上 0.68 个峰哥高
  result.jelly = jellyWindowBounds(jellyCenterX - jellySide / 2, jellyCenterY - jellySide / 2, jellySide);
  return result;
}

/** 缩放后保持窗口「底边 + 水平中心」不变，和 macOS 调大小的手感一致。 */
function resizeAnchored(bounds, newSize, kind) {
  const centerX = bounds.x + bounds.width / 2;
  const bottom = bounds.y + bounds.height;
  if (kind === 'jelly') {
    return { x: Math.round(centerX - newSize.width / 2), y: Math.round(bottom - newSize.height), ...newSize };
  }
  return { x: Math.round(centerX - newSize.width / 2), y: Math.round(bottom - newSize.height), ...newSize };
}

/** 恢复位置前检查：窗口至少有一部分在屏幕可见区内。 */
function isReasonablePosition(bounds, displays) {
  const minVisible = 24;
  return displays.some((display) => {
    const area = display.workArea;
    const overlapX = Math.min(bounds.x + bounds.width, area.x + area.width) - Math.max(bounds.x, area.x);
    const overlapY = Math.min(bounds.y + bounds.height, area.y + area.height) - Math.max(bounds.y, area.y);
    return overlapX >= minVisible && overlapY >= minVisible;
  });
}

module.exports = {
  audioSize,
  jellyWindowSize,
  iconSideFor,
  visualWidth,
  visualHeight,
  rowBottom,
  defaultLayout,
  compactLayout,
  stageLayout,
  resizeAnchored,
  isReasonablePosition,
  jellyWindowBounds,
};