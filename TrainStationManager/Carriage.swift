import SwiftUI

/// Draws one carriage centred at screen point `p`, rotated to `angle`, in `tint`.
/// Shared by the station board and the animated menu. `cw`/`ch` are design-space
/// dimensions; `scale` maps design units to screen.
func drawCarriage(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat,
                  tint: Color, cw: CGFloat, ch: CGFloat, scale: CGFloat) {
    let glass = Color(red: 0.66, green: 0.84, blue: 0.96)
    ctx.drawLayer { l in
        l.addFilter(.shadow(color: .black.opacity(0.45), radius: 4 * scale, x: 0, y: 4 * scale))
        l.translateBy(x: p.x, y: p.y)
        l.rotate(by: .radians(angle))
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
