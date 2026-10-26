#!/bin/bash
# 构建桌宠合集：环境检查 → 编译 → 打包资源 → 本地签名 → 自检 →（可选）产出可分发文件
#
#   ./build.sh                 编译并自检，产物在 build/桌宠合集.app
#   ./build.sh --package       另外产出 dist/ 下的 zip、dmg 和 sha256 校验文件
#   ./build.sh --no-self-test  跳过自检（没有图形会话的环境里用）
#
# 环境变量：PET_VERSION（默认 1.1.0）、PET_BUILD（默认 1）
# 成功时最后一行输出 PASS（用了 --no-self-test 则没有）。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="桌宠合集"
EXECUTABLE="PetHub"
BUNDLE_ID="local.pethub.app"
VERSION="${PET_VERSION:-1.1.0}"
BUILD_NUMBER="${PET_BUILD:-1}"
DEPLOY_TARGET="arm64-apple-macosx14.0"
BUNDLE="build/$APP_NAME.app"
DIST="dist"
PACKAGE=0
SELF_TEST=1

for arg in "$@"; do
    case "$arg" in
        --package) PACKAGE=1 ;;
        --no-self-test) SELF_TEST=0 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) printf '未知参数：%s（可用：--package / --no-self-test / --help）\n' "$arg" >&2; exit 2 ;;
    esac
done

die() { printf '\n构建中止：%s\n' "$1" >&2; exit 1; }

check_environment() {
    [ "$(uname -s)" = "Darwin" ] || die "只能在 macOS 上构建，当前系统是 $(uname -s)。"
    local arch
    arch="$(uname -m)"
    if [ "$arch" != "arm64" ]; then
        die "本项目只支持 Apple Silicon（arm64），当前是 $arch。Intel Mac 需把 DEPLOY_TARGET 改成 x86_64-apple-macosx14.0 后自行验证。"
    fi
    local os_major
    os_major="$(sw_vers -productVersion | cut -d. -f1)"
    if [ "$os_major" -lt 14 ]; then
        die "需要 macOS 14 或更新版本，当前是 $(sw_vers -productVersion)。"
    fi
    if ! command -v swiftc >/dev/null 2>&1; then
        die "找不到 swiftc。先安装 Xcode Command Line Tools：
    xcode-select --install
装完重新运行本脚本（不需要完整 Xcode）。"
    fi
}

compile() {
    printf '编译中…\n'

    # Sources/ 下的全部 .swift 一起编译：main.swift 是入口，其余文件顺序无所谓。
    local -a sources=()
    while IFS= read -r file; do
        sources+=("$file")
    done < <(find Sources -type f -name '*.swift' -print | sort)
    [ "${#sources[@]}" -gt 0 ] || die "Sources/ 里没有 .swift 文件，仓库不完整。"
    [ -f Sources/main.swift ] || die "缺少 Sources/main.swift（程序入口）。"

    rm -rf "$BUNDLE"
    mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
    if ! swiftc -O -target "$DEPLOY_TARGET" \
        -framework AppKit -framework AVFoundation -framework CoreImage \
        -framework IOKit -framework Network \
        "${sources[@]}" -o "$BUNDLE/Contents/MacOS/$EXECUTABLE"; then
        die "swiftc 编译失败。把上面的完整报错保留下来；若是素材或 Sources 缺文件，先确认四个素材目录都在。"
    fi

    # 四只的素材各自一个目录，App 里按原目录名读；果冻的三个图标也在 jelly/ 里。
    local pet
    for pet in shaolan sun fengge jelly; do
        [ -d "Assets/$pet" ] || die "缺少素材目录 Assets/$pet/，素材不完整。"
    done
    [ -f Assets/AppIcon.icns ] || die "缺少 Assets/AppIcon.icns。先生成合集图标：
    swift Tools/make-icon.swift"
    [ -f LICENSE ] || die "缺少 LICENSE，仓库不完整。"

    cp -R Assets/shaolan Assets/sun Assets/fengge Assets/jelly "$BUNDLE/Contents/Resources/"
    cp Assets/AppIcon.icns "$BUNDLE/Contents/Resources/"
    cp LICENSE "$BUNDLE/Contents/Resources/"
    if [ -f NOTICE.md ]; then cp NOTICE.md "$BUNDLE/Contents/Resources/"; fi
    if [ -d licenses ]; then cp -R licenses "$BUNDLE/Contents/Resources/"; fi

    cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$EXECUTABLE</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST

    # 从下载目录 / iCloud 拷来的文件可能带资源叉或隔离标记，会让签名失败。
    # FinderInfo 偶尔会被 iCloud 立刻加回来，重试几次；仍不通过就报错，别静默放过。
    local signed=0
    for _ in 1 2 3; do
        xattr -cr "$BUNDLE" 2>/dev/null || true
        if codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 \
            && codesign --verify "$BUNDLE" >/dev/null 2>&1; then
            signed=1
            break
        fi
        sleep 0.2
    done
    [ "$signed" = "1" ] || die "本地签名失败。若项目放在 iCloud 同步目录里，先把整个仓库拷到本地磁盘再试。"

    printf '编译完成：%s\n' "$BUNDLE"
}

self_test() {
    printf '自检中…\n'
    local out last
    if ! out="$("$BUNDLE/Contents/MacOS/$EXECUTABLE" --self-test 2>&1)"; then
        printf '%s\n' "$out" >&2
        die "自检未通过（上面每行 FAIL 都指向具体环节）。若报素材缺失，请重新完整下载素材。"
    fi
    last="$(printf '%s\n' "$out" | tail -1)"
    if [ "$last" != "PASS" ]; then
        printf '%s\n' "$out" >&2
        die "自检最后一行不是 PASS，而是：$last"
    fi
    # 保留每项检查的输出，最后那行 PASS 放到整个构建的最后打印。
    printf '%s\n' "$out" | sed '$d'
}

package() {
    local base="PetHub-$VERSION"
    local dmg="$DIST/$base.dmg"
    local stage
    mkdir -p "$DIST"
    rm -f "$DIST/$base.zip" "$dmg" "$DIST/$base.sha256"
    printf '打包中…\n'

    # zip 用 ditto 生成：Finder 双击和 unzip 都能正确解出中文文件名。
    ditto -c -k --keepParent "$BUNDLE" "$DIST/$base.zip" || die "生成 zip 失败。"

    # dmg 里只放 app 和「应用程序」软链，拖进去就是安装。
    stage="$(mktemp -d)"
    cp -R "$BUNDLE" "$stage/" || { rm -rf "$stage"; die "复制 app 到 dmg 暂存目录失败。"; }
    ln -s /Applications "$stage/Applications"
    if ! hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$stage" -ov -format UDZO "$dmg"; then
        rm -rf "$stage"
        die "生成 dmg 失败。"
    fi
    rm -rf "$stage"
    hdiutil verify "$dmg" >/dev/null 2>&1 || die "dmg 校验失败：$dmg"

    ( cd "$DIST" && shasum -a 256 "$base.zip" "$base.dmg" > "$base.sha256" )
    printf '分发包：\n'
    ls -lh "$DIST" | sed 1d | sed 's/^/  /'
}

check_environment
compile
if [ "$SELF_TEST" = "1" ]; then self_test; fi
if [ "$PACKAGE" = "1" ]; then package; fi
printf '完成：%s\n' "$BUNDLE"
printf '安装：./install.sh（或把 app 拖进「应用程序」）\n'
if [ "$SELF_TEST" = "1" ]; then printf 'PASS\n'; fi