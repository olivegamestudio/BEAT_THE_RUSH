using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

internal sealed class TitleScreenRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    private readonly SplitFlapRenderer _flaps = new(paint);
    private readonly MenuRailwayRenderer _railway = new(paint);
    public void Draw(AppFlow flow)
    {
        _railway.Draw(flow.MenuRailway);
        _paint.Text("OLIVE GAME STUDIO", 800, 170, 16, Palette.Muted, centered: true);
        const string title = "BEAT THE RUSH";
        const float cellWidth = 70, gap = 7;
        var boardWidth = title.Length * (cellWidth + gap) - gap;
        _flaps.Line(title, title.Length, new((1600 - boardWidth) / 2, 265), new(cellWidth, 108),
            flow.ScreenElapsed % 22, 0, Palette.Text, gap);
        _paint.Text("Route the trains. Clear the platforms.", 800, 423, 23, Palette.Muted, centered: true);
        var button = MenuLayout.PlayButton;
        var pulse = (float)(0.5 + 0.5 * Math.Sin(flow.ScreenElapsed * Math.PI / 1.05));
        _paint.Rounded(button.X - 7, button.Y - 7, button.Width + 14, button.Height + 14, 22, Palette.Green * (0.05f + pulse * 0.08f));
        _paint.Rounded(button.X, button.Y, button.Width, button.Height, 16, Palette.Green);
        _paint.Text("PLAY", button.Center.X, button.Y + 34, 28, Palette.Background, centered: true);
        _paint.Text("WORK THE SIGNALS. KEEP BRITAIN MOVING.", 800, 800, 13, Palette.Muted, centered: true);
    }
}

