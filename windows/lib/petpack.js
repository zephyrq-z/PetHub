'use strict';

/**
 * PetPack 内容包（v1）：模型、校验、安装 / 删除。
 *
 * 规则对齐 docs/PETPACK.md（macOS 的 Sources/PetKit/PetPack.swift）：
 *   format == 1、name 非空、1–200 条语音、相对安全路径、中文非空、
 *   头像可解码、每条音频可解码且时长 > 0.1 秒；
 * 安装走「先写临时目录、完整校验、再原子替换、失败回滚」。
 *
 * Windows 版把包装在 `app.getPath('userData')/HeadPet/`，保留包内相对目录结构，
 * 所以安装好的 HeadPet/ 本身仍是一个标准 PetPack，可以整个拷出来分发。
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const MAX_CLIPS = 200;
const MIN_AUDIO_SECONDS = 0.1;
const MANIFEST_NAME = 'petpack.json';

function packError(message) {
  const error = new Error(message);
  error.name = 'PetPackError';
  return error;
}

/** 包内相对路径：不能用绝对路径、不能有 `..`，统一用 `/`。 */
function safeRelative(rel, what) {
  if (typeof rel !== 'string' || rel.trim() === '') {
    throw packError(`${what} 是空的，必须写相对路径`);
  }
  const normalized = rel.replace(/\\/g, '/').trim();
  if (normalized.startsWith('/') || /^[A-Za-z]:/.test(normalized)) {
    throw packError(`桌宠包里有不安全的相对路径：${rel}（不能是绝对路径）`);
  }
  const segments = normalized.split('/');
  if (segments.some((segment) => segment === '..')) {
    throw packError(`桌宠包里有不安全的相对路径：${rel}（不能包含 ..）`);
  }
  if (segments.some((segment) => segment === '')) {
    throw packError(`桌宠包里有不安全的相对路径：${rel}（路径段为空）`);
  }
  return segments.join(path.sep);
}

function resolveInside(root, rel, what) {
  const relative = safeRelative(rel, what);
  const resolved = path.resolve(root, relative);
  const rootResolved = path.resolve(root);
  if (resolved !== rootResolved && !resolved.startsWith(rootResolved + path.sep)) {
    throw packError(`桌宠包里有不安全的相对路径：${rel}`);
  }
  return resolved;
}

function readManifest(dir) {
  const manifestPath = path.join(dir, MANIFEST_NAME);
  if (!fs.existsSync(manifestPath)) {
    throw packError(`找不到桌宠包：目录里没有 ${MANIFEST_NAME}`);
  }
  let raw;
  try {
    raw = fs.readFileSync(manifestPath, 'utf8');
  } catch (error) {
    throw packError(`读不了 ${MANIFEST_NAME}：${error.message}`);
  }
  let json;
  try {
    json = JSON.parse(raw);
  } catch (error) {
    throw packError(`桌宠包格式不对：${MANIFEST_NAME} 不是合法 JSON（${error.message}）`);
  }
  if (!json || typeof json !== 'object' || Array.isArray(json)) {
    throw packError('桌宠包格式不对：petpack.json 顶层必须是对象');
  }
  return json;
}

/** 只查 JSON 结构与路径是否安全，不碰磁盘上的文件内容。 */
function validateShape(manifest) {
  if (manifest.format !== 1) {
    throw packError(`桌宠包格式不对：format 必须是 1，现在是 ${JSON.stringify(manifest.format)}`);
  }
  if (typeof manifest.name !== 'string' || manifest.name.trim() === '') {
    throw packError('给桌宠起个名字吧。');
  }
  if (typeof manifest.avatar !== 'string') {
    throw packError('桌宠包格式不对：缺少 avatar');
  }
  safeRelative(manifest.avatar, 'avatar');
  if (!Array.isArray(manifest.clips)) {
    throw packError('桌宠包格式不对：缺少 clips 数组');
  }
  if (manifest.clips.length === 0) {
    throw packError('至少要放一条语音，不然桌宠没话说。');
  }
  if (manifest.clips.length > MAX_CLIPS) {
    throw packError(`语音太多了（${manifest.clips.length} 条），上限 ${MAX_CLIPS} 条。`);
  }
  manifest.clips.forEach((clip, index) => {
    if (!clip || typeof clip !== 'object') {
      throw packError(`桌宠包格式不对：第 ${index + 1} 条语音不是对象`);
    }
    safeRelative(clip.file, `第 ${index + 1} 条语音的 file`);
    if (typeof clip.label !== 'string' || clip.label.trim() === '') {
      throw packError('每条语音都要配一句中文。');
    }
  });
  if (manifest.author != null && typeof manifest.author !== 'string') {
    throw packError('桌宠包格式不对：author 必须是字符串');
  }
  return manifest;
}

/** 复制目录，拒绝符号链接（内容包只允许普通文件，避免指到包外）。 */
function copyTreeSafe(source, destination) {
  const stat = fs.lstatSync(source);
  if (stat.isSymbolicLink()) {
    throw packError(`桌宠包里不允许符号链接：${source}`);
  }
  if (stat.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
      if (entry.name === '.DS_Store') continue;
      copyTreeSafe(path.join(source, entry.name), path.join(destination, entry.name));
    }
    return;
  }
  if (!stat.isFile()) {
    throw packError(`桌宠包里不允许的文件类型：${source}`);
  }
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}

