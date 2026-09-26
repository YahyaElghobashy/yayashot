// Generates YayaShot's icon assets with AppKit and CoreGraphics only (no ImageMagick):
//
//   Resources/Generated/AppIcon.icns        the camera (Resources/Brand/AppIcon-Source.png,
//                                           transparent) on a dark space tile with a portal glow,
//                                           on Apple's 824-in-1024 icon grid
//   Resources/Brand/AppIcon-1024.png        the same tile as a PNG (README, installer art)
//   Resources/Generated/MenuBarIcon.pdf     the menu bar template glyph as vector art (18 × 18 pt)
//   Resources/Generated/MenuBarIcon*.png    the same glyph rasterised at 18 and 36 px
//   build/icon-previews/*.png               review sheets (not shipped)
//
// The glyph is drawn, not traced: a camera body with the concept art's three tells
// (a bubble dome, a bent antenna with a bulb, a big lens with a glint), so it stays
// recognisable at menu bar size.
//
// usage: swift Tools/MakeIcons.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func path(_ rel: String) -> URL { root.appendingPathComponent(rel) }
try? FileManager.default.createDirectory(at: path("Resources/Generated"), withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: path("build/icon-previews"), withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func bitmap(_ px: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - App icon

guard let cameraSource = NSImage(contentsOf: path("Resources/Brand/AppIcon-Source.png")),
      let camera = cameraSource.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Resources/Brand/AppIcon-Source.png is missing")
}

func appIcon(_ px: Int) -> CGImage {
    bitmap(px) { ctx in
        let s = CGFloat(px) / 1024
        ctx.scaleBy(x: s, y: s)
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

        // Drop shadow under the tile, as macOS icons have.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.35))
        ctx.addPath(tilePath); ctx.setFillColor(rgb(0x0C0A1C)); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tilePath); ctx.clip()
        // Deep space gradient.
        let space = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0x2A2360), rgb(0x0B0918)] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(space, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
        // Portal-green glow behind the lens.
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(0x8BFF3C, 0.55), rgb(0x3FD12A, 0.18), rgb(0x3FD12A, 0)] as CFArray,
                              locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 590, y: 470), startRadius: 0,
                               endCenter: CGPoint(x: 560, y: 480), endRadius: 470, options: [])
        // A deterministic scatter of stars.
        var seed: UInt64 = 0x59_41_59_41_53_48_4F_54
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max)
        }
        for _ in 0..<46 {
            let p = CGPoint(x: 110 + next() * 804, y: 110 + next() * 804)
            let r = 1.2 + next() * 2.6
            ctx.setFillColor(rgb(0xFFFFFF, 0.25 + next() * 0.5))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        // Subtle top sheen.
        let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 620), options: [])
        ctx.restoreGState()

        // The camera, slightly larger than the tile's safe area so it feels bold.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.45))
        let side: CGFloat = 780
        ctx.draw(camera, in: CGRect(x: 512 - side / 2, y: 512 - side / 2 - 6, width: side, height: side))
        ctx.restoreGState()

        // Hairline edge to separate the tile from dark wallpapers.
        ctx.addPath(tilePath); ctx.setStrokeColor(rgb(0xFFFFFF, 0.14)); ctx.setLineWidth(2); ctx.strokePath()
    }
}

