using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

public readonly record struct ScreenInsets(float Left, float Top, float Right, float Bottom);
internal static class GameLayout
{
    public const int Width = 1600, Height = 900;
    public static readonly Rectangle MapBounds = new(60, 180, 1480, 660);
    public static readonly Rectangle PauseButton = new(1430, 52, 100, 80);
    public static readonly Rectangle OverlayButton = new(590, 570, 420, 80);
    // Frame the operational area more closely; both bridge controls remain visible.
    public static readonly Matrix WorldToCanvas = Matrix.CreateTranslation(-200, -420, 0)
        * Matrix.CreateScale(1480f / 1260f) * Matrix.CreateTranslation(60, 510, 0);
    public static readonly Matrix CanvasToWorld = Matrix.Invert(WorldToCanvas);
}

internal sealed class CanvasViewport
{
    private Vector2 _pixelSize = new(GameLayout.Width, GameLayout.Height);
    public Rectangle Destination { get; private set; } = new(0, 0, GameLayout.Width, GameLayout.Height);
    public void Update(int screenWidth, int screenHeight, ScreenInsets insets)
    {
        _pixelSize = new(screenWidth, screenHeight);
        var width = Math.Max(1, screenWidth - insets.Left - insets.Right);
        var height = Math.Max(1, screenHeight - insets.Top - insets.Bottom);
        var scale = Math.Min(width / GameLayout.Width, height / GameLayout.Height);
        Destination = new((int)(insets.Left + (width - GameLayout.Width * scale) / 2),
            (int)(insets.Top + (height - GameLayout.Height * scale) / 2),
            Math.Max(1, (int)(GameLayout.Width * scale)), Math.Max(1, (int)(GameLayout.Height * scale)));
    }
    public Vector2 FromClient(Vector2 point, int clientWidth, int clientHeight) =>
        ToCanvas(new(point.X * _pixelSize.X / Math.Max(1, clientWidth),
            point.Y * _pixelSize.Y / Math.Max(1, clientHeight)));
    public Vector2 ToCanvas(Vector2 p) => new((p.X - Destination.X) * GameLayout.Width / Destination.Width,
        (p.Y - Destination.Y) * GameLayout.Height / Destination.Height);
}


