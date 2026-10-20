using BeatTheRush.Core;
using Microsoft.Xna.Framework;
using static BeatTheRush.Game.RenderMath;

namespace BeatTheRush.Game;

internal sealed class SceneryRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    public void DrawBackground(StationSimulation simulation, double animationTime)
    {
        var scenery = simulation.Definition.Scenery;
        // Flat map scenery, kept away from the operational foreground.
        for (var y = 120; y < 750; y += 12)
        {
            var left = scenery.RiverLeft + MathF.Sin(y * 0.016f) * 13;
            var right = scenery.RiverRight + MathF.Sin(y * 0.013f + 1) * 18;
            _paint.Fill(left - 10, y, right - left + 20, 12, new Color(49, 66, 53));
            _paint.Fill(left, y, right - left, 12, new Color(29, 66, 72));
        }
        for (var x = scenery.RiverLeft + 25; x < scenery.RiverRight - 20; x += 42)
            for (var y = 130; y < 750; y += 38)
            {
                var drift = (float)(animationTime * 5 % 26);
                _paint.Line(new(x, y + drift), new(x + 14, y + drift - 2), new Color(46, 84, 86), 1.3f);
            }

        DrawTown();
        for (var i = 0; i < 19; i++)
        {
            var x = 310 + (i * 149 % 1190);
            var y = i % 2 == 0 ? 220 + (i * 17 % 44) : 589 + (i * 11 % 40);
            if (x > scenery.RiverLeft - 30 && x < scenery.RiverRight + 40) continue;
            _paint.Circle(new(x, y), 13 + i % 5, new Color(24, 38, 31));
            _paint.Circle(new(x - 3, y - 3), 11 + i % 5, new Color(43, 64, 43));
            _paint.Circle(new(x - 6, y - 5), 6, new Color(52, 75, 47));
        }

        var bridgeWidth = scenery.BridgeRight - scenery.BridgeLeft;
        _paint.Fill(scenery.BridgeLeft - 8, scenery.BridgeY - 32, bridgeWidth + 16, 64, new Color(83, 87, 76));
        _paint.Fill(scenery.BridgeLeft - 4, scenery.BridgeY - 27, bridgeWidth + 8, 54, new Color(48, 58, 56));
    }

    public void DrawForeground(SceneryDefinition scenery)
    {
        // Side trusses seen directly from above, without hiding the train roof.
        foreach (var y in new[] { scenery.BridgeY - 30, scenery.BridgeY + 30 })
        {
            _paint.Line(new(scenery.BridgeLeft - 6, y), new(scenery.BridgeRight + 6, y), new Color(160, 169, 149), 4);
            for (var x = scenery.BridgeLeft; x < scenery.BridgeRight; x += 42)
            {
                _paint.Line(new(x, y - 6), new(x + 21, y + 6), new Color(102, 119, 106), 2);
                _paint.Line(new(x + 21, y + 6), new(x + 42, y - 6), new Color(102, 119, 106), 2);
            }
        }
        _paint.Text("ROYAL ALBERT BRIDGE", 1050, 502, 14, Palette.Muted, centered: true);
        _paint.Text("CORNWALL", 250, 578, 16, Palette.Muted);
        _paint.Text("PLYMOUTH", 1360, 600, 16, Palette.Muted, centered: true);
        _paint.Text("SINGLE TRACK / ONE TRAIN AT A TIME", 250, 625, 12, new Color(115, 139, 124));
        _paint.Text("N", 1400, 210, 13, Palette.Muted, centered: true);
        _paint.Line(new(1400, 232), new(1400, 256), Palette.Muted, 1.5f);
        _paint.Line(new(1400, 232), new(1395, 241), Palette.Muted, 1.5f);
        _paint.Line(new(1400, 232), new(1405, 241), Palette.Muted, 1.5f);
    }

    private void DrawTown()
    {
        _paint.Line(new(100, 272), new(285, 272), new Color(58, 66, 53), 13);
        _paint.Line(new(230, 196), new(230, 297), new Color(58, 66, 53), 11);
        for (var i = 0; i < 7; i++)
        {
            var x = 106 + i % 4 * 40;
            var y = 210 + i / 4 * 76;
            _paint.Rounded(x, y, 27, 24, 3, new Color(75, 78, 62));
            _paint.Line(new(x + 13, y + 2), new(x + 13, y + 22), new Color(96, 94, 72), 2);
        }
        _paint.Text("SALTASH", 330, 221, 14, new Color(121, 143, 117));
    }
}



