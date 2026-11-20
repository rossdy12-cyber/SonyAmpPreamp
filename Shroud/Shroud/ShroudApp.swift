import SwiftUI
import UIKit
import UserNotifications

// ============================================================
//  SHROUD — gothic wallpaper forge for the iPhone 16
//  Procedurally renders full-resolution gothic wallpapers
//  (cathedrals, blood moons, damask, graveyards, rose windows,
//  ashen forests) at exact device resolution, saves them to
//  Photos, keeps a vault of favorites, and can deliver a fresh
//  shroud nightly via local notification. Nothing leaves the device.
// ============================================================

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)

// MARK: - Design model

struct ShroudDesign: Identifiable, Codable {
    let id: UUID
    let theme: Int
    let seed: UInt64
    let created: Date

    var themeName: String { ShroudForge.themeNames[max(0, min(ShroudForge.themeNames.count - 1, theme))] }
}

// MARK: - Deterministic RNG

enum ShroudRng {
    /// mulberry32 — same seed always weaves the same shroud
    static func make(_ seed: UInt64) -> () -> Double {
        var state = seed &* 2654435761 &+ 1
        return {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
        }
    }
}

// MARK: - The Forge (Core Graphics renderer)

enum ShroudForge {

    static let themeNames = [
        "CATHEDRAL DUSK",
        "BLOOD MOON VIGIL",
        "VICTORIAN DAMASK",
        "REAPER'S GATE",
        "ROSE WINDOW",
        "ASHEN FOREST"
    ]

    // Exact native resolutions (portrait, pixels)
    static let devices: [(String, CGSize)] = [
        ("iPhone 16", CGSize(width: 1179, height: 2556)),
        ("iPhone 16 Plus", CGSize(width: 1290, height: 2796)),
        ("iPhone 16 Pro", CGSize(width: 1206, height: 2622)),
        ("iPhone 16 Pro Max", CGSize(width: 1320, height: 2868))
    ]

    static func cg(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
    }

    // MARK: render entry

