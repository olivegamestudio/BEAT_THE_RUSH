using BeatTheRush.Core;
using Microsoft.Xna.Framework;
using static BeatTheRush.Game.RenderMath;

namespace BeatTheRush.Game;

internal sealed class PlatformRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    public void Draw(PlatformState platform)
    {
        var p = platform.Definition;
        _paint.Rounded(p.X - 3, p.Y - 3, p.Width + 6, p.Height + 6, 7, new Color(37, 40, 36));
        _paint.Rounded(p.X, p.Y, p.Width, p.Height, 5, new Color(103, 111, 91));
        var upper = p.Y < 420;
        var lineY = upper ? p.Y + p.Height - 5 : p.Y + 5;
        _paint.Line(new(p.X + 7, lineY), new(p.X + p.Width - 7, lineY), Palette.Amber * 0.85f, 2);
        for (var i = 0; i < (int)Math.Ceiling(platform.Waiting); i++)
        {
            var center = new Vector2(p.X + 22 + i % 14 * 22, p.Y + (upper ? 28 : 22) + i / 14 * (upper ? -16 : 16));
            var color = platform.WaitSeconds > 26 ? Palette.Red : i % 3 == 0 ? Palette.Amber : new Color(194, 205, 176);
            _paint.Circle(center, 4.3f, color);
            _paint.Circle(center + new Vector2(-1, -1), 1.5f, new Color(239, 220, 180));
        }
        var textY = upper ? p.Y - 41 : p.Y + p.Height + 17;
        var count = $"{(int)Math.Ceiling(platform.Waiting - 0.00001)}/{p.Capacity}";
        _paint.Text(count, p.X + p.Width - _paint.Measure(count, 14), textY, 14,
            platform.Fill >= 0.9 ? Palette.Red : Palette.Muted);
        var meterY = upper ? p.Y - 15 : p.Y + p.Height + 42;
        _paint.Fill(p.X, meterY, p.Width, 3, new Color(58, 75, 61));
        _paint.Fill(p.X, meterY, (float)(p.Width * platform.Fill), 3, platform.Fill >= 0.9 ? Palette.Red : Palette.Green);
    }
}


