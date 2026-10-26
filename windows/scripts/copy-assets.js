'use strict';

/**
 * 把仓库根目录 `Assets/` 里的四只素材复制到 `windows/assets/`。
 *
 * 约束：不把素材提交进仓库、也不复制 upstream/；开发（npm start）和构建
 * （build-win.sh / electron-builder）都从这里拿素材。
 *
 * 顺带把 AppIcon.icns 转成 1024 PNG：Windows 的托盘和 electron-builder 都需要 png。
 * macOS 上用系统自带 sips；其它平台如果已经有 png 就跳过，没有则只告警
 * （真正的 Windows 打包在 macOS 上做，见 windows/README.md）。
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const WINDOWS_DIR = path.join(__dirname, '..');
const REPO_ROOT = path.join(WINDOWS_DIR, '..');
const SRC = path.join(REPO_ROOT, 'Assets');
const DEST = path.join(WINDOWS_DIR, 'assets');
const BUILD_DIR = path.join(WINDOWS_DIR, 'build');
const FOLDERS = ['shaolan', 'sun', 'fengge', 'jelly'];

function fail(message) {
  console.error(`[copy-assets] ${message}`);
  process.exit(1);
}

function copyTree(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (entry.name === '.DS_Store') continue;
    const from = path.join(src, entry.name);
    const to = path.join(dest, entry.name);
    if (entry.isDirectory()) copyTree(from, to);
    else if (entry.isFile()) fs.copyFileSync(from, to);
    else fail(`不支持的素材类型：${from}`);
  }
}

function countBytes(dir) {
  let total = 0;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const target = path.join(dir, entry.name);
    if (entry.isDirectory()) total += countBytes(target);
    else if (entry.isFile()) total += fs.statSync(target).size;
  }
  return total;
}

function main() {
  if (!fs.existsSync(SRC)) fail(`找不到素材目录：${SRC}`);

  fs.rmSync(DEST, { recursive: true, force: true });
  fs.mkdirSync(DEST, { recursive: true });

  const report = [];
  for (const folder of FOLDERS) {
    const from = path.join(SRC, folder);
    if (!fs.existsSync(from)) fail(`缺少素材目录：${from}`);
    copyTree(from, path.join(DEST, folder));
    report.push(`${folder}(${countBytes(path.join(DEST, folder))}B)`);
  }

  const icns = path.join(SRC, 'AppIcon.icns');

  fs.mkdirSync(BUILD_DIR, { recursive: true });
  const png = path.join(DEST, 'AppIcon.png');
  const iconPng = path.join(BUILD_DIR, 'icon.png');
  const canSips = process.platform === 'darwin' && fs.existsSync('/usr/bin/sips');
  let pngSource = null;
  if (canSips && fs.existsSync(icns)) {
    try {
      execFileSync('/usr/bin/sips', ['-s', 'format', 'png', icns, '--out', png], { stdio: 'ignore' });
      pngSource = 'sips';
    } catch (error) {
      console.warn(`[copy-assets] sips 转换 icns 失败：${error.message}`);
    }
  }
  if (!fs.existsSync(png)) {
    if (fs.existsSync(iconPng)) {
      fs.copyFileSync(iconPng, png);
      pngSource = 'build/icon.png';
    } else {
      console.warn('[copy-assets] 没有生成 AppIcon.png：托盘和打包图标会缺失（在 macOS 上重跑即可）');
    }
  }
  if (fs.existsSync(png)) {
    fs.copyFileSync(png, iconPng);
  }

  console.log(`[copy-assets] ${REPO_ROOT}/Assets → windows/assets：${report.join(' ')}`);
  console.log(`[copy-assets] icon.png：${pngSource ? `已生成（${pngSource}）` : '缺失'}`);
}

main();