/**
 * 在给定目录上做完整校验（含头像 / 音频解码）。probe 由 lib/probe.js 提供。
 * 返回一份可直接渲染的 content 描述。
 */
async function validatePack(dir, probe) {
  const manifest = validateShape(readManifest(dir));
  const avatarAbs = resolveInside(dir, manifest.avatar, 'avatar');
  const clipAbs = manifest.clips.map((clip, index) => resolveInside(dir, clip.file, `第 ${index + 1} 条语音`));

  for (const [abs, label] of [
    [avatarAbs, '头像'],
    ...clipAbs.map((abs, index) => [abs, `第 ${index + 1} 条语音`]),
  ]) {
    if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) {
      throw packError(`桌宠包缺少文件：${label}（${path.relative(dir, abs)}）`);
    }
  }

  const measured = await probe.measure({ images: [avatarAbs], audios: clipAbs });
  const image = measured.images[avatarAbs];
  if (!image || !image.ok || !(image.width > 0) || !(image.height > 0)) {
    throw packError(`头像读不出来：${manifest.avatar}（Windows 版支持 png / jpeg / gif / webp）`);
  }
  const clips = manifest.clips.map((clip, index) => {
    const duration = measured.audios[clipAbs[index]]?.duration ?? 0;
    if (!(duration > MIN_AUDIO_SECONDS)) {
      throw packError(
        `语音读不出来（支持 wav / m4a / mp3 / aiff）：${clip.file}（时长 ${duration.toFixed(2)}s，需要 > 0.1s）`
      );
    }
    return {
      id: index + 1,
      label: clip.label,
      file: clip.file.replace(/\\/g, '/'),
      absPath: clipAbs[index],
      duration,
    };
  });

  return {
    dir,
    manifest,
    name: manifest.name.trim(),
    author: typeof manifest.author === 'string' ? manifest.author : '',
    avatar: {
      file: manifest.avatar.replace(/\\/g, '/'),
      absPath: avatarAbs,
      width: image.width,
      height: image.height,
      ratio: image.height / image.width,
    },
    clips,
  };
}

function contentSignature(content) {
  const payload = {
    name: content.name,
    avatar: content.avatar.file,
    author: content.author,
    clips: content.clips.map((clip) => ({
      file: clip.file,
      label: clip.label,
      size: fs.statSync(clip.absPath).size,
    })),
  };
  return crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}

function timestamp() {
  return new Date().toISOString().replace(/[-:.TZ]/g, '');
}

/**
 * 安装内容包到 baseDir/HeadPet：
 * 1. 先校验源目录；
 * 2. 复制到 HeadPet.tmp-<时间>，在临时目录再完整校验一次；
 * 3. 旧 HeadPet 改名备份 → 临时目录改名为 HeadPet → 删备份；
 * 4. 任何一步失败都回滚，坏包不会弄坏正在用的角色。
 */
async function installPack(sourceDir, baseDir, probe) {
  const sourceContent = await validatePack(sourceDir, probe);
  fs.mkdirSync(baseDir, { recursive: true });

  const dest = path.join(baseDir, 'HeadPet');
  const tmp = path.join(baseDir, `HeadPet.tmp-${timestamp()}-${process.pid}`);
  const backup = path.join(baseDir, `HeadPet.bak-${timestamp()}-${process.pid}`);

  try {
    copyTreeSafe(sourceDir, tmp);
    await validatePack(tmp, probe);

    const hadOld = fs.existsSync(dest);
    if (hadOld) fs.renameSync(dest, backup);
    try {
      fs.renameSync(tmp, dest);
    } catch (error) {
      if (hadOld && fs.existsSync(backup)) fs.renameSync(backup, dest);
      throw error;
    }
    if (fs.existsSync(backup)) fs.rmSync(backup, { recursive: true, force: true });
    return { content: await validatePack(dest, probe), sourceName: sourceContent.name };
  } catch (error) {
    fs.rmSync(tmp, { recursive: true, force: true });
    if (fs.existsSync(backup) && !fs.existsSync(dest)) {
      try {
        fs.renameSync(backup, dest);
      } catch {
        /* 回滚失败时保留备份目录，至少数据还在 */
      }
    }
    throw error;
  }
}

function removePack(baseDir) {
  const dest = path.join(baseDir, 'HeadPet');
  if (!fs.existsSync(dest)) return false;
  const trash = path.join(baseDir, `HeadPet.trash-${timestamp()}-${process.pid}`);
  fs.renameSync(dest, trash);
  fs.rmSync(trash, { recursive: true, force: true });
  return true;
}

module.exports = {
  MANIFEST_NAME,
  MAX_CLIPS,
  MIN_AUDIO_SECONDS,
  safeRelative,
  resolveInside,
  readManifest,
  validateShape,
  validatePack,
  installPack,
  removePack,
  contentSignature,
  copyTreeSafe,
};