let iconset = path("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(appIcon(base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(appIcon(base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
writePNG(appIcon(1024), path("Resources/Brand/AppIcon-1024.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", path("Resources/Generated/AppIcon.icns").path]
try! iconutil.run(); iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

// MARK: - Menu bar glyph (18 × 18 pt, drawn with even-odd holes)

func glyphPath() -> CGPath {
    let p = CGMutablePath()
    // Body.
    p.addPath(CGPath(roundedRect: CGRect(x: 1.25, y: 1.75, width: 15.5, height: 9.25), cornerWidth: 2.4, cornerHeight: 2.4, transform: nil))
    // Bubble dome sitting on the body.
    p.move(to: CGPoint(x: 4.3, y: 11.0))
    p.addArc(center: CGPoint(x: 7.6, y: 11.0), radius: 3.3, startAngle: .pi, endAngle: 0, clockwise: true)
    p.closeSubpath()
    // Viewfinder block on the right.
    p.addPath(CGPath(roundedRect: CGRect(x: 11.8, y: 11.0, width: 2.4, height: 1.5), cornerWidth: 0.45, cornerHeight: 0.45, transform: nil))
    // Bent antenna (butt caps so it only touches the body) and its bulb.
    let antenna = CGMutablePath()
    antenna.move(to: CGPoint(x: 3.35, y: 11.0))
    antenna.addLine(to: CGPoint(x: 3.35, y: 12.9))
    antenna.addLine(to: CGPoint(x: 2.45, y: 14.9))
    p.addPath(antenna.copy(strokingWithWidth: 1.05, lineCap: .butt, lineJoin: .round, miterLimit: 4))
    p.addEllipse(in: CGRect(x: 2.45 - 1.35, y: 16.25 - 1.35, width: 2.7, height: 2.7))
    // Holes (even-odd): the lens well, a plasma bubble in the dome, the record light,
    // and the seam between dome and body.
    p.addEllipse(in: CGRect(x: 11.2 - 3.7, y: 6.2 - 3.7, width: 7.4, height: 7.4))
    p.addEllipse(in: CGRect(x: 7.9 - 0.75, y: 12.35 - 0.75, width: 1.5, height: 1.5))
    p.addEllipse(in: CGRect(x: 3.7 - 0.85, y: 8.5 - 0.85, width: 1.7, height: 1.7))
    p.addRect(CGRect(x: 4.7, y: 10.75, width: 5.8, height: 0.5))
    // Lens glass inside the well (filled again), with a glint hole.
    p.addEllipse(in: CGRect(x: 11.2 - 2.5, y: 6.2 - 2.5, width: 5.0, height: 5.0))
    p.addEllipse(in: CGRect(x: 10.25 - 0.7, y: 7.15 - 0.7, width: 1.4, height: 1.4))
    return p
}

func drawGlyph(_ ctx: CGContext, color: CGColor = rgb(0x000000)) {
    ctx.addPath(glyphPath())
    ctx.setFillColor(color)
    ctx.fillPath(using: .evenOdd)
}

// Vector PDF.
let pdfURL = path("Resources/Generated/MenuBarIcon.pdf")
var box = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil); drawGlyph(pdf); pdf.endPDFPage(); pdf.closePDF()

// Raster fallbacks.
for (scale, name) in [(1, "MenuBarIcon.png"), (2, "MenuBarIcon@2x.png")] {
    let img = bitmap(18 * scale) { ctx in ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale)); drawGlyph(ctx) }
    writePNG(img, path("Resources/Generated/\(name)"))
}

// MARK: - Previews

let sheet = bitmap(720) { ctx in
    // Light and dark menu bars at 1x and 2x, magnified 8x / 4x with nearest-neighbour.
    ctx.interpolationQuality = .none
    let rows: [(CGColor, CGColor)] = [(rgb(0xECECEC), rgb(0x000000)), (rgb(0x1E1E1E), rgb(0xFFFFFF))]
    for (i, (bar, ink)) in rows.enumerated() {
        let y = CGFloat(i) * 360
        ctx.setFillColor(bar); ctx.fill(CGRect(x: 0, y: y, width: 720, height: 360))
        let one = bitmap(18) { c in drawGlyph(c, color: ink) }
        let two = bitmap(36) { c in c.scaleBy(x: 2, y: 2); drawGlyph(c, color: ink) }
        ctx.draw(one, in: CGRect(x: 40, y: y + 60, width: 18 * 12, height: 18 * 12))
        ctx.draw(two, in: CGRect(x: 320, y: y + 60, width: 36 * 6, height: 36 * 6))
        ctx.interpolationQuality = .high
        ctx.draw(two, in: CGRect(x: 620, y: y + 160, width: 18, height: 18))
        ctx.draw(two, in: CGRect(x: 660, y: y + 158, width: 22, height: 22))
        ctx.interpolationQuality = .none
    }
}
writePNG(sheet, path("build/icon-previews/menubar.png"))
writePNG(appIcon(512), path("build/icon-previews/appicon-512.png"))
print("✓ AppIcon.icns, AppIcon-1024.png, MenuBarIcon.pdf/.png/@2x.png, previews in build/icon-previews")
