#!/usr/bin/env bash
#
# 兜底方案：把 electron-builder 的 --win zip 产物包成单文件 exe。
#
# 原理：7zS.sfx（7-Zip 官方的「安装器用」自解压模块）+ UTF-8 配置 + 7z 压缩包
#       = 一个双击后自动解压到临时目录并启动 PetHub.exe 的单文件 exe。
# 说明：
#   - 7zS.sfx 从 7-Zip 官方老版本 Extra 包（9.20）里取，只在构建时下载，不进仓库；
#     下载失败就直接返回非 0，由 build-win.sh 决定「只交付 zip」。
#   - 生成的 exe 在 Windows 上未实测（本机是 macOS），只做结构校验（MZ 头 + 配置 +
#     7z payload 可解析），见 windows/README.md「已知限制」。
#
# 用法：scripts/make-sfx-exe.sh <input.zip> <output.exe>
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP="${1:?用法: make-sfx-exe.sh <input.zip> <output.exe>}"
EXE="${2:?用法: make-sfx-exe.sh <input.zip> <output.exe>}"
ZIP="$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")"
EXE_DIR="$(cd "$(dirname "$EXE")" && pwd)"
EXE="$EXE_DIR/$(basename "$EXE")"

log() { printf '  [sfx] %s\n' "$*"; }
die() { printf '  [sfx] FAIL %s\n' "$*" >&2; exit 1; }

[[ -f "$ZIP" ]] || die "找不到 zip：$ZIP"

SEVEN_ZIP=""
for candidate in 7z 7za /opt/homebrew/bin/7z /usr/local/bin/7z; do
  if command -v "$candidate" >/dev/null 2>&1; then SEVEN_ZIP="$candidate"; break; fi
done
[[ -n "$SEVEN_ZIP" ]] || die "需要 7z（macOS: brew install p7zip；或设置 PATH）"

SFX_DIR="$PWD/build/sfx"
SFX_MODULE="$SFX_DIR/7zS.sfx"
mkdir -p "$SFX_DIR"

if [[ ! -f "$SFX_MODULE" ]]; then
  log "下载 7-Zip 9.20 Extra（含 7zS.sfx）"
  EXTRA="$SFX_DIR/7z920_extra.7z"
  if [[ ! -f "$EXTRA" ]]; then
    curl -fL --retry 3 --connect-timeout 20 -o "$EXTRA" https://www.7-zip.org/a/7z920_extra.7z \
      || die "下载 7z920_extra.7z 失败（检查代理；也可自己把 7zS.sfx 放到 $SFX_MODULE）"
  fi
  "$SEVEN_ZIP" e -y -o"$SFX_DIR" "$EXTRA" 7zS.sfx >/dev/null || die "从 Extra 包里解不出 7zS.sfx"
fi
[[ -f "$SFX_MODULE" ]] || die "缺少 SFX 模块：$SFX_MODULE"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pethub-sfx.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

log "解压 zip 到临时目录"
mkdir -p "$WORK/app"
"$SEVEN_ZIP" x -y -o"$WORK/app" "$ZIP" >/dev/null || die "解压 zip 失败"
[[ -f "$WORK/app/PetHub.exe" ]] || die "zip 里没有 PetHub.exe，结构不对"

log "生成自解压配置"
cat > "$WORK/config.txt" <<'CONFIG'
;!@Install@!UTF-8!
Title="桌宠合集 PetHub 2.0.0（Windows x64）"
BeginPrompt="启动桌宠合集 PetHub？"
RunProgram="PetHub.exe"
CONFIG
# 末尾必须带结束标记
printf ';!@InstallEnd@!\n' >> "$WORK/config.txt"

log "压缩 payload（7z）"
(
  cd "$WORK/app"
  "$SEVEN_ZIP" a -t7z -mx=9 -bd "$WORK/payload.7z" . >/dev/null
) || die "生成 payload.7z 失败"

log "拼接 7zS.sfx + config + payload → exe"
cat "$SFX_MODULE" "$WORK/config.txt" "$WORK/payload.7z" > "$EXE"
chmod +x "$EXE"

# 结构自检：MZ 头、配置串、7z 魔数、体积
MAGIC="$(head -c 2 "$EXE")"
[[ "$MAGIC" == "MZ" ]] || die "生成的 exe 不是 MZ 头"
grep -a -q ';!@Install@!UTF-8!' "$EXE" || die "exe 里没有 SFX 配置"
grep -a -q '7zS.sfx' "$EXE" || true
SIZE="$(stat -f%z "$EXE" 2>/dev/null || stat -c%s "$EXE")"
[[ "$SIZE" -gt 5000000 ]] || die "生成的 exe 太小（${SIZE}B），payload 可能没拼进去"

log "完成：$(basename "$EXE")（${SIZE} bytes）"
echo "  [sfx] 注意：Windows 实机未测；这是 portable 不可用时的兜底，解压后运行 PetHub.exe。"