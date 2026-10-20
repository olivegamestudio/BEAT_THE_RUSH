using BeatTheRush.Core;
using Microsoft.Xna.Framework;
using static BeatTheRush.Game.RenderMath;

namespace BeatTheRush.Game;

internal sealed class TrackRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    public void Draw(TrackPath path)
    {
        for (var i = 1; i < path.Points.Count; i++)
            _paint.Line(V(path.Points[i - 1]), V(path.Points[i]), new Color(44, 48, 43), 27);
        for (double d = 0; d <= path.Length; d += 16)
        {
            var pose = path.Sample(d);
            _paint.Box(V(pose.Position), 5, 23, pose.Angle, new Color(77, 79, 63));
        }
        for (var i = 1; i < path.Points.Count; i++)
        {
            var a = V(path.Points[i - 1]); var b = V(path.Points[i]);
            var direction = Vector2.Normalize(b - a);
            var normal = new Vector2(-direction.Y, direction.X) * 6;
            _paint.Line(a + normal, b + normal, new Color(153, 163, 147), 2.5f);
            _paint.Line(a - normal, b - normal, new Color(153, 163, 147), 2.5f);
        }
    }
}

