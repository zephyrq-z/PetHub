#!/bin/bash
# 一键安装桌宠合集：编译（如需）→ 装进「应用程序」→ 去掉下载隔离标记 → 启动
#
#   ./install.sh                    从 build/ 安装（没有就编译），然后启动
#   ./install.sh --build            强制重新编译再安装
#   ./install.sh --from 路径.app     安装一个已有的应用包（比如从 dmg 拖到下载文件夹的那个）
#   ./install.sh --uninstall        退出并删除「应用程序」里的合集（保留设置，不动四个独立 App）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="桌宠合集"
EXECUTABLE="PetHub"
BUILD_APP="build/$APP_NAME.app"
TARGET="/Applications/$APP_NAME.app"
SOURCE=""
FORCE_BUILD=0

die() { printf '\n安装中止：%s\n' "$1" >&2; exit 1; }
quit_running() { pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true; }

case "${1:-}" in
    --uninstall)
        quit_running
        if [ ! -e "$TARGET" ]; then
            printf '「应用程序」里没有%s，无需卸载。\n' "$APP_NAME"; exit 0
        fi
        rm -rf "$TARGET" || die "删除 $TARGET 失败，可能需要：sudo ./install.sh --uninstall"
        printf '已卸载 %s。\n' "$TARGET"
        printf '四只的显示状态、位置、音量等设置仍保留在用户偏好里（local.pethub.app）；原来那四个独立 App 不受影响。\n'
        exit 0
        ;;
    --from)
        SOURCE="${2:-}"
        if [ -z "$SOURCE" ] || [ ! -d "$SOURCE" ]; then
            die "用法：./install.sh --from /路径/桌宠合集.app"
        fi
        ;;
    --build) FORCE_BUILD=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    "") ;;
    *) printf '未知参数：%s（可用：--from 路径 / --build / --uninstall）\n' "$1" >&2; exit 2 ;;
esac

if [ -n "$SOURCE" ]; then
    BUNDLE="$SOURCE"
else
    BUNDLE="$BUILD_APP"
    if [ "$FORCE_BUILD" = "1" ] || [ ! -d "$BUNDLE" ]; then ./build.sh; fi
fi
[ -d "$BUNDLE" ] || die "找不到 $BUNDLE。先运行 ./build.sh 编译。"

quit_running
sleep 0.5
# 覆盖安装：先删旧版，避免新旧签名混杂导致启动失败。
if [ -e "$TARGET" ]; then rm -rf "$TARGET"; fi
cp -R "$BUNDLE" "$TARGET" || die "写入 $TARGET 失败。需要管理员权限时改用：sudo ./install.sh"

# 从浏览器、dmg 或网盘拿到的包会带 com.apple.quarantine，本地签名会被 Gatekeeper 拦住。
before="$(xattr -p com.apple.quarantine "$TARGET" 2>/dev/null || true)"
xattr -cr "$TARGET" 2>/dev/null || true
if [ -n "$before" ]; then printf '已移除下载隔离标记。\n'; fi
# 拷进「应用程序」后再做一次本地签名：顺手清掉 iCloud 留下的 FinderInfo。
codesign --force --sign - "$TARGET" >/dev/null 2>&1 || true

open "$TARGET"
printf '已安装并启动：%s\n' "$TARGET"
printf '入口在菜单栏右侧的「桌宠」：点人物会出声，果冻可以按住拖，右键任意一只改设置。\n'
printf '卸载：./install.sh --uninstall（不动你原来那四个独立 App）。\n'