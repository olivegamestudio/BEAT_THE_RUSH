import SwiftUI

/// A drifting cumulus cloud centred at screen point `c`; `s` scales its size.
/// Bumpy top, flatter base, built as one path so the fill is even (no muddy overlaps).
func drawCloud(_ ctx: GraphicsContext, at c: CGPoint, s: CGFloat) {
    var cloud = Path()
    for (dx, dy, r): (CGFloat, CGFloat, CGFloat) in
        [(-58, 8, 20), (-32, -2, 28), (-2, -14, 34), (28, -4, 30), (56, 8, 22),
         (-34, 16, 18), (2, 19, 23), (38, 16, 18)] {
        cloud.addEllipse(in: CGRect(x: c.x + dx * s - r * s, y: c.y + dy * s - r * s,
                                    width: r * 2 * s, height: r * 2 * s))
    }
    ctx.drawLayer { l in
        l.addFilter(.blur(radius: 3 * s))
        l.fill(cloud, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.5), .white.opacity(0.26)]),
            startPoint: CGPoint(x: c.x, y: c.y - 34 * s),
            endPoint: CGPoint(x: c.x, y: c.y + 28 * s)))
    }
}

/// A two-aspect running signal standing at screen point `p` (its foot on the track):
/// a post and head with a red lamp over a green, the active one lit and glowing.
func drawSignal(_ ctx: GraphicsContext, at p: CGPoint, red: Bool, scale: CGFloat) {
    let postH = 13 * scale
    // post + base
    var post = Path()
    post.move(to: p); post.addLine(to: CGPoint(x: p.x, y: p.y - postH))
    ctx.stroke(post, with: .color(Color(white: 0.34)), style: .init(lineWidth: 2.4 * scale, lineCap: .round))
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.4 * scale, y: p.y - 2 * scale,
                                    width: 4.8 * scale, height: 4 * scale)), with: .color(Color(white: 0.3)))
    // head
    let hw = 9 * scale, hh = 17 * scale
    let head = CGRect(x: p.x - hw / 2, y: p.y - postH - hh, width: hw, height: hh)
    ctx.fill(Path(roundedRect: head, cornerRadius: 3.5 * scale), with: .color(Color(white: 0.13)))
    ctx.stroke(Path(roundedRect: head, cornerRadius: 3.5 * scale),
               with: .color(.black.opacity(0.5)), style: .init(lineWidth: 1 * scale))
    let r = 2.9 * scale
    let redC = CGPoint(x: head.midX, y: head.minY + hh * 0.29)
    let grnC = CGPoint(x: head.midX, y: head.minY + hh * 0.71)
    let redCol = red ? Color(red: 1.0, green: 0.24, blue: 0.24) : Color(red: 0.26, green: 0.06, blue: 0.06)
    let grnCol = red ? Color(red: 0.06, green: 0.22, blue: 0.10) : Color(red: 0.30, green: 0.95, blue: 0.44)
    let lit = red ? redC : grnC
    let litCol = red ? redCol : grnCol
    // a soft, blurred halo around the lit lamp so it reads as glowing
    ctx.drawLayer { g in
        g.addFilter(.blur(radius: r * 1.6))
        g.fill(Path(ellipseIn: CGRect(x: lit.x - r * 2.6, y: lit.y - r * 2.6, width: r * 5.2, height: r * 5.2)),
               with: .color(litCol.opacity(0.85)))
    }
    ctx.fill(Path(ellipseIn: CGRect(x: redC.x - r, y: redC.y - r, width: r * 2, height: r * 2)), with: .color(redCol))
    ctx.fill(Path(ellipseIn: CGRect(x: grnC.x - r, y: grnC.y - r, width: r * 2, height: r * 2)), with: .color(grnCol))
    // a bright core on the lit lamp
    ctx.fill(Path(ellipseIn: CGRect(x: lit.x - r * 0.45, y: lit.y - r * 0.45, width: r * 0.9, height: r * 0.9)),
             with: .color(.white.opacity(0.75)))
}

/// A gold sparkle burst at screen point `p`, expanding and fading over its life (`age`/`life`).
func drawSparkleBurst(_ ctx: GraphicsContext, at p: CGPoint, age: Double, life: Double, scale: CGFloat) {
    let prog = min(age / life, 1)
    let alpha = 1 - prog
    let gold = Color(red: 1.0, green: 0.9, blue: 0.5)
    let flash = (5 - prog * 4) * scale
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - flash, y: p.y - flash, width: flash * 2, height: flash * 2)),
             with: .color(.white.opacity(alpha * 0.8)))
    for k in 0..<7 {
        let a = Double(k) / 7 * 2 * .pi + age * 3
        let r = (6 + prog * 26) * scale
        let sp = CGPoint(x: p.x + CGFloat(cos(a)) * r, y: p.y + CGFloat(sin(a)) * r)
        let sz = (2.6 - prog * 2) * scale
        if sz > 0 {
            ctx.fill(Path(ellipseIn: CGRect(x: sp.x - sz, y: sp.y - sz, width: sz * 2, height: sz * 2)),
                     with: .color(gold.opacity(alpha)))
        }
    }
}

/// A little speech bubble with `emoji`, its tail pointing down at the crowd at screen point `p`.
func drawMood(_ ctx: GraphicsContext, _ emoji: String, at p: CGPoint, scale: CGFloat) {
    let w = 32 * scale, h = 27 * scale
    let rect = CGRect(x: p.x - w / 2, y: p.y - h, width: w, height: h)
    ctx.drawLayer { l in
        l.addFilter(.shadow(color: .black.opacity(0.4), radius: 3 * scale, x: 0, y: 2 * scale))
        l.fill(Path(roundedRect: rect, cornerRadius: 8 * scale), with: .color(.white.opacity(0.94)))
        var tail = Path()
        tail.move(to: CGPoint(x: p.x - 5 * scale, y: rect.maxY - 1))
        tail.addLine(to: CGPoint(x: p.x + 1 * scale, y: rect.maxY + 6 * scale))
        tail.addLine(to: CGPoint(x: p.x + 6 * scale, y: rect.maxY - 1))
        tail.closeSubpath()
        l.fill(tail, with: .color(.white.opacity(0.94)))
    }
    ctx.draw(Text(emoji).font(.system(size: 17 * scale)), at: CGPoint(x: rect.midX, y: rect.midY - 1))
}

/// Draws one carriage centred at screen point `p`, rotated to `angle`, in `tint`.
/// Shared by the station board and the animated menu. `cw`/`ch` are design-space
/// dimensions; `scale` maps design units to screen.
func drawCarriage(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat,
                  tint: Color, cw: CGFloat, ch: CGFloat, scale: CGFloat) {
    let glass = Color(red: 0.66, green: 0.84, blue: 0.96)
    // Align to the track line but keep the carriage upright — never let it flip over when
    // it's travelling to the left (a carriage looks the same either way along its length).
    var a = angle
    if cos(a) < 0 { a += .pi }
    ctx.drawLayer { l in
        l.addFilter(.shadow(color: .black.opacity(0.45), radius: 4 * scale, x: 0, y: 4 * scale))
        l.translateBy(x: p.x, y: p.y)
        l.rotate(by: .radians(a))
        let r = CGRect(x: -cw / 2 * scale, y: -ch / 2 * scale, width: cw * scale, height: ch * scale)
        let corner = ch * 0.22 * scale
        let shape = Path(roundedRect: r, cornerRadius: corner)
        // A side face carries the windows and doors — the roof is the lit top.
        let depth = ch * 0.44 * scale
        let sideShape = Path(roundedRect: r.offsetBy(dx: 0, dy: depth), cornerRadius: corner)
        l.fill(sideShape, with: .color(tint))
        l.fill(sideShape, with: .color(.black.opacity(0.30)))
        let bandTop = r.maxY
        let winW = cw * 0.15 * scale, winH = depth * 0.48
        let winY = bandTop + depth * 0.44
        for k in [-1.0, 0.0, 1.0] {
            let wx = CGFloat(k) * cw * 0.24 * scale
            l.fill(Path(roundedRect: CGRect(x: wx - winW / 2, y: winY - winH / 2,
                                            width: winW, height: winH), cornerRadius: 2 * scale),
                   with: .color(glass))
        }
        let doorW = cw * 0.08 * scale, doorH = depth * 0.82
        for dx in [-cw * 0.40, cw * 0.40] {
            l.fill(Path(roundedRect: CGRect(x: dx * scale - doorW / 2,
                                            y: bandTop + depth * 0.5 - doorH / 2,
                                            width: doorW, height: doorH), cornerRadius: 1.5 * scale),
                   with: .color(.black.opacity(0.38)))
        }
        // roof (top face), lit from the top-left
        l.fill(shape, with: .color(tint))
        l.fill(shape, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.16)]),
            startPoint: CGPoint(x: r.minX, y: r.minY),
            endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        l.stroke(shape, with: .color(.black.opacity(0.22)), style: .init(lineWidth: 1.2 * scale))
    }
}
