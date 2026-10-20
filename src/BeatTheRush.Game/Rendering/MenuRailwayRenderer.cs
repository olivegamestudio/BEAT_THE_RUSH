using Microsoft.Xna.Framework;
using static BeatTheRush.Game.RenderMath;
namespace BeatTheRush.Game;

internal sealed class MenuRailwayRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    private static readonly Color[] Liveries = [new(71, 153, 117), new(181, 118, 72), new(102, 138, 160), new(167, 91, 83)];
    public void Draw(MenuRailway railway)
    {
        foreach (var path in railway.Paths)
        {
            var a = V(path.Points[0]); var b = V(path.Points[^1]);
            _paint.Line(a, b, new Color(30, 45, 41), 18);
            _paint.Line(a, b, new Color(56, 73, 63), 2);
        }
        foreach (var train in railway.Trains)
            for (var c = 0; c < train.Carriages; c++)
            {
                var pose = railway.Paths[train.Path].Sample(train.Distance - (c + 0.5) * 44);
                var center = V(pose.Position);
                var direction = new Vector2(MathF.Cos(pose.Angle), MathF.Sin(pose.Angle));
                _paint.Box(center, 39, 21, pose.Angle, Liveries[train.Tint]);
                _paint.Box(center, 29, 13, pose.Angle, new Color(172, 187, 157));
                _paint.Box(center + direction * 11, 4, 10, pose.Angle, new Color(50, 76, 67));
                if (c == 0) _paint.Box(center + direction * 18, 2, 14, pose.Angle, Palette.Text);
            }
        foreach (var signal in railway.Signals)
        {
            var pose = railway.Paths[signal.Path].Sample(signal.Distance);
            var foot = V(pose.Position); var light = foot + new Vector2(0, -35);
            _paint.Line(foot, light, Palette.Muted, 2);
            _paint.Circle(light, 9, Palette.Background);
            _paint.Circle(light, 4, signal.RedAt(railway.Elapsed) ? Palette.Red : Palette.Green);
        }
        // Keep the operational animation behind the title and its controls.
        _paint.Fill(0, 0, GameLayout.Width, GameLayout.Height, Palette.Background * 0.68f);
    }
}