    static func render(theme: Int, seed: UInt64, size: CGSize) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: fmt)
        return renderer.image { ctx in
            let c = ctx.cgContext
            let rng = ShroudRng.make(seed &+ UInt64(theme &+ 1))
            switch max(0, min(themeNames.count - 1, theme)) {
            case 0: drawCathedral(c, size, rng)
            case 1: drawBloodMoon(c, size, rng)
            case 2: drawDamask(c, size, rng)
            case 3: drawReapersGate(c, size, rng)
            case 4: drawRoseWindow(c, size, rng)
            default: drawAshenForest(c, size, rng)
            }
            drawVignette(c, size)
            drawGrain(c, size, rng)
        }
    }

    // MARK: shared atmosphere

    static func sky(_ c: CGContext, _ size: CGSize, _ top: (CGFloat, CGFloat, CGFloat), _ bottom: (CGFloat, CGFloat, CGFloat)) {
        let space = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: space, colors: [cg(top.0, top.1, top.2), cg(bottom.0, bottom.1, bottom.2)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }

    static func glow(_ c: CGContext, _ size: CGSize, center: CGPoint, radius: CGFloat, color: (CGFloat, CGFloat, CGFloat), strength: CGFloat) {
        let space = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: space, colors: [cg(color.0, color.1, color.2, strength), cg(color.0, color.1, color.2, 0)] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    static func fogBand(_ c: CGContext, _ size: CGSize, y: CGFloat, thickness: CGFloat, alpha: CGFloat) {
        let space = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: space, colors: [cg(0.55, 0.48, 0.52, 0), cg(0.72, 0.62, 0.66, alpha), cg(0.55, 0.48, 0.52, 0)] as CFArray, locations: [0, 0.5, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: y - thickness / 2), end: CGPoint(x: 0, y: y + thickness / 2), options: [])
    }

    static func drawVignette(_ c: CGContext, _ size: CGSize) {
        let space = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: space, colors: [cg(0, 0, 0, 0), cg(0, 0, 0, 0.58)] as CFArray, locations: [0.5, 1])!
        let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
        c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width * 1.05, options: [.drawsAfterEndLocation])
    }

    static func drawGrain(_ c: CGContext, _ size: CGSize, _ rng: () -> Double) {
        for _ in 0..<1400 {
            let x = rng() * size.width
            let y = rng() * size.height
            let a = CGFloat(rng()) * 0.05
            c.setFillColor(rng() < 0.5 ? cg(1, 0.9, 0.92, a) : cg(0, 0, 0, a * 1.6))
            c.fill(CGRect(x: x, y: y, width: 2, height: 2))
        }
    }

    static func pointedArch(_ c: CGContext, cx: CGFloat, yBase: CGFloat, w: CGFloat, h: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - w / 2, y: yBase))
        path.addLine(to: CGPoint(x: cx - w / 2, y: yBase - h * 0.55))
        path.addQuadCurve(to: CGPoint(x: cx, y: yBase - h), control: CGPoint(x: cx - w * 0.62, y: yBase - h * 0.55))
        path.addQuadCurve(to: CGPoint(x: cx + w / 2, y: yBase - h * 0.55), control: CGPoint(x: cx + w * 0.62, y: yBase - h * 0.55))
        path.addLine(to: CGPoint(x: cx + w / 2, y: yBase))
        path.closeSubpath()
        c.addPath(path)
        c.fillPath()
    }

    static func branch(_ c: CGContext, _ p: CGPoint, _ angle: CGFloat, _ len: CGFloat, _ width: CGFloat, _ depth: Int, _ color: CGColor, _ rng: () -> Double) {
        guard depth > 0, len > 2 else { return }
        let end = CGPoint(x: p.x + sin(angle) * len, y: p.y - cos(angle) * len)
        c.setStrokeColor(color)
        c.setLineWidth(max(0.8, width))
        c.setLineCap(.round)
        c.move(to: p)
        c.addLine(to: end)
        c.strokePath()
        let n = 2 + (rng() < 0.3 ? 1 : 0)
        for _ in 0..<n {
            let spread = (rng() - 0.5) * 1.25
            branch(c, end, angle + spread, len * (0.6 + rng() * 0.2), width * 0.62, depth - 1, color, rng)
        }
    }

    static func drawBat(_ c: CGContext, _ p: CGPoint, span: CGFloat, flap: CGFloat, color: CGColor) {
        c.setFillColor(color)
        let path = CGMutablePath()
        path.move(to: p)
        path.addLine(to: CGPoint(x: p.x - span, y: p.y - span * (0.18 + flap)))
        path.addQuadCurve(to: CGPoint(x: p.x - span * 0.45, y: p.y + span * 0.16), control: CGPoint(x: p.x - span * 0.58, y: p.y + span * 0.04))
        path.addLine(to: p)
        path.addLine(to: CGPoint(x: p.x + span * 0.45, y: p.y + span * 0.16))
        path.addQuadCurve(to: CGPoint(x: p.x + span, y: p.y - span * (0.18 + flap)), control: CGPoint(x: p.x + span * 0.58, y: p.y + span * 0.04))
        path.addLine(to: p)
        path.closeSubpath()
        c.addPath(path)
        c.fillPath()
        c.fillEllipse(in: CGRect(x: p.x - span * 0.09, y: p.y - span * 0.12, width: span * 0.18, height: span * 0.26))
    }

    // MARK: THEME 0 — Cathedral Dusk

    static func drawCathedral(_ c: CGContext, _ size: CGSize, _ rng: () -> Double) {
        let w = size.width, h = size.height
        sky(c, size, (0.015, 0.005, 0.02), (0.11, 0.03, 0.06))
        glow(c, size, center: CGPoint(x: w * 0.5, y: h * 0.32), radius: w * 0.75, color: (0.75, 0.12, 0.2), strength: 0.28)
        glow(c, size, center: CGPoint(x: w * 0.5, y: h * 0.3), radius: w * 0.16, color: (1.0, 0.35, 0.3), strength: 0.5)

        // rose window silhouette behind spires
        let roseC = CGPoint(x: w * 0.5, y: h * 0.3)
        let roseR = w * 0.085
        glow(c, size, center: roseC, radius: roseR * 2.6, color: (0.95, 0.3, 0.25), strength: 0.55)
        c.setFillColor(cg(0.9, 0.22, 0.2, 0.85))
        c.fillEllipse(in: CGRect(x: roseC.x - roseR, y: roseC.y - roseR, width: roseR * 2, height: roseR * 2))
        c.setStrokeColor(cg(0.03, 0.01, 0.02, 1))
        c.setLineWidth(roseR * 0.09)
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * 2 * .pi
            c.move(to: roseC)
            c.addLine(to: CGPoint(x: roseC.x + cos(a) * roseR, y: roseC.y + sin(a) * roseR))
            c.strokePath()
        }
        c.setStrokeColor(cg(0.03, 0.01, 0.02, 1))
        c.setLineWidth(roseR * 0.12)
        c.strokeEllipse(in: CGRect(x: roseC.x - roseR, y: roseC.y - roseR, width: roseR * 2, height: roseR * 2))

        // skyline of gothic towers
        var x: CGFloat = -w * 0.02
        while x < w * 1.02 {
            let tw = w * (0.05 + rng() * 0.07)
            let towerH = h * (0.16 + rng() * 0.3)
            let spireH = h * (0.05 + rng() * 0.12)
            let topY = h - towerH
            let dark = cg(0.015, 0.006, 0.014, 1)
            c.setFillColor(dark)
            c.fill(CGRect(x: x, y: topY, width: tw, height: towerH + h * 0.02))
            // spire
            let spire = CGMutablePath()
            spire.move(to: CGPoint(x: x, y: topY))
            spire.addLine(to: CGPoint(x: x + tw * 0.5, y: topY - spireH))
            spire.addLine(to: CGPoint(x: x + tw, y: topY))
            spire.closeSubpath()
            c.addPath(spire)
            c.fillPath()
            // pinnacle on some towers
            if rng() < 0.5 {
                let pw = tw * 0.14
                c.fill(CGRect(x: x - pw * 1.6, y: topY + h * 0.04, width: pw, height: h * 0.05))
                c.fill(CGRect(x: x + tw + pw * 0.6, y: topY + h * 0.04, width: pw, height: h * 0.05))
            }
            // glowing arch slits
            let slits = Int(rng() * 3) + 1
            for _ in 0..<slits {
                let sw = tw * (0.16 + rng() * 0.16)
                let sh = h * (0.02 + rng() * 0.05)
                let sy = topY + towerH * (0.25 + rng() * 0.6)
                let sx = x + tw * (0.2 + rng() * 0.45)
                c.setFillColor(cg(1.0, 0.28, 0.22, 0.28 + rng() * 0.5))
                pointedArch(c, cx: sx, yBase: sy, w: sw, h: sh)
            }
            x += tw * (0.85 + rng() * 0.4)
        }

        // great door at the base
        c.setFillColor(cg(0.012, 0.004, 0.01, 1))
        pointedArch(c, cx: w * 0.5, yBase: h, w: w * 0.2, h: h * 0.1)
        c.setFillColor(cg(1.0, 0.25, 0.2, 0.35))
        pointedArch(c, cx: w * 0.5, yBase: h - h * 0.004, w: w * 0.15, h: h * 0.085)

        fogBand(c, size, y: h * 0.86, thickness: h * 0.1, alpha: 0.14)
        fogBand(c, size, y: h * 0.94, thickness: h * 0.07, alpha: 0.2)
    }

    // MARK: THEME 1 — Blood Moon Vigil

    static func drawBloodMoon(_ c: CGContext, _ size: CGSize, _ rng: () -> Double) {
        let w = size.width, h = size.height
        sky(c, size, (0.02, 0.004, 0.014), (0.09, 0.015, 0.035))
        let moonC = CGPoint(x: w * (0.3 + rng() * 0.4), y: h * (0.16 + rng() * 0.1))
        let moonR = w * (0.2 + rng() * 0.1)
        glow(c, size, center: moonC, radius: moonR * 3.4, color: (0.85, 0.08, 0.14), strength: 0.4)
        // disc
        c.setFillColor(cg(0.82, 0.09, 0.1, 1))
        c.fillEllipse(in: CGRect(x: moonC.x - moonR, y: moonC.y - moonR, width: moonR * 2, height: moonR * 2))
        // craters
        for _ in 0..<9 {
            let cr = moonR * (0.05 + rng() * 0.12)
            let cx = moonC.x + (rng() - 0.5) * moonR * 1.5
            let cy = moonC.y + (rng() - 0.5) * moonR * 1.5
            c.setFillColor(cg(0.6, 0.05, 0.08, 0.55))
            c.fillEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2))
        }
        c.setFillColor(cg(0.45, 0.03, 0.06, 0.4))
        c.fillEllipse(in: CGRect(x: moonC.x - moonR, y: moonC.y - moonR, width: moonR * 2, height: moonR * 2))

        // bats circling the moon
        let bats = 7 + Int(rng() * 6)
        for _ in 0..<bats {
            let bx = moonC.x + (rng() - 0.5) * moonR * 4.2
            let by = moonC.y + (rng() - 0.5) * moonR * 3.2
            let span = w * (0.012 + rng() * 0.028)
            drawBat(c, CGPoint(x: bx, y: by), span: span, flap: rng() * 0.35, color: cg(0.02, 0.004, 0.01, 0.95))
        }

        // far ridge + near hill
        c.setFillColor(cg(0.03, 0.008, 0.02, 1))
        let ridge = CGMutablePath()
        ridge.move(to: CGPoint(x: 0, y: h))
        ridge.addLine(to: CGPoint(x: 0, y: h * 0.78))
        var rx: CGFloat = 0
        while rx < w {
            rx += w * (0.08 + rng() * 0.1)
            ridge.addQuadCurve(to: CGPoint(x: rx, y: h * (0.72 + rng() * 0.1)), control: CGPoint(x: rx - w * 0.05, y: h * (0.66 + rng() * 0.08)))
        }
        ridge.addLine(to: CGPoint(x: w, y: h))
        ridge.closeSubpath()
        c.addPath(ridge)
        c.fillPath()

        // dead tree on the near hill
        let treeX = w * (0.15 + rng() * 0.7)
        branch(c, CGPoint(x: treeX, y: h * 0.93), 0.05, h * 0.09, w * 0.02, 7, cg(0.008, 0.002, 0.006, 1), rng)

        // near hill
        c.setFillColor(cg(0.012, 0.003, 0.01, 1))
        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: 0, y: h))
        hill.addLine(to: CGPoint(x: 0, y: h * 0.9))
        hill.addQuadCurve(to: CGPoint(x: w, y: h * 0.92), control: CGPoint(x: w * 0.5, y: h * 0.84))
        hill.addLine(to: CGPoint(x: w, y: h))
        hill.closeSubpath()
        c.addPath(hill)
        c.fillPath()

        fogBand(c, size, y: h * 0.8, thickness: h * 0.06, alpha: 0.12)
        fogBand(c, size, y: h * 0.9, thickness: h * 0.08, alpha: 0.16)
    }

    // MARK: THEME 2 — Victorian Damask

    static func drawDamask(_ c: CGContext, _ size: CGSize, _ rng: () -> Double) {
        let w = size.width, h = size.height
        sky(c, size, (0.03, 0.006, 0.018), (0.055, 0.01, 0.028))
        let cell = w / 5.0

        // faint diagonal lattice
        c.setStrokeColor(cg(1.0, 0.09, 0.27, 0.06))
        c.setLineWidth(w * 0.0035)
        var d = -h
        while d < w + h {
            c.move(to: CGPoint(x: d, y: 0))
            c.addLine(to: CGPoint(x: d + h, y: h))
            c.strokePath()
            c.move(to: CGPoint(x: d, y: 0))
            c.addLine(to: CGPoint(x: d - h, y: h))
            c.strokePath()
            d += cell
        }

        // damask medallions
        var row: CGFloat = 0
        var y = cell * 0.4
        while y < h + cell {
            var x = row.truncatingRemainder(dividingBy: 2) == 0 ? cell * 0.5 : cell
            while x < w + cell {
                let s = cell * (0.3 + rng() * 0.12)
                let a = CGFloat(0.16 + rng() * 0.3)
                let cc = cg(1.0, 0.09, 0.27, a)
                // diamond
                let dia = CGMutablePath()
                dia.move(to: CGPoint(x: x, y: y - s))
                dia.addLine(to: CGPoint(x: x + s * 0.72, y: y))
                dia.addLine(to: CGPoint(x: x, y: y + s))
                dia.addLine(to: CGPoint(x: x - s * 0.72, y: y))
                dia.closeSubpath()
                c.setStrokeColor(cc)
                c.setLineWidth(s * 0.055)
                c.addPath(dia)
                c.strokePath()
                // quatrefoil heart
                c.setFillColor(cc)
                let q = s * 0.34
                c.fillEllipse(in: CGRect(x: x - q, y: y - q * 1.15, width: q * 2, height: q * 2))
                c.fillEllipse(in: CGRect(x: x - q * 1.35, y: y + q * 0.1, width: q * 1.3, height: q * 1.3))
                c.fillEllipse(in: CGRect(x: x + q * 0.05, y: y + q * 0.1, width: q * 1.3, height: q * 1.3))
                // crown spike + tail
                c.fill(CGRect(x: x - s * 0.045, y: y - s * 1.35, width: s * 0.09, height: s * 0.4))
                let tail = CGMutablePath()
                tail.move(to: CGPoint(x: x, y: y + s * 0.9))
                tail.addQuadCurve(to: CGPoint(x: x + s * 0.22, y: y + s * 1.5), control: CGPoint(x: x + s * 0.1, y: y + s * 1.2))
                tail.addQuadCurve(to: CGPoint(x: x, y: y + s * 1.9), control: CGPoint(x: x + s * 0.18, y: y + s * 1.55))
                tail.addQuadCurve(to: CGPoint(x: x - s * 0.22, y: y + s * 1.5), control: CGPoint(x: x - s * 0.18, y: y + s * 1.55))
                tail.closeSubpath()
                c.addPath(tail)
                c.fillPath()
                x += cell * 1.15
            }
            y += cell * 0.62
            row += 1
        }

        // moody darkening at top/bottom for lock-screen legibility
        let space = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: space, colors: [cg(0, 0, 0, 0.5), cg(0, 0, 0, 0)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h * 0.18), options: [])
        let g2 = CGGradient(colorsSpace: space, colors: [cg(0, 0, 0, 0), cg(0, 0, 0, 0.5)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g2, start: CGPoint(x: 0, y: h * 0.82), end: CGPoint(x: 0, y: h), options: [])
    }

    // MARK: THEME 3 — Reaper's Gate

    static func drawReapersGate(_ c: CGContext, _ size: CGSize, _ rng: () -> Double) {
        let w = size.width, h = size.height
        sky(c, size, (0.018, 0.005, 0.016), (0.1, 0.03, 0.05))
        let moonC = CGPoint(x: w * (0.2 + rng() * 0.6), y: h * 0.2)
        let moonR = w * 0.11
        glow(c, size, center: moonC, radius: moonR * 3, color: (0.75, 0.2, 0.25), strength: 0.4)
        c.setFillColor(cg(0.8, 0.75, 0.7, 0.9))
        c.fillEllipse(in: CGRect(x: moonC.x - moonR, y: moonC.y - moonR, width: moonR * 2, height: moonR * 2))

        // pale glow beyond the gate
        glow(c, size, center: CGPoint(x: w * 0.5, y: h * 0.52), radius: w * 0.5, color: (0.9, 0.5, 0.4), strength: 0.3)

        let groundY = h * 0.72
        // headstones beyond the gate
        for _ in 0..<14 {
            let sx = rng() * w
            let sy = groundY + h * (rng() * 0.14)
            let sw = w * (0.03 + rng() * 0.045)
            let sh = h * (0.03 + rng() * 0.05)
            c.setFillColor(cg(0.02, 0.006, 0.015, 1))
            if rng() < 0.3 {
                // cross
                c.fill(CGRect(x: sx - sw * 0.12, y: sy - sh, width: sw * 0.24, height: sh))
                c.fill(CGRect(x: sx - sw * 0.4, y: sy - sh * 0.72, width: sw * 0.8, height: sh * 0.2))
            } else {
                let rect = CGRect(x: sx - sw / 2, y: sy - sh, width: sw, height: sh)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .pi, endAngle: 0, clockwise: true)
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.closeSubpath()
                c.addPath(path)
                c.fillPath()
            }
        }

        // ground
        c.setFillColor(cg(0.012, 0.003, 0.01, 1))
        c.fill(CGRect(x: 0, y: groundY, width: w, height: h - groundY))

        // the gate: pointed arch frame + bars
        let gw = w * 0.52
        let gh = h * 0.34
        let gx = w * 0.5
        let gy = groundY + h * 0.01
        let frame = CGMutablePath()
        frame.move(to: CGPoint(x: gx - gw / 2, y: gy))
        frame.addLine(to: CGPoint(x: gx - gw / 2, y: gy - gh * 0.55))
        frame.addQuadCurve(to: CGPoint(x: gx, y: gy - gh), control: CGPoint(x: gx - gw * 0.62, y: gy - gh * 0.55))
        frame.addQuadCurve(to: CGPoint(x: gx + gw / 2, y: gy - gh * 0.55), control: CGPoint(x: gx + gw * 0.62, y: gy - gh * 0.55))
        frame.addLine(to: CGPoint(x: gx + gw / 2, y: gy))
        c.addPath(frame)
        c.setStrokeColor(cg(0.008, 0.002, 0.008, 1))
        c.setLineWidth(w * 0.032)
        c.strokePath()

        // bars
        let bars = 9
        for i in 0..<bars {
            let t = CGFloat(i) / CGFloat(bars - 1)
            let bx = gx - gw / 2 + t * gw
            let inset = abs(t - 0.5) * 2 // follow arch curve
            let barTop = gy - gh * (1 - inset * 0.42)
            c.setStrokeColor(cg(0.01, 0.002, 0.008, 1))
            c.setLineWidth(w * 0.012)
            c.move(to: CGPoint(x: bx, y: gy))
            c.addLine(to: CGPoint(x: bx, y: barTop))
            c.strokePath()
            // spike
            let spike = CGMutablePath()
            spike.move(to: CGPoint(x: bx - w * 0.008, y: barTop))
            spike.addLine(to: CGPoint(x: bx, y: barTop - w * 0.028))
            spike.addLine(to: CGPoint(x: bx + w * 0.008, y: barTop))
            spike.closeSubpath()
            c.addPath(spike)
            c.fillPath()
        }
        // horizontal band with spikes
        let bandY = gy - gh * 0.3
        c.setLineWidth(w * 0.014)
        c.move(to: CGPoint(x: gx - gw / 2, y: bandY))
        c.addLine(to: CGPoint(x: gx + gw / 2, y: bandY))
        c.strokePath()

        // reaper silhouette waiting beyond the gate
        let rx = gx + gw * (rng() - 0.5) * 0.5
        let ry = gy - h * 0.005
        let rs = h * 0.09
        c.setFillColor(cg(0.006, 0.001, 0.005, 0.95))
        c.fillEllipse(in: CGRect(x: rx - rs * 0.14, y: ry - rs, width: rs * 0.28, height: rs * 0.3)) // hood head
        let robe = CGMutablePath()
        robe.move(to: CGPoint(x: rx - rs * 0.16, y: ry - rs * 0.72))
        robe.addQuadCurve(to: CGPoint(x: rx - rs * 0.34, y: ry), control: CGPoint(x: rx - rs * 0.3, y: ry - rs * 0.3))
        robe.addLine(to: CGPoint(x: rx + rs * 0.34, y: ry))
        robe.addQuadCurve(to: CGPoint(x: rx + rs * 0.16, y: ry - rs * 0.72), control: CGPoint(x: rx + rs * 0.3, y: ry - rs * 0.3))
        robe.closeSubpath()
        c.addPath(robe)
        c.fillPath()
        // scythe
        c.setStrokeColor(cg(0.006, 0.001, 0.005, 0.95))
        c.setLineWidth(w * 0.006)
        c.move(to: CGPoint(x: rx + rs * 0.3, y: ry))
        c.addLine(to: CGPoint(x: rx + rs * 0.42, y: ry - rs * 1.05))
        c.strokePath()
        let blade = CGMutablePath()
        blade.move(to: CGPoint(x: rx + rs * 0.42, y: ry - rs * 1.05))
        blade.addQuadCurve(to: CGPoint(x: rx - rs * 0.1, y: ry - rs * 1.25), control: CGPoint(x: rx + rs * 0.15, y: ry - rs * 1.28))
        blade.addQuadCurve(to: CGPoint(x: rx + rs * 0.42, y: ry - rs * 0.92), control: CGPoint(x: rx + rs * 0.1, y: ry - rs * 1.05))
        blade.closeSubpath()
        c.addPath(blade)
        c.fillPath()

        fogBand(c, size, y: groundY + h * 0.02, thickness: h * 0.07, alpha: 0.2)
        fogBand(c, size, y: h * 0.9, thickness: h * 0.09, alpha: 0.12)
    }

    // MARK: THEME 4 — Rose Window (stained glass)

    static func drawRoseWindow(_ c: CGContext, _ size: CGSize, _ rng: () -> Double) {
        let w = size.width, h = size.height
        c.setFillColor(cg(0.015, 0.005, 0.014, 1))
        c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let cx = w / 2
        let cy = h * 0.36
        let R = w * 0.44
        glow(c, size, center: CGPoint(x: cx, y: cy), radius: R * 1.6, color: (0.7, 0.06, 0.16), strength: 0.3)

        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.72, 0.05, 0.16),   // deep crimson
            (0.4, 0.03, 0.13),    // blood
            (0.22, 0.04, 0.28),   // violet
            (0.05, 0.02, 0.06),   // near night
            (0.82, 0.62, 0.42),   // candle gold
            (0.55, 0.08, 0.2)     // ember rose
        ]
        let rings: [(r0: CGFloat, r1: CGFloat, segs: Int)] = [
            (0.16, 0.4, 8), (0.4, 0.62, 16), (0.62, 0.82, 24), (0.82, 1.0, 32)
        ]
        for ring in rings {
            for s in 0..<ring.segs {
                let a0 = CGFloat(s) / CGFloat(ring.segs) * 2 * .pi
                let a1 = CGFloat(s + 1) / CGFloat(ring.segs) * 2 * .pi
                let col = palette[Int(rng() * Double(palette.count))]
                let bright = CGFloat(0.65 + rng() * 0.55)
                c.setFillColor(cg(col.0 * bright, col.1 * bright, col.2 * bright, 0.96))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: cx + cos(a0) * R * ring.r0, y: cy + sin(a0) * R * ring.r0))
                path.addLine(to: CGPoint(x: cx + cos(a0) * R * ring.r1, y: cy + sin(a0) * R * ring.r1))
                path.addArc(center: CGPoint(x: cx, y: cy), radius: R * ring.r1, startAngle: a0, endAngle: a1, clockwise: false)
                path.addLine(to: CGPoint(x: cx + cos(a1) * R * ring.r0, y: cy + sin(a1) * R * ring.r0))
                path.addArc(center: CGPoint(x: cx, y: cy), radius: R * ring.r0, startAngle: a1, endAngle: a0, clockwise: true)
                path.closeSubpath()
                c.addPath(path)
                c.fillPath()
            }
        }
        // lead lines
        c.setStrokeColor(cg(0.01, 0.002, 0.008, 1))
        c.setLineWidth(w * 0.014)
        for ring in rings {
            c.strokeEllipse(in: CGRect(x: cx - R * ring.r0, y: cy - R * ring.r0, width: R * ring.r0 * 2, height: R * ring.r0 * 2))
            for s in 0..<ring.segs {
                let a = CGFloat(s) / CGFloat(ring.segs) * 2 * .pi
                c.move(to: CGPoint(x: cx + cos(a) * R * ring.r0, y: cy + sin(a) * R * ring.r0))
                c.addLine(to: CGPoint(x: cx + cos(a) * R * ring.r1, y: cy + sin(a) * R * ring.r1))
                c.strokePath()
            }
        }
        // center rosette
        glow(c, size, center: CGPoint(x: cx, y: cy), radius: R * 0.2, color: (1.0, 0.4, 0.3), strength: 0.5)
        c.setFillColor(cg(0.85, 0.2, 0.18, 1))
        c.fillEllipse(in: CGRect(x: cx - R * 0.09, y: cy - R * 0.09, width: R * 0.18, height: R * 0.18))
        c.setStrokeColor(cg(0.01, 0.002, 0.008, 1))
        c.setLineWidth(w * 0.016)
        c.strokeEllipse(in: CGRect(x: cx - R * 0.09, y: cy - R * 0.09, width: R * 0.18, height: R * 0.18))
        // outer tracery rays into the dark
        c.setStrokeColor(cg(0.05, 0.015, 0.03, 1))
        c.setLineWidth(w * 0.01)
        for i in 0..<16 {
            let a = CGFloat(i) / 16 * 2 * .pi + .pi / 16
            c.move(to: CGPoint(x: cx + cos(a) * R, y: cy + sin(a) * R))
            c.addLine(to: CGPoint(x: cx + cos(a) * R * 1.5, y: cy + sin(a) * R * 1.5))
            c.strokePath()
        }
        fogBand(c, size, y: h * 0.9, thickness: h * 0.12, alpha: 0.08)
    }

    // MARK: THEME 5 — Ashen Forest

    static func drawAshenForest(_ c: CGContext, _ size: CGSize, _ rng: () -> Double) {
        let w = size.width, h = size.height
        sky(c, size, (0.05, 0.03, 0.05), (0.12, 0.07, 0.09))
        glow(c, size, center: CGPoint(x: w * 0.5, y: h * 0.42), radius: w * 0.8, color: (0.7, 0.35, 0.4), strength: 0.2)
        glow(c, size, center: CGPoint(x: w * (0.3 + rng() * 0.4), y: h * 0.25), radius: w * 0.22, color: (0.85, 0.7, 0.65), strength: 0.35)

        // three depth rows of bare trees
        let rows: [(base: CGFloat, count: Int, len: CGFloat, width: CGFloat, color: CGColor)] = [
            (h * 0.62, 7, h * 0.06, w * 0.012, cg(0.1, 0.06, 0.08, 0.9)),
            (h * 0.78, 5, h * 0.09, w * 0.018, cg(0.045, 0.02, 0.035, 0.96)),
            (h * 0.98, 4, h * 0.13, w * 0.026, cg(0.012, 0.004, 0.012, 1))
        ]
        for (i, row) in rows.enumerated() {
            for _ in 0..<row.count {
                let tx = rng() * w * 1.1 - w * 0.05
                let lean = (rng() - 0.5) * 0.16
                branch(c, CGPoint(x: tx, y: row.base), lean, row.len, row.width, 7, row.color, rng)
            }
            if i < rows.count - 1 {
                fogBand(c, size, y: row.base + h * 0.02, thickness: h * 0.05, alpha: 0.18)
            }
        }
        // ground mist
        c.setFillColor(cg(0.02, 0.008, 0.014, 1))
        c.fill(CGRect(x: 0, y: h * 0.96, width: w, height: h * 0.04))
        fogBand(c, size, y: h * 0.93, thickness: h * 0.08, alpha: 0.2)
    }
}

// MARK: - Shrine state

@MainActor
final class ShrineState: ObservableObject {
    @Published var theme: Int = 0
    @Published var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    @Published var deviceIndex: Int = 0
    @Published var rendering = false
    @Published var status = ""
    @Published var vault: [ShroudDesign] = []
    @Published var sharingImage: UIImage? = nil

    @Published var deliveryOn = false
    @Published var deliveryHour = 21
    @Published var deliveryMinute = 0

    private let vaultKey = "shroud_vault"
    private let deliveryKey = "shroud_delivery"
    private let hourKey = "shroud_hour"
    private let minuteKey = "shroud_minute"

    init() {
        if let data = UserDefaults.standard.data(forKey: vaultKey),
           let saved = try? JSONDecoder().decode([ShroudDesign].self, from: data) {
            vault = saved
        }
        deliveryOn = UserDefaults.standard.bool(forKey: deliveryKey)
        let h = UserDefaults.standard.integer(forKey: hourKey)
        let m = UserDefaults.standard.integer(forKey: minuteKey)
        deliveryHour = h == 0 ? 21 : h
        deliveryMinute = m
        if deliveryOn { scheduleDelivery() }
    }

    var design: ShroudDesign {
        ShroudDesign(id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012X", seed & 0xFFFFFFFFFFFF))") ?? UUID(), theme: theme, seed: seed, created: Date())
    }

    func conjure() {
        seed = UInt64.random(in: 1...UInt64.max)
        status = "A new shroud has been woven. Seed \(seed % 100000)."
    }

    func currentImage(_ size: CGSize) -> UIImage {
        ShroudForge.render(theme: theme, seed: seed, size: size)
    }

    func renderAndSave() {
        rendering = true
        status = "Weaving at \(Int(ShroudForge.devices[deviceIndex].1.width))×\(Int(ShroudForge.devices[deviceIndex].1.height))…"
        let t = theme, s = seed
        let size = ShroudForge.devices[deviceIndex].1
        Task.detached(priority: .userInitiated) {
            let img = ShroudForge.render(theme: t, seed: s, size: size)
            await MainActor.run {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                self.rendering = false
                self.status = "Saved to Photos — Settings ▸ Wallpaper ▸ Add New Wallpaper to set it."
            }
        }
    }

    func shareCurrent() {
        rendering = true
        let t = theme, s = seed
        let size = ShroudForge.devices[deviceIndex].1
        Task.detached(priority: .userInitiated) {
            let img = ShroudForge.render(theme: t, seed: s, size: size)
            await MainActor.run {
                self.rendering = false
                self.sharingImage = img
            }
        }
    }

    func keepToVault() {
        let d = ShroudDesign(id: UUID(), theme: theme, seed: seed, created: Date())
        vault.insert(d, at: 0)
        if vault.count > 30 { vault.removeLast() }
        persistVault()
        status = "Kept in the vault — \(vault.count) shrouds preserved."
    }

    func deleteFromVault(_ d: ShroudDesign) {
        vault.removeAll { $0.id == d.id }
        persistVault()
    }

    func restore(_ d: ShroudDesign) {
        theme = d.theme
        seed = d.seed
        status = "Restored \(d.themeName) from the vault."
    }

    private func persistVault() {
        if let data = try? JSONEncoder().encode(vault) {
            UserDefaults.standard.set(data, forKey: vaultKey)
        }
    }

    // MARK: nightly delivery

    func setDelivery(_ on: Bool) {
        if on {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        self.deliveryOn = true
                        UserDefaults.standard.set(true, forKey: self.deliveryKey)
                        self.scheduleDelivery()
                        self.status = "Nightly delivery sealed — a fresh shroud every \(String(format: "%02d:%02d", self.deliveryHour, self.deliveryMinute))."
                    } else {
                        self.deliveryOn = false
                        self.status = "Notifications denied — enable them in Settings to receive the nightly shroud."
                    }
                }
            }
        } else {
            deliveryOn = false
            UserDefaults.standard.set(false, forKey: deliveryKey)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["shroud-nightly"])
            status = "Nightly delivery lifted."
        }
    }

    func deliveryTimeChanged() {
        UserDefaults.standard.set(deliveryHour, forKey: hourKey)
        UserDefaults.standard.set(deliveryMinute, forKey: minuteKey)
        if deliveryOn {
            scheduleDelivery()
            status = "Delivery resealed for \(String(format: "%02d:%02d", deliveryHour, deliveryMinute))."
        }
    }

    private func scheduleDelivery() {
        let content = UNMutableNotificationContent()
        content.title = "THE SHROUD STIRS"
        content.body = "A fresh gothic wallpaper has been woven for you. Open Shroud to claim it."
        content.sound = .default
        var comps = DateComponents()
        comps.hour = deliveryHour
        comps.minute = deliveryMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "shroud-nightly", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - Shared gothic components

struct SCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
            content()
        }
        .padding(13)
        .background(Color(red: 0.06, green: 0.01, blue: 0.03))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.35), lineWidth: 1))
    }
}

struct SButton: View {
    let title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: 11, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(enabled ? (filled ? crimson : bloodDim) : Color(red: 0.2, green: 0.03, blue: 0.07))
            .foregroundColor(enabled ? .white : ashDim)
            .cornerRadius(7)
        }
        .disabled(!enabled)
    }
}

// MARK: - Root

@main
struct ShroudApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var shrine = ShrineState()

    var body: some View {
        TabView {
            ShrineView(shrine: shrine)
                .tabItem { Label("SHRINE", systemImage: "moon.stars.fill") }
            VaultView(shrine: shrine)
                .tabItem { Label("VAULT", systemImage: "archivebox.fill") }
            DeliveryView(shrine: shrine)
                .tabItem { Label("DELIVERY", systemImage: "bell.badge.fill") }
        }
        .accentColor(crimson)
    }
}

// MARK: - SHRINE tab

struct ShrineView: View {
    @ObservedObject var shrine: ShrineState
    @State private var previewImage: UIImage? = nil

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // phone preview with lock-screen composition
                    SCard(title: "01 // THE PREVIEW") {
                        VStack(spacing: 8) {
                            ZStack(alignment: .top) {
                                if let img = previewImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 150, height: 325)
                                        .clipped()
                                } else {
                                    Rectangle()
                                        .fill(Color(red: 0.09, green: 0.02, blue: 0.05))
                                        .frame(width: 150, height: 325)
                                }
                                VStack(spacing: 2) {
                                    Text("21:47")
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.95))
                                    Text("Saturday, November 22")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                                .padding(.top, 34)
                            }
                            .frame(width: 150, height: 325)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(crimson.opacity(0.6), lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            Text("\(ShroudForge.devices[shrine.deviceIndex].0) · \(Int(ShroudForge.devices[shrine.deviceIndex].1.width))×\(Int(ShroudForge.devices[shrine.deviceIndex].1.height))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(ashDim)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    SCard(title: "02 // CHOOSE THE RITE") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(0..<ShroudForge.themeNames.count, id: \.self) { i in
                                Button {
                                    shrine.theme = i
                                } label: {
                                    Text(ShroudForge.themeNames[i])
                                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 9)
                                        .padding(.horizontal, 4)
                                        .frame(maxWidth: .infinity)
                                        .background(shrine.theme == i ? crimson : Color(red: 0.14, green: 0.02, blue: 0.06))
                                        .foregroundColor(shrine.theme == i ? .white : ashDim)
                                        .cornerRadius(7)
                                }
                            }
                        }
                        Menu {
                            ForEach(0..<ShroudForge.devices.count, id: \.self) { i in
                                Button(ShroudForge.devices[i].0) { shrine.deviceIndex = i }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "iphone")
                                Text("FOR \(ShroudForge.devices[shrine.deviceIndex].0)")
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                Spacer()
                                Image(systemName: "chevron.down")
                            }
                            .foregroundColor(ashText)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color(red: 0.1, green: 0.015, blue: 0.04))
                            .cornerRadius(7)
                        }
                    }

                    HStack(spacing: 8) {
                        SButton(title: "CONJURE", systemImage: "dice.fill") { shrine.conjure() }
                        SButton(title: "KEEP", systemImage: "heart.fill", filled: true) { shrine.keepToVault() }
                    }
                    SButton(title: shrine.rendering ? "WEAVING…" : "SAVE TO PHOTOS", systemImage: "photo.badge.arrow.down.fill", enabled: !shrine.rendering, filled: true) {
                        shrine.renderAndSave()
                    }
                    SButton(title: "SHARE", systemImage: "square.and.arrow.up", enabled: !shrine.rendering) {
                        shrine.shareCurrent()
                    }

                    SCard(title: "STATUS") {
                        Text(shrine.status.isEmpty ? "Pick a rite, conjure until it haunts you, then save to Photos and set it as your wallpaper." : shrine.status)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ashText)
                    }
                }
                .padding(14)
            }
            .sheet(item: $shrine.sharingImage) { img in
                ShareSheet(items: [img])
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE SHRINE")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
        .onAppear { refreshPreview() }
        .onChange(of: shrine.theme) { _ in refreshPreview() }
        .onChange(of: shrine.seed) { _ in refreshPreview() }
        .onChange(of: shrine.deviceIndex) { _ in refreshPreview() }
    }

    private func refreshPreview() {
        let t = shrine.theme, s = shrine.seed
        let size = CGSize(width: 300, height: 650)
        Task.detached(priority: .userInitiated) {
            let img = ShroudForge.render(theme: t, seed: s, size: size)
            await MainActor.run {
                if t == shrine.theme && s == shrine.seed {
                    previewImage = img
                }
            }
        }
    }
}

extension UIImage: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

// MARK: - VAULT tab

struct VaultView: View {
    @ObservedObject var shrine: ShrineState

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            if shrine.vault.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 36))
                        .foregroundColor(bloodDim)
                    Text("The vault is empty.\nKEEP a shroud you love from the SHRINE.")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(ashDim)
                        .multilineTextAlignment(.center)
                }
            } else {
                List {
                    ForEach(shrine.vault) { d in
                        VaultRow(design: d) {
                            shrine.restore(d)
                        } onSave: {
                            let t = d.theme, s = d.seed
                            let size = ShroudForge.devices[shrine.deviceIndex].1
                            Task.detached(priority: .userInitiated) {
                                let img = ShroudForge.render(theme: t, seed: s, size: size)
                                await MainActor.run {
                                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                                    shrine.status = "\(d.themeName) saved to Photos."
                                }
                            }
                        } onDelete: {
                            shrine.deleteFromVault(d)
                        }
                        .listRowBackground(Color(red: 0.06, green: 0.01, blue: 0.03))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE VAULT")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
    }
}

struct VaultRow: View {
    let design: ShroudDesign
    let onRestore: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    @State private var thumb: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let t = thumb {
                    Image(uiImage: t)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 112)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(red: 0.14, green: 0.03, blue: 0.06))
                        .frame(width: 56, height: 112)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(design.themeName)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(ashText)
                Text("seed \(design.seed % 100000) · \(design.created.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ashDim)
                Text("Restoring loads it into the SHRINE for re-weaving at full size.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(ashDim.opacity(0.7))
            }
            Spacer()
            VStack(spacing: 10) {
                Button(action: onRestore) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(crimson)
                }
                Button(action: onSave) {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(crimson)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(ashDim)
                }
            }
        }
        .onAppear {
            let t = design.theme, s = design.seed
            Task.detached(priority: .utility) {
                let img = ShroudForge.render(theme: t, seed: s, size: CGSize(width: 112, height: 224))
                await MainActor.run { thumb = img }
            }
        }
    }
}

// MARK: - DELIVERY tab

struct DeliveryView: View {
    @ObservedObject var shrine: ShrineState

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SCard(title: "01 // NIGHTLY DELIVERY") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: Binding(
                                get: { shrine.deliveryOn },
                                set: { shrine.setDelivery($0) }
                            )) {
                                Text("SEND ME A SHROUD EVERY NIGHT")
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                    .foregroundColor(ashText)
                            }
                            .tint(crimson)
                            if shrine.deliveryOn {
                                DatePicker("DELIVERY HOUR", selection: Binding(
                                    get: {
                                        var comps = DateComponents()
                                        comps.hour = shrine.deliveryHour
                                        comps.minute = shrine.deliveryMinute
                                        return Calendar.current.date(from: comps) ?? Date()
                                    },
                                    set: { d in
                                        let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
                                        shrine.deliveryHour = comps.hour ?? 21
                                        shrine.deliveryMinute = comps.minute ?? 0
                                        shrine.deliveryTimeChanged()
                                    }
                                ), displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .tint(crimson)
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .colorMultiply(ashText)
                            }
                        }
                    }

                    SCard(title: "02 // HOW IT LANDS") {
                        VStack(alignment: .leading, spacing: 8) {
                            step("At your chosen hour, a notification knocks: THE SHROUD STIRS.")
                            step("Open Shroud — a brand-new wallpaper has already been conjured.")
                            step("Conjure again until it haunts you, then SAVE TO PHOTOS.")
                            step("Settings ▸ Wallpaper ▸ Add New Wallpaper ▸ choose the shroud.")
                        }
                    }

                    SCard(title: "STATUS") {
                        Text(shrine.status.isEmpty ? "The shroud is patient. Seal the delivery above." : shrine.status)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ashText)
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE DELIVERY")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
    }

    private func step(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(crimson)
                .frame(width: 6, height: 6)
                .padding(.top, 4)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ashDim)
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
