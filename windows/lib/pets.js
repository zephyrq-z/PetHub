'use strict';

/**
 * 四只桌宠的静态资料 + 素材目录约定。
 *
 * 这里的数值全部照抄 macOS 原生版（Sources/PetKit/Audio/AudioPetProfiles.swift、
 * Sources/PetHub/PetLayout.swift），Windows 版只换渲染层，不改协议与策略。
 */

const PET_IDS = ['shaolan', 'sunpet', 'fengge', 'jelly'];
const ORDER = ['shaolan', 'sunpet', 'fengge', 'jelly'];

/** 素材目录名：Assets/ 下的一层目录（和 macOS 的 PetID.assetsFolder 一致）。 */
const ASSETS_FOLDER = {
  shaolan: 'shaolan',
  sunpet: 'sun',
  fengge: 'fengge',
  jelly: 'jelly',
};

/** 视觉槽位宽度（PetLayout.slotWidth）。 */
const SLOT_WIDTH = {
  shaolan: 260,
  sunpet: 180,
  fengge: 260,
  jelly: 128,
};

const LAYOUT = {
  gap: 36,
  margin: 24,
  compactGap: 6,
  compactMargin: 16,
  stageBase: 36,
  stageRaiseMin: 56,
  stageRaiseRatio: 0.18,
  stageScales: { shaolan: 1.2, sunpet: 1.4, fengge: 1.2, jelly: 0.65 },
};

const SIZE_MIN = 0.5;
const SIZE_MAX = 1.8;

/** 菜单里的六档音量（和 macOS 一致）。 */
const VOLUME_STEPS = [0, 0.25, 0.5, 0.65, 0.8, 1];

/** 捧哏池：Sun 只拿这 6 句短的，峰哥全部 11 句。 */
const SUN_COMPANION_IDS = [1, 2, 4, 11, 13, 14];

const CREDIT_LINE =
  '整合自 ShaolanPet / SunPet / FengGe-Desktop-Pet / JellyPet，版权归原作者；JellyPet 无 LICENSE。';

const CREDIT_DETAIL =
  '桌宠合集 PetHub 是一个整合项目：四只角色、原声、头像和原始玩法来自四个独立开源仓库。' +
  '代码（整合部分）为 MIT；音频与头像不在 MIT 范围内，归原作者，不商用。';

const UPSTREAM = [
  { name: 'ShaolanPet（薄肌桌宠）', author: 'Ganzhe2028', license: 'MIT', url: 'https://github.com/Ganzhe2028/ShaolanPet' },
  { name: 'SunPet（太对了）', author: 'Ganzhe2028', license: 'MIT', url: 'https://github.com/Ganzhe2028/SunPet' },
  {
    name: 'FengGe-Desktop-Pet（好事桌宠）',
    author: 'FengGe-Desktop-Pet contributors',
    license: 'MIT',
    url: 'https://github.com/Ganzhe2028/FengGe-Desktop-Pet',
  },
  { name: 'JellyPet（果冻桌宠）', author: 'aurelius358', license: '仓库未附 LICENSE', url: 'https://github.com/aurelius358/JellyPet' },
];

/**
 * 三只语音桌宠的 profile，字段与 macOS 的 AudioPetProfile 对齐。
 * `reaction` 是接话条件，`companionIds` 是捧哏池（null = 全部）。
 * `hop` / `root` 语义不可改：点击 hop 0，接话者 hop+1，root 原样传。
 */
const PET_PROFILES = {
  shaolan: {
    id: 'shaolan',
    kind: 'audio',
    title: '薄肌',
    fullName: '薄肌桌宠',
    menuHeader: '薄肌桌宠',
    assetsFolder: ASSETS_FOLDER.shaolan,
    defaultSize: 260,
    defaultVolume: 0.65,
    defaultX: null,
    defaultY: null,
    animation: 'squash',
    insetX: 8,
    insetY: 8,
    captionBand: 44,
    fontSize: 13,
    captionRadius: 9,
    captionBg: 'rgba(0,0,0,0.76)',
    hint: '点我说一句 · 右键设置',
    startupHint: '点我说一句 · 右键设置',
    companionIds: null,
    companionRespectsExclusions: false,
    initialDefaultOffExclusions: true,
    reaction: () => false,
    idleRelayStatus: '联动：只说不接',
  },
  sunpet: {
    id: 'sunpet',
    kind: 'audio',
    title: '太对了',
    fullName: '太对了桌宠',
    menuHeader: '孙宇晨 · 太对了',
    assetsFolder: ASSETS_FOLDER.sunpet,
    defaultSize: 180,
    defaultVolume: 0.65,
    animation: 'tilt',
    insetX: 12,
    insetY: 12,
    captionBand: 60,
    fontSize: 12,
    captionRadius: 10,
    captionBg: 'rgba(0,0,0,0.72)',
    hint: '点我一下 · 右键设置',
    startupHint: '点我一下 · 右键设置',
    companionIds: SUN_COMPANION_IDS,
    companionRespectsExclusions: true,
    initialDefaultOffExclusions: false,
    reaction: (speech) => (speech.from === 'shaolan' || speech.from === 'fengge') && speech.hop < 3,
    idleRelayStatus: '捧哏：就位（峰哥、薄肌）',
  },
  fengge: {
    id: 'fengge',
    kind: 'audio',
    title: '峰哥',
    fullName: '好事桌宠',
    menuHeader: '好事桌宠',
    assetsFolder: ASSETS_FOLDER.fengge,
    defaultSize: 260,
    defaultVolume: 0.65,
    animation: 'squash',
    insetX: 8,
    insetY: 8,
    captionBand: 44,
    fontSize: 13,
    captionRadius: 9,
    captionBg: 'rgba(0,0,0,0.76)',
    hint: '点我说一句 · 右键设置',
    startupHint: '点我说一句 · 右键设置',
    companionIds: null,
    companionRespectsExclusions: false,
    initialDefaultOffExclusions: false,
    reaction: (speech) => speech.from === 'sunpet' && speech.root === 'shaolan' && speech.hop < 3,
    idleRelayStatus: '联动：接太对了',
  },
  jelly: {
    id: 'jelly',
    kind: 'jelly',
    title: '果冻',
    fullName: '果冻桌宠',
    menuHeader: '果冻桌宠',
    assetsFolder: ASSETS_FOLDER.jelly,
    defaultSize: 128,
    defaultVolume: 0,
    animation: 'spring',
    hint: '按一下会 Q 弹 · 右键设置',
    startupHint: '按一下会 Q 弹 · 右键设置',
    marks: {
      0: 'claude-mark.png',
      1: 'gpt-mark.png',
      2: 'gemini-mark.png',
    },
    styleNames: { 0: 'Claude', 1: 'GPT', 2: 'Gemini' },
  },
};

module.exports = {
  PET_IDS,
  ORDER,
  ASSETS_FOLDER,
  SLOT_WIDTH,
  LAYOUT,
  SIZE_MIN,
  SIZE_MAX,
  VOLUME_STEPS,
  SUN_COMPANION_IDS,
  PET_PROFILES,
  CREDIT_LINE,
  CREDIT_DETAIL,
  UPSTREAM,
};