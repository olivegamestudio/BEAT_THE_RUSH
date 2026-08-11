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

/// A three-aspect block signal: 0 = green, 1 = amber (caution), 2 = red. Three lamps stacked in the head.
func drawBlockSignal(_ ctx: GraphicsContext, at p: CGPoint, aspect: Int, scale: CGFloat) {
    let postH = 13 * scale
    var post = Path()
    post.move(to: p); post.addLine(to: CGPoint(x: p.x, y: p.y - postH))
    ctx.stroke(post, with: .color(Color(white: 0.34)), style: .init(lineWidth: 2.4 * scale, lineCap: .round))
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.4 * scale, y: p.y - 2 * scale,
                                    width: 4.8 * scale, height: 4 * scale)), with: .color(Color(white: 0.3)))
    let hw = 9 * scale, hh = 23 * scale
    let head = CGRect(x: p.x - hw / 2, y: p.y - postH - hh, width: hw, height: hh)
    ctx.fill(Path(roundedRect: head, cornerRadius: 3.5 * scale), with: .color(Color(white: 0.13)))
    ctx.stroke(Path(roundedRect: head, cornerRadius: 3.5 * scale),
               with: .color(.black.opacity(0.5)), style: .init(lineWidth: 1 * scale))
    let r = 2.7 * scale
    let centers = [CGPoint(x: head.midX, y: head.minY + hh * 0.22),   // 0: red (top)
                   CGPoint(x: head.midX, y: head.minY + hh * 0.50),   // 1: amber (middle)
                   CGPoint(x: head.midX, y: head.minY + hh * 0.78)]   // 2: green (bottom)
    let on: [Color] = [Color(red: 1.0, green: 0.24, blue: 0.24), Color(red: 1.0, green: 0.74, blue: 0.14),
                       Color(red: 0.30, green: 0.95, blue: 0.44)]
    let off: [Color] = [Color(red: 0.26, green: 0.06, blue: 0.06), Color(red: 0.28, green: 0.20, blue: 0.03),
                        Color(red: 0.06, green: 0.22, blue: 0.10)]
    let litLamp = aspect == 2 ? 0 : (aspect == 1 ? 1 : 2)   // red→top, amber→middle, green→bottom
    ctx.drawLayer { g in
        g.addFilter(.blur(radius: r * 1.6))
        g.fill(Path(ellipseIn: CGRect(x: centers[litLamp].x - r * 2.6, y: centers[litLamp].y - r * 2.6,
                                      width: r * 5.2, height: r * 5.2)), with: .color(on[litLamp].opacity(0.85)))
    }
    for i in 0..<3 {
        ctx.fill(Path(ellipseIn: CGRect(x: centers[i].x - r, y: centers[i].y - r, width: r * 2, height: r * 2)),
                 with: .color(i == litLamp ? on[i] : off[i]))
    }
    ctx.fill(Path(ellipseIn: CGRect(x: centers[litLamp].x - r * 0.45, y: centers[litLamp].y - r * 0.45,
                                    width: r * 0.9, height: r * 0.9)), with: .color(.white.opacity(0.75)))
}

/// A gold sparkle burst at screen point `p`, expanding and fading over its life (`age`/`life`).
func drawSparkleBurst(_ ctx: GraphicsContext, at p: CGPoint, age: Double, life: Double, scale: CGFloat,
                      toward: CGPoint? = nil) {
    let prog = min(age / life, 1)
    let gold = Color(red: 1.0, green: 0.88, blue: 0.46)
    // A boarded passenger flies to the people counter (bottom-left), so the score visibly ticks up.
    guard let target = toward else {
        let alpha = 1 - prog
        let flash = (5 - prog * 4) * scale
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - flash, y: p.y - flash, width: flash * 2, height: flash * 2)),
                 with: .color(.white.opacity(alpha * 0.8)))
        return
    }
    let ease = 1 - pow(1 - prog, 3.2)                      // ease-out — zips off the train, settling into the count
    let pos = CGPoint(x: p.x + (target.x - p.x) * ease, y: p.y + (target.y - p.y) * ease)
    let alpha = prog < 0.85 ? 1.0 : (1 - (prog - 0.85) / 0.15)   // fade only as it lands
    ctx.drawLayer { g in
        g.addFilter(.blur(radius: 3 * scale))
        g.fill(Path(ellipseIn: CGRect(x: pos.x - 5 * scale, y: pos.y - 5 * scale, width: 10 * scale, height: 10 * scale)),
               with: .color(gold.opacity(alpha * 0.6)))
    }
    let r = 5.5 * scale                                    // a little twinkle: four rays + a bright core
    for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
        var ray = Path(); ray.move(to: pos)
        ray.addLine(to: CGPoint(x: pos.x + CGFloat(dx) * r, y: pos.y + CGFloat(dy) * r))
        ctx.stroke(ray, with: .color(gold.opacity(alpha)), style: .init(lineWidth: 1.7 * scale, lineCap: .round))
    }
    ctx.fill(Path(ellipseIn: CGRect(x: pos.x - 2 * scale, y: pos.y - 2 * scale, width: 4 * scale, height: 4 * scale)),
             with: .color(.white.opacity(alpha)))
}

/// A little steam locomotive centred at screen point `p`. `angle` is the track tangent in the
/// direction of travel; the engine is drawn upright with its smokebox facing the way it's going,
/// so it leads the rake either way along the line. GWR-ish: a Brunswick-green boiler with brass
/// bands, a chimney and dome, a cab, and three driving wheels.
func drawSteamLoco(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat,
                   cw: CGFloat, ch: CGFloat, scale: CGFloat, phase: CGFloat = 0) {
    let forward: CGFloat = cos(angle) >= 0 ? 1 : -1     // which way the smokebox points on screen
    var a = angle
    if cos(a) < 0 { a += .pi }                          // keep the engine upright like the carriages
    let green = Color(red: 0.09, green: 0.24, blue: 0.16)
    let dark  = Color(red: 0.09, green: 0.10, blue: 0.11)   // smokebox + chimney (black even on a green loco)
    let brass = Color(red: 0.82, green: 0.64, blue: 0.26)
    let frame = Color(red: 0.46, green: 0.12, blue: 0.11)   // red frames / footplate
    let wheelC = Color(red: 0.14, green: 0.15, blue: 0.17)
    ctx.drawLayer { l in
        l.addFilter(.shadow(color: .black.opacity(0.45), radius: 4 * scale, x: 0, y: 4 * scale))
        l.translateBy(x: p.x, y: p.y)
        l.rotate(by: .radians(a))
        l.scaleBy(x: forward, y: 1)                     // mirror so the smokebox leads the way it travels
        let W = cw * scale, H = ch * scale
        let depth = 0.44 * H                            // the same extrusion the carriages use, for matching volume
        func R(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: x0 * W, y: y0 * H, width: (x1 - x0) * W, height: (y1 - y0) * H)
        }
        // An extruded block: a darker side wall dropped by `depth`, then a lit top face — exactly the
        // roof-over-side treatment the carriages get, so the engine reads with the same 3-D solidity.
        func block(_ r: CGRect, _ corner: CGFloat, _ top: Color) {
            let side = Path(roundedRect: r.offsetBy(dx: 0, dy: depth), cornerRadius: corner)
            l.fill(side, with: .color(top)); l.fill(side, with: .color(.black.opacity(0.30)))
            let face = Path(roundedRect: r, cornerRadius: corner)
            l.fill(face, with: .color(top))
            l.fill(face, with: .linearGradient(Gradient(colors: [.white.opacity(0.42), .clear, .black.opacity(0.16)]),
                                               startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
            l.stroke(face, with: .color(.black.opacity(0.22)), style: .init(lineWidth: 1.1 * scale))
        }
        // driving wheels, sitting below the frames so they and their coupling rod are fully in view
        let wr = 0.19 * H
        let wheelXs: [CGFloat] = [-0.30, -0.02, 0.26]
        let wheelY = 0.26 * H + depth
        for wx in wheelXs {
            let c = CGPoint(x: wx * W, y: wheelY)
            l.fill(Path(ellipseIn: CGRect(x: c.x - wr, y: c.y - wr, width: wr * 2, height: wr * 2)), with: .color(wheelC))
            l.stroke(Path(ellipseIn: CGRect(x: c.x - wr, y: c.y - wr, width: wr * 2, height: wr * 2)),
                     with: .color(brass.opacity(0.8)), style: .init(lineWidth: 1.4 * scale))
            l.fill(Path(ellipseIn: CGRect(x: c.x - wr * 0.3, y: c.y - wr * 0.3, width: wr * 0.6, height: wr * 0.6)), with: .color(brass))
        }
        block(R(-0.50, 0.10, 0.48, 0.20), 2 * scale, frame)          // footplate / red frames
        block(R(-0.34, -0.20, 0.30, 0.18), 0.20 * H, green)          // boiler barrel
        block(R(0.24, -0.22, 0.46, 0.20), 0.20 * H, dark)            // smokebox at the front
        block(R(-0.54, -0.32, -0.22, 0.18), 3 * scale, green)       // cab (taller than the boiler)
        block(R(0.20, -0.50, 0.33, -0.20), 1.5 * scale, dark)        // chimney
        block(R(-0.07, -0.42, 0.11, -0.20), 4 * scale, brass)       // brass steam dome
        // details, painted onto the side wall (dropped by depth)
        let doorC = CGPoint(x: 0.35 * W, y: depth - 0.01 * H), dr = 0.15 * H
        l.fill(Path(ellipseIn: CGRect(x: doorC.x - dr, y: doorC.y - dr, width: dr * 2, height: dr * 2)),
               with: .color(Color(red: 0.16, green: 0.17, blue: 0.19)))
        l.stroke(Path(ellipseIn: CGRect(x: doorC.x - dr, y: doorC.y - dr, width: dr * 2, height: dr * 2)),
                 with: .color(brass.opacity(0.7)), style: .init(lineWidth: 1 * scale))
        for by: CGFloat in [-0.07, 0.07] {                           // brass boiler bands
            var band = Path()
            band.move(to: CGPoint(x: -0.32 * W, y: by * H + depth)); band.addLine(to: CGPoint(x: 0.24 * W, y: by * H + depth))
            l.stroke(band, with: .color(brass.opacity(0.85)), style: .init(lineWidth: 1.2 * scale))
        }
        l.fill(Path(roundedRect: CGRect(x: -0.48 * W, y: depth - 0.14 * H, width: 0.20 * W, height: 0.22 * H),
                    cornerRadius: 2 * scale), with: .color(Color(red: 0.55, green: 0.72, blue: 0.82)))   // cab window
        // Coupling rod: the crank pins on every driving wheel share one phase, so the steel side rod stays
        // level and orbits the wheel centres as the engine rolls — the reciprocating motion of a real loco.
        let rc = 0.52 * wr                                   // crank throw
        let crank = CGPoint(x: rc * cos(phase), y: rc * sin(phase))
        func pin(_ wx: CGFloat) -> CGPoint { CGPoint(x: wx * W + crank.x, y: wheelY + crank.y) }
        let steel = Color(red: 0.70, green: 0.73, blue: 0.78)
        var rod = Path(); rod.move(to: pin(wheelXs.first!)); rod.addLine(to: pin(wheelXs.last!))
        l.stroke(rod, with: .color(.black.opacity(0.5)), style: .init(lineWidth: 0.20 * H, lineCap: .round))
        l.stroke(rod, with: .color(steel), style: .init(lineWidth: 0.13 * H, lineCap: .round))
        for wx in wheelXs {                                   // bright crank-pin bosses
            let c = pin(wx), br = 0.07 * H
            l.fill(Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2)), with: .color(steel))
        }
    }
}

/// A plume of steam rising from a chimney at screen point `o`, drifting `back` (−1 / +1 in screen x,
/// opposite the way the engine travels) and thinning as it climbs. `t` drives the loop.
func drawSteamPlume(_ ctx: GraphicsContext, at o: CGPoint, back: CGFloat, t: Double, scale: CGFloat) {
    let n = 6
    for i in 0..<n {
        let p = CGFloat(((t * 1.2) + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1))
        let rise = p * 30 * scale                          // climbs a little
        let drift = p * 120 * scale * back                 // but mostly streams fast back over the train
        let wob = CGFloat(sin(t * 3 + Double(i) * 1.3)) * 3 * scale * p
        let r = (3.5 + p * 13) * scale
        let alpha = Double(1 - p) * 0.5
        let c = CGPoint(x: o.x + drift + wob, y: o.y - rise)
        ctx.drawLayer { g in
            g.addFilter(.blur(radius: 2.2 * scale + r * 0.25))
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(Color(white: 0.88 - Double(p) * 0.14).opacity(alpha)))
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
                  tint: Color, cw: CGFloat, ch: CGFloat, scale: CGFloat, endCap: Bool = false,
                  fill: Double = 0, seed: Int = 0, cornerRadius: CGFloat? = nil) {
    let glass = Color(red: 0.66, green: 0.84, blue: 0.96)
    let seated = Color(red: 0.20, green: 0.19, blue: 0.24)   // a passenger, seen as a silhouette through the glass
    // Align to the track line but keep the carriage upright — never let it flip over when
    // it's travelling to the left (a carriage looks the same either way along its length).
    var a = angle
    if cos(a) < 0 { a += .pi }
    ctx.drawLayer { l in
        l.addFilter(.shadow(color: .black.opacity(0.45), radius: 4 * scale, x: 0, y: 4 * scale))
        l.translateBy(x: p.x, y: p.y)
        l.rotate(by: .radians(a))
        let r = CGRect(x: -cw / 2 * scale, y: -ch / 2 * scale, width: cw * scale, height: ch * scale)
        // A power car at the nose/tail of an express is a smooth, rounded capsule with no passenger windows.
        // Heritage coaches pass a small `cornerRadius` so they read as squarer, more rectangular boxes.
        let corner = (cornerRadius ?? (endCap ? ch * 0.5 : ch * 0.22)) * scale
        let shape = Path(roundedRect: r, cornerRadius: corner)
        // A side face carries the windows and doors — the roof is the lit top.
        let depth = ch * 0.44 * scale
        let sideShape = Path(roundedRect: r.offsetBy(dx: 0, dy: depth), cornerRadius: corner)
        l.fill(sideShape, with: .color(tint))
        l.fill(sideShape, with: .color(.black.opacity(0.30)))
        let bandTop = r.maxY
        if endCap {
            // just a single cab windscreen, no passenger windows or doors
            let winW = cw * 0.16 * scale, winH = depth * 0.5
            l.fill(Path(roundedRect: CGRect(x: -winW / 2, y: bandTop + depth * 0.44 - winH / 2,
                                            width: winW, height: winH), cornerRadius: 2 * scale),
                   with: .color(glass.opacity(0.7)))
        } else {
            let winW = cw * 0.15 * scale, winH = depth * 0.48
            let winY = bandTop + depth * 0.44
            let f = min(1, max(0, fill))
            for (w, k) in [-1.0, 0.0, 1.0].enumerated() {
                let wx = CGFloat(k) * cw * 0.24 * scale
                l.fill(Path(roundedRect: CGRect(x: wx - winW / 2, y: winY - winH / 2,
                                                width: winW, height: winH), cornerRadius: 2 * scale),
                       with: .color(glass))
                // Each window has a stable pseudo-random threshold; it fills once the train is that full,
                // so seats populate scattered about (not front-to-back) but the fuller the train the more show.
                let h = Double(((seed &* 2654435761) &+ (w &* 40503)) & 0xFFFF) / 65535.0
                if f > h {                                               // a passenger silhouette in the window
                    let hd = winW * 0.52
                    l.fill(Path(roundedRect: CGRect(x: wx - winW * 0.40, y: winY + winH * 0.04,
                                                    width: winW * 0.80, height: winH * 0.52),
                                cornerRadius: winW * 0.24), with: .color(seated))            // shoulders
                    l.fill(Path(ellipseIn: CGRect(x: wx - hd / 2, y: winY - winH * 0.30, width: hd, height: hd)),
                           with: .color(seated))                                             // head
                }
            }
            let doorW = cw * 0.08 * scale, doorH = depth * 0.82
            for dx in [-cw * 0.40, cw * 0.40] {
                l.fill(Path(roundedRect: CGRect(x: dx * scale - doorW / 2,
                                                y: bandTop + depth * 0.5 - doorH / 2,
                                                width: doorW, height: doorH), cornerRadius: 1.5 * scale),
                       with: .color(.black.opacity(0.38)))
            }
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
