#!/usr/bin/env swift
// 生成桌宠合集的 App 图标：四张脸排成 2×2，画在 1024×1024 的圆角底板上。
//
//   swift Tools/make-icon.swift
//
// 输入：Assets/{shaolan,sun,fengge}/face.png、Assets/jelly/claude-mark.png
// 输出：build/AppIcon.iconset/（16/32/128/256/512 的 1x 与 2x）
//       Assets/AppIcon.icns（iconutil 打包）
//       /tmp/pethub-icon-preview.png（1024 预览，方便肉眼确认）
//
// 人脸用 Vision 自动找框，再按「脸宽统一」缩放：四张脸在图标里一样大。
// 找不到人脸时退化成居中裁切，不会中断生成。
// 素材有透明底，所以底板、格子都是画出来的，不依赖素材自己的背景色。

import AppKit
import Vision

// MARK: - 小工具

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("图标生成中止：" + message + "\n").data(using: .utf8)!)
    exit(1)
}

func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    min(max(value, lower), upper)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

// MARK: - 四只的素材与配色

/// 一只桌宠在图标里的一张脸。
struct FaceArt {
    let title: String
    let image: NSImage
    /// 脸宽 / 裁切图边长。果冻没有脸，是整张图形，记作 1。
    let faceFraction: CGFloat
    /// 人脸中心在裁切图里的横向位置（0…1，从左算）。
    let fx: CGFloat
    /// 人脸中心在裁切图里的纵向位置（0…1，从顶部算）。
    let fyTop: CGFloat
    /// 期望脸宽占格子边长的比例。四只统一，所以四张脸一样大。
    let targetFraction: CGFloat
    /// 人脸中心放在格子的什么高度（0…1，从顶部算）。
    let anchorTop: CGFloat
    /// 果冻是图形不是人脸，垂直居中即可。
    let isGlyph: Bool
    let accent: NSColor
    let backdrop: NSColor
}

let specs: [(title: String, folder: String, file: String, accent: UInt32, backdrop: UInt32)] = [
    ("薄肌", "shaolan", "face.png", 0x5B7CFA, 0xEDF2FF),
    ("太对了", "sun", "face.png", 0xE8A317, 0xFFF4DF),
    ("峰哥", "fengge", "face.png", 0x4B4B4B, 0xF1F2F4),
    ("果冻", "jelly", "claude-mark.png", 0xD97757, 0xFFF0EA),
]

/// 找出最大的一张人脸，返回 Vision 的归一化框（原点左下）。
func detectFace(in image: CGImage) -> CGRect? {
    let request = VNDetectFaceRectanglesRequest()
    do {
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch {
        return nil
    }
    return (request.results ?? []).max {
        $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
    }?.boundingBox
}

/// 裁出以人脸为中心的正方形；脸四周留约 1.1 倍脸宽的边，够看到头发和一点肩膀。
func faceArt(title: String, file: URL, accent: NSColor, backdrop: NSColor) -> FaceArt {
    guard let image = NSImage(contentsOf: file),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("读不到素材 \(file.path)。请在仓库根目录运行：swift Tools/make-icon.swift")
    }
    let width = CGFloat(cg.width)
    let height = CGFloat(cg.height)

    guard let box = detectFace(in: cg) else {
        // 退化路径：居中裁正方形，脸大概率还在中间。宁可略歪，也不要生成失败。
        let side = min(width, height)
        let crop = cg.cropping(to: CGRect(x: (width - side) / 2, y: (height - side) / 2,
                                         width: side, height: side)) ?? cg
        return FaceArt(title: title,
                       image: NSImage(cgImage: crop, size: NSSize(width: side, height: side)),
                       faceFraction: 0.5, fx: 0.5, fyTop: 0.5,
                       targetFraction: 0.55, anchorTop: 0.47, isGlyph: false,
                       accent: accent, backdrop: backdrop)
    }

    let faceW = box.width * width
    let faceH = box.height * height
    let faceSide = max(faceW, faceH)
    let centerX = (box.origin.x + box.width / 2) * width
    // Vision 的 y 从底部算，这里换成从顶部算，和 CGImage 裁切坐标一致。
    let centerYTop = (1 - box.origin.y - box.height / 2) * height

    let side = min(faceSide * 2.15, min(width, height))
    let cropX = clamp(centerX - side / 2, 0, width - side)
    let cropYTop = clamp(centerYTop - side * 0.47, 0, height - side)

    guard let crop = cg.cropping(to: CGRect(x: cropX, y: cropYTop, width: side, height: side)) else {
        fail("裁切 \(file.lastPathComponent) 失败。")
    }

    return FaceArt(title: title,
                   image: NSImage(cgImage: crop, size: NSSize(width: side, height: side)),
                   faceFraction: faceSide / side,
                   fx: (centerX - cropX) / side,
                   fyTop: (centerYTop - cropYTop) / side,
                   targetFraction: 0.55, anchorTop: 0.47, isGlyph: false,
                   accent: accent, backdrop: backdrop)
}

func glyphArt(title: String, file: URL, accent: NSColor, backdrop: NSColor) -> FaceArt {
    guard let image = NSImage(contentsOf: file),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("读不到素材 \(file.path)。请在仓库根目录运行：swift Tools/make-icon.swift")
    }
    return FaceArt(title: title,
                   image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)),
                   faceFraction: 1, fx: 0.5, fyTop: 0.5,
                   targetFraction: 0.70, anchorTop: 0.50, isGlyph: true,
                   accent: accent, backdrop: backdrop)
}

// MARK: - 画一张图标

let canvasSize: CGFloat = 1024
let boardInset: CGFloat = 56
let boardRadius: CGFloat = 200
let contentInset: CGFloat = 60
let gap: CGFloat = 24

func drawIcon(size: Int, arts: [FaceArt]) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: size, height: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true

    let scale = CGFloat(size) / canvasSize
    let canvas = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    context.cgContext.clear(canvas)

    // 1. 底板：圆角、白到浅灰的渐变、细边、一点投影。
    let board = canvas.insetBy(dx: boardInset * scale, dy: boardInset * scale)
    let boardPath = NSBezierPath(roundedRect: board,
                                 xRadius: boardRadius * scale, yRadius: boardRadius * scale)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 26 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    shadow.set()
    NSColor.white.setFill()
    boardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    if let gradient = NSGradient(colors: [color(0xFFFFFF), color(0xEDF1F6)]) {
        gradient.draw(in: boardPath, angle: -90)
    }
    color(0x000000, alpha: 0.07).setStroke()
    boardPath.lineWidth = max(1, 1.6 * scale)
    boardPath.stroke()

    // 2. 2×2 四张脸。顺序：薄肌 / 太对了 / 峰哥 / 果冻。
    let tile = (board.width - 2 * contentInset * scale - gap * scale) / 2
    let x0 = board.minX + contentInset * scale
    let x1 = x0 + tile + gap * scale
    let yBottom = board.minY + contentInset * scale
    let yTop = yBottom + tile + gap * scale
    let places: [CGPoint] = [
        CGPoint(x: x0, y: yTop),   // 薄肌（左上）
        CGPoint(x: x1, y: yTop),   // 太对了（右上）
        CGPoint(x: x0, y: yBottom),// 峰哥（左下）
        CGPoint(x: x1, y: yBottom),// 果冻（右下）
    ]

    for (art, place) in zip(arts, places) {
        let rect = CGRect(x: place.x, y: place.y, width: tile, height: tile)
        let radius = tile * 0.245
        let tilePath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        art.backdrop.setFill()
        tilePath.fill()

        // 照片按「脸一样大」缩放，多出来的部分裁在格子里。
        let ring = max(1, 6 * scale)
        let clipPath = NSBezierPath(roundedRect: rect.insetBy(dx: ring, dy: ring),
                                    xRadius: max(1, radius - ring), yRadius: max(1, radius - ring))
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        let drawSize = tile * art.targetFraction / art.faceFraction
        let drawX = rect.midX - art.fx * drawSize
        let drawY = rect.minY + rect.height * (1 - art.anchorTop) - (1 - art.fyTop) * drawSize
        art.image.draw(in: NSRect(x: drawX, y: drawY, width: drawSize, height: drawSize),
                       from: NSRect(origin: .zero, size: art.image.size),
                       operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        // 彩色细环：既做边框，也让四只在 16×16 时还能区分。
        art.accent.setStroke()
        let ringPath = NSBezierPath(roundedRect: rect.insetBy(dx: ring / 2, dy: ring / 2),
                                    xRadius: max(1, radius - ring / 2), yRadius: max(1, radius - ring / 2))
        ringPath.lineWidth = ring
        ringPath.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - 入口

let fileManager = FileManager.default
var root = URL(fileURLWithPath: fileManager.currentDirectoryPath)

// 允许在任意目录用绝对路径运行：找不到 Assets/ 就按脚本位置推仓库根目录。
if !fileManager.fileExists(atPath: root.appendingPathComponent("Assets/shaolan/face.png").path) {
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
}
guard fileManager.fileExists(atPath: root.appendingPathComponent("Assets/shaolan/face.png").path) else {
    fail("找不到 Assets/。请在仓库根目录运行：swift Tools/make-icon.swift")
}

print("读取四张脸…")
var arts: [FaceArt] = []
for spec in specs {
    let file = root.appendingPathComponent("Assets/\(spec.folder)/\(spec.file)")
    let accent = color(spec.accent)
    let backdrop = color(spec.backdrop)
    let art: FaceArt
    if spec.folder == "jelly" {
        art = glyphArt(title: spec.title, file: file, accent: accent, backdrop: backdrop)
    } else {
        art = faceArt(title: spec.title, file: file, accent: accent, backdrop: backdrop)
    }
    arts.append(art)
    print("  \(spec.title)：\(spec.folder)/\(spec.file)（脸占裁切图 \(String(format: "%.0f", art.faceFraction * 100))%）")
}

let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
do {
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
} catch {
    fail("创建 \(iconset.path) 失败：\(error.localizedDescription)")
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

print("绘制 iconset（16/32/128/256/512 的 1x、2x）…")
for (name, pixels) in variants {
    guard let data = drawIcon(size: pixels, arts: arts) else {
        fail("渲染 \(name) 失败。")
    }
    do {
        try data.write(to: iconset.appendingPathComponent(name))
    } catch {
        fail("写 \(name) 失败：\(error.localizedDescription)")
    }
}

let icns = root.appendingPathComponent("Assets/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
} catch {
    fail("调用 iconutil 失败：\(error.localizedDescription)")
}
guard iconutil.terminationStatus == 0,
      fileManager.fileExists(atPath: icns.path),
      let bytes = try? fileManager.attributesOfItem(atPath: icns.path)[.size] as? Int else {
    fail("iconutil 没能生成 \(icns.path)（退出码 \(iconutil.terminationStatus)）。")
}

// 1024 预览单独放 /tmp，给 Lead 和人眼确认。
if let preview = drawIcon(size: 1024, arts: arts) {
    try? preview.write(to: URL(fileURLWithPath: "/tmp/pethub-icon-preview.png"))
}

print("图标已生成：Assets/AppIcon.icns（\(bytes) 字节）")
print("iconset：build/AppIcon.iconset/")
print("预览：/tmp/pethub-icon-preview.png")