#!/usr/bin/env bash
#
# Windows 打包脚本（在 macOS / Linux 上运行，产物给 Windows x64）
#
#   ./build-win.sh            # npm install → 复制素材 → electron-builder → dist/windows
#   ./build-win.sh --no-install
#
# 产物（仓库根 dist/windows/，不会碰 macOS 的 dist/PetHub-2.0.0.dmg）：
#   PetHub-2.0.0-Windows-x64.exe   单文件（优先 electron-builder portable）
#   PetHub-2.0.0-Windows-x64.zip   免安装兜底
#   PetHub-2.0.0-Windows-x64.sha256
#
# target=portable 在本机（macOS + Wine 不可用）如果失败，会自动退回：
#   1) 先保证 zip 产出；
#   2) 用 7z SFX（7zS.sfx + 自解压配置）把 zip 内容包成单文件 exe；
#   3) 连 SFX 模块都下载不到时，保留 zip 并打印明确的 WARN（不会假装成功）。
#
# 代理：本机需要。脚本只在环境里还没有 HTTPS_PROXY 时才用下面的默认值。
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(node -p "require('./package.json').version" 2>/dev/null || echo 2.0.0)"
REPO_ROOT="$(cd .. && pwd)"
OUT_DIR="$REPO_ROOT/dist/windows"
EXE="$OUT_DIR/PetHub-$VERSION-Windows-x64.exe"
ZIP="$OUT_DIR/PetHub-$VERSION-Windows-x64.zip"
SHA="$OUT_DIR/PetHub-$VERSION-Windows-x64.sha256"

DEFAULT_PROXY="${PET_PROXY:-http://127.0.0.1:7897}"
NO_INSTALL=0
[[ "${1:-}" == "--no-install" ]] && NO_INSTALL=1

step() { printf '\n== %s ==\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*" >&2; }
die() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. 环境
# ---------------------------------------------------------------------------
step "环境检查"
command -v node >/dev/null 2>&1 || die "缺少 node"
command -v npm >/dev/null 2>&1 || die "缺少 npm"
[[ -f package.json ]] || die "请在 windows/ 目录里运行"
[[ -d "$REPO_ROOT/Assets" ]] || die "找不到 $REPO_ROOT/Assets（素材必须从仓库根 Assets/ 复制）"

if [[ -z "${HTTPS_PROXY:-}" ]]; then
  export HTTPS_PROXY="$DEFAULT_PROXY"
  export HTTP_PROXY="$DEFAULT_PROXY"
  export ALL_PROXY="${ALL_PROXY:-socks5://127.0.0.1:7897}"
  echo "未检测到代理环境变量，使用默认值 $DEFAULT_PROXY（可用 PET_PROXY 覆盖）"
fi
# electron-builder 的 Windows 预编译件走镜像，比 GitHub 稳
export ELECTRON_BUILDER_BINARIES_MIRROR="${ELECTRON_BUILDER_BINARIES_MIRROR:-https://npmmirror.com/mirrors/electron-builder-binaries/}"
export ELECTRON_MIRROR="${ELECTRON_MIRROR:-https://npmmirror.com/mirrors/electron/}"

# ---------------------------------------------------------------------------
# 1. 依赖
# ---------------------------------------------------------------------------
if [[ "$NO_INSTALL" -eq 0 && ! -x node_modules/.bin/electron-builder ]]; then
  step "npm install（electron / electron-builder）"
  npm install --no-audit --no-fund
fi

# ---------------------------------------------------------------------------
# 2. 素材 + 图标（../Assets → windows/assets、build/icon.png）
# ---------------------------------------------------------------------------
step "复制素材"
node scripts/copy-assets.js

# ---------------------------------------------------------------------------
# 3. 清空输出目录，只写仓库根 dist/windows/
# ---------------------------------------------------------------------------
step "清理 $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

PORTABLE_OK=0

# ---------------------------------------------------------------------------
# 4. electron-builder：portable 单文件 exe
# ---------------------------------------------------------------------------
step "electron-builder --win portable --x64"
if npx electron-builder --win portable --x64 --publish never; then
  if [[ -f "$EXE" ]]; then
    PORTABLE_OK=1
    echo "portable 成功：$EXE"
  else
    warn "electron-builder 退出 0，但没有找到 $EXE"
  fi
else
  warn "portable target 失败（常见原因：macOS 上需要 Wine / NSIS 资源下载失败）"
fi

# ---------------------------------------------------------------------------
# 5. electron-builder：zip 兜底（无论 portable 是否成功都要）
# ---------------------------------------------------------------------------
step "electron-builder --win zip --x64"
if ! npx electron-builder --win zip --x64 --publish never; then
  die "zip target 也失败了，看上面日志；这通常是 electron Windows 包下载失败（检查代理）"
fi
[[ -f "$ZIP" ]] || die "zip 目标没有产出 $ZIP"
echo "zip 成功：$ZIP"

# ---------------------------------------------------------------------------
# 6. fallback：7z SFX 把 zip 包成单文件 exe
# ---------------------------------------------------------------------------
if [[ "$PORTABLE_OK" -eq 0 ]]; then
  step "portable 不可用 → 尝试 7z SFX 单文件 exe"
  if bash scripts/make-sfx-exe.sh "$ZIP" "$EXE"; then
    echo "7z SFX 成功：$EXE"
  else
    warn "7z SFX 也失败：本次只交付 zip。"
    warn "Windows 用户解压 $ZIP 后双击 PetHub.exe 即可（就是免安装版）。"
  fi
fi

# ---------------------------------------------------------------------------
# 7. 清理中间产物（win-unpacked / .icon-ico / builder-debug.yml），只留交付文件
# ---------------------------------------------------------------------------
step "清理中间产物"
rm -rf "$OUT_DIR/win-unpacked" "$OUT_DIR/.icon-ico" "$OUT_DIR/builder-debug.yml"

# ---------------------------------------------------------------------------
# 8. 校验和 + 汇总
# ---------------------------------------------------------------------------
step "sha256 + 汇总"
(
  cd "$OUT_DIR"
  : > "$(basename "$SHA")"
  for file in "$(basename "$EXE")" "$(basename "$ZIP")"; do
    if [[ -f "$file" ]]; then
      shasum -a 256 "$file" >> "$(basename "$SHA")"
    fi
  done
)

echo
echo "产物目录：$OUT_DIR"
for file in "$EXE" "$ZIP" "$SHA"; do
  if [[ -f "$file" ]]; then
    printf '  %-46s %10s bytes  %s\n' "$(basename "$file")" "$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")" "$(shasum -a 256 "$file" | cut -d' ' -f1)"
  else
    printf '  %-46s %s\n' "$(basename "$file")" "（没有生成）"
  fi
done

if [[ -f "$EXE" ]]; then
  echo
  echo "PASS 单文件 exe 就绪：$EXE"
else
  echo
  echo "WARN 本次没有单文件 exe，只有 zip：$ZIP"
fi
echo "提醒：Windows 实机尚未验证（见 windows/README.md「已知限制」）。"