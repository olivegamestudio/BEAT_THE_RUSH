using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace BeatTheRush.Game;

internal sealed record Glyph(int Code, int X, int Y, int Width, int Height, float OffsetX, float OffsetY, float Advance);
internal sealed record FontAtlas(float CapHeight, Glyph[] Glyphs);
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(FontAtlas))]
internal partial class FontJsonContext : JsonSerializerContext;

internal sealed class Painter : IDisposable
{
    private readonly SpriteBatch _batch;
    private readonly Texture2D _pixel;
    private readonly Texture2D _circle;
    private readonly Texture2D _font;
    private readonly Dictionary<char, Glyph> _glyphs;
    private readonly float _capHeight;
    public Painter(GraphicsDevice device, SpriteBatch batch)
    {
        _batch = batch;
        _pixel = new Texture2D(device, 1, 1);
        _pixel.SetData(new[] { Color.White });
        _circle = new Texture2D(device, 64, 64);
        var pixels = new Color[64 * 64];
        for (var y = 0; y < 64; y++)
            for (var x = 0; x < 64; x++)
                pixels[y * 64 + x] = Color.White * Math.Clamp(32 - Vector2.Distance(new(x + 0.5f, y + 0.5f), new(32, 32)), 0, 1);
        _circle.SetData(pixels);
        using var fontStream = Resource("font.png");
        _font = Texture2D.FromStream(device, fontStream);
        // PNGs store straight alpha; SpriteBatch uses premultiplied alpha.
        var fontPixels = new Color[_font.Width * _font.Height];
        _font.GetData(fontPixels);
        for (var i = 0; i < fontPixels.Length; i++) fontPixels[i] = Color.FromNonPremultiplied(fontPixels[i].ToVector4());
        _font.SetData(fontPixels);
        using var metricStream = Resource("font.json");
        var atlas = JsonSerializer.Deserialize(metricStream, FontJsonContext.Default.FontAtlas)!;
        _capHeight = atlas.CapHeight;
        _glyphs = atlas.Glyphs.ToDictionary(g => (char)g.Code);
    }
    private static Stream Resource(string name) => Assembly.GetExecutingAssembly().GetManifestResourceStream("Assets." + name)
        ?? throw new InvalidOperationException($"Missing game asset: {name}");

    public void Fill(float x, float y, float width, float height, Color color)
    {
        if (width <= 0 || height <= 0) return;
        _batch.Draw(_pixel, new Vector2(x, y), null, color, 0, Vector2.Zero, new Vector2(width, height), SpriteEffects.None, 0);
    }
    public void Circle(Vector2 center, float radius, Color color) => _batch.Draw(_circle, center, null, color,
        0, new Vector2(32, 32), radius / 32, SpriteEffects.None, 0);
    public void Rounded(float x, float y, float width, float height, float radius, Color color)
    {
        radius = Math.Min(radius, Math.Min(width, height) / 2);
        Fill(x + radius, y, width - radius * 2, height, color);
        Fill(x, y + radius, width, height - radius * 2, color);
        Circle(new(x + radius, y + radius), radius, color);
        Circle(new(x + width - radius, y + radius), radius, color);
        Circle(new(x + radius, y + height - radius), radius, color);
        Circle(new(x + width - radius, y + height - radius), radius, color);
    }
    public void Line(Vector2 a, Vector2 b, Color color, float width = 1)
    {
        var d = b - a;
        _batch.Draw(_pixel, a, null, color, MathF.Atan2(d.Y, d.X), new Vector2(0, 0.5f),
            new Vector2(d.Length(), width), SpriteEffects.None, 0);
    }
    public void Box(Vector2 center, float width, float height, float angle, Color color) => _batch.Draw(_pixel, center,
        null, color, angle, new Vector2(0.5f, 0.5f), new Vector2(width, height), SpriteEffects.None, 0);

    public float Measure(string text, float size) => text.Sum(c => _glyphs.GetValueOrDefault(c, _glyphs['?']).Advance) * size / _capHeight;
    public void Text(string text, float x, float y, float size, Color color, bool centered = false)
    {
        if (centered) x -= Measure(text, size) / 2;
        var scale = size / _capHeight;
        foreach (var c in text)
        {
            var glyph = _glyphs.GetValueOrDefault(c, _glyphs['?']);
            if (glyph.Width > 0 && glyph.Height > 0)
                _batch.Draw(_font, new Vector2(x + glyph.OffsetX * scale, y + glyph.OffsetY * scale),
                    new Rectangle(glyph.X, glyph.Y, glyph.Width, glyph.Height), color, 0, Vector2.Zero, scale, SpriteEffects.None, 0);
            x += glyph.Advance * scale;
        }
    }
    public void GlyphSlice(char character, Vector2 center, float size, Color color, Rectangle clip,
        float verticalScale = 1, float hinge = 0)
    {
        var glyph = _glyphs.GetValueOrDefault(character, _glyphs['?']);
        if (glyph.Width == 0 || glyph.Height == 0 || verticalScale <= 0.001f) return;
        var scale = size / _capHeight;
        var x = center.X - glyph.Advance * scale / 2 + glyph.OffsetX * scale;
        var y = center.Y - size / 2 + glyph.OffsetY * scale;
        y = hinge + (y - hinge) * verticalScale;
        var width = glyph.Width * scale; var height = glyph.Height * scale * verticalScale;
        var left = Math.Max(x, clip.Left); var right = Math.Min(x + width, clip.Right);
        var top = Math.Max(y, clip.Top); var bottom = Math.Min(y + height, clip.Bottom);
        if (right <= left || bottom <= top) return;
        var sourceX = glyph.X + (int)MathF.Round((left - x) / width * glyph.Width);
        var sourceY = glyph.Y + (int)MathF.Round((top - y) / height * glyph.Height);
        var sourceRight = Math.Min(glyph.X + glyph.Width, glyph.X + (int)MathF.Round((right - x) / width * glyph.Width));
        var sourceBottom = Math.Min(glyph.Y + glyph.Height, glyph.Y + (int)MathF.Round((bottom - y) / height * glyph.Height));
        if (sourceRight <= sourceX || sourceBottom <= sourceY) return;
        var source = new Rectangle(sourceX, sourceY, sourceRight - sourceX, sourceBottom - sourceY);
        _batch.Draw(_font, new Vector2(left, top), source, color, 0, Vector2.Zero,
            new Vector2((right - left) / source.Width, (bottom - top) / source.Height), SpriteEffects.None, 0);
    }

    public void Dispose() { _pixel.Dispose(); _circle.Dispose(); _font.Dispose(); }
}

internal static class Palette
{
    public static readonly Color Background = new(12, 22, 24);
    public static readonly Color Panel = new(22, 36, 38);
    public static readonly Color Border = new(47, 65, 65);
    public static readonly Color Text = new(231, 235, 218);
    public static readonly Color Muted = new(141, 164, 156);
    public static readonly Color Green = new(117, 218, 151);
    public static readonly Color Amber = new(236, 185, 92);
    public static readonly Color Red = new(239, 118, 103);
}


