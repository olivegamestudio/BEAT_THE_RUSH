using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

internal sealed class SplitFlapRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    private static readonly Color Top = new(32, 38, 40), Bottom = new(23, 29, 31);
    public void Line(string text, int width, Vector2 origin, Vector2 cell, double elapsed, double delay, Color ink, float gap = 4)
    {
        text = text.ToUpperInvariant();
        for (var i = 0; i < width; i++)
        {
            var target = i < text.Length ? text[i] : ' ';
            var frame = SplitFlapAnimation.Sample(target, elapsed, delay + i * SplitFlapAnimation.ColumnDelay);
            DrawCell(new((int)(origin.X + i * (cell.X + gap)), (int)origin.Y, (int)cell.X, (int)cell.Y), frame, ink);
        }
    }
    private void DrawCell(Rectangle cell, FlapFrame frame, Color ink)
    {
        var hinge = cell.Y + cell.Height / 2f;
        var top = new Rectangle(cell.X, cell.Y, cell.Width, cell.Height / 2);
        var bottom = new Rectangle(cell.X, top.Bottom, cell.Width, cell.Height - top.Height);
        var center = new Vector2(cell.Center.X, hinge);
        var fontSize = cell.Height * 0.58f;
        _paint.Rounded(cell.X, cell.Y, cell.Width, cell.Height, cell.Width * 0.12f, Top);
        _paint.Fill(bottom.X, bottom.Y, bottom.Width, bottom.Height, Bottom);
        if (frame.Leaving == frame.Arriving)
            _paint.GlyphSlice(frame.Arriving, center, fontSize, ink, cell);
        else
        {
            _paint.GlyphSlice(frame.Arriving, center, fontSize, ink, top);
            _paint.GlyphSlice(frame.Leaving, center, fontSize, ink, bottom);
            if (frame.Progress < 0.5f)
            {
                var scale = Math.Max(0.001f, 1 - frame.Progress * 2);
                _paint.Fill(top.X, hinge - top.Height * scale, top.Width, top.Height * scale, Top);
                _paint.GlyphSlice(frame.Leaving, center, fontSize, ink, top, scale, hinge);
            }
            else
            {
                var scale = Math.Max(0.001f, (frame.Progress - 0.5f) * 2);
                _paint.Fill(bottom.X, hinge, bottom.Width, bottom.Height * scale, Bottom);
                _paint.GlyphSlice(frame.Arriving, center, fontSize, ink, bottom, scale, hinge);
            }
        }
        _paint.Fill(cell.X + 1, hinge, cell.Width - 2, Math.Max(1, cell.Height * 0.014f), Palette.Background * 0.7f);
    }
}

