'use strict';

/**
 * 启动 Electron 的小包装。
 *
 * 为什么不用 `electron .`：有些环境（包括本仓库的 AI 工具链）会带
 * `ELECTRON_RUN_AS_NODE=1`，这时 electron 会变成纯 Node，窗口一个都不开。
 * 这里显式清掉该变量再启动，让 `npm start` / `npm run smoke` 稳定跑成 GUI 进程。
 * Windows 上不需要这个变量，清掉也无副作用。
 */

const { spawn } = require('child_process');
const path = require('path');
const electronBinary = require('electron');

const env = { ...process.env };
delete env.ELECTRON_RUN_AS_NODE;

const args = ['.', ...process.argv.slice(2)];
const child = spawn(electronBinary, args, {
  cwd: path.join(__dirname, '..'),
  stdio: 'inherit',
  env,
});

child.on('error', (error) => {
  console.error(`[launch] 启动 Electron 失败：${error.message}`);
  process.exit(1);
});
child.on('exit', (code, signal) => {
  if (signal) {
    console.error(`[launch] Electron 被信号 ${signal} 结束`);
    process.exit(1);
  }
  process.exit(code == null ? 0 : code);
});