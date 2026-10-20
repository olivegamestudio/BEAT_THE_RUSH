using BeatTheRush.Core;
using Microsoft.Xna.Framework;
using static BeatTheRush.Game.RenderMath;

namespace BeatTheRush.Game;

internal sealed class SignalRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    public void DrawPortal(TrackRoute route, StationSimulation simulation)
    {
        var signal = route.Definition.Signal;
        var at = new Vector2(signal.X, signal.Y);
        var track = V(route.Path.Sample(route.Hold).Position);
        var color = AspectColor(simulation.PortalAspect(route.Definition.Id));
        _paint.Line(track, at, Palette.Border, 2);
        _paint.Circle(at, 35, color * 0.13f);
        _paint.Circle(at, 24, Palette.Background);
        _paint.Circle(at, 18, new Color(36, 48, 46));
        _paint.Circle(at, 10, color);
        _paint.Circle(at + new Vector2(-3, -3), 3, Color.White * 0.45f);
        _paint.Text(route.Definition.Id == "east" ? "E" : "W", at.X, at.Y + (at.Y < 420 ? -55 : 45), 13, Palette.Muted, centered: true);
    }

    public void DrawBlock(TrackRoute route, double distance, StationSimulation simulation)
    {
        var pose = route.Path.Sample(distance);
        if (pose.Position.X < 85 || pose.Position.X > 1510) return;
        var normal = new Vector2(MathF.Sin(pose.Angle), -MathF.Cos(pose.Angle));
        var at = V(pose.Position) + normal * 28;
        _paint.Line(V(pose.Position) + normal * 12, at, Palette.Muted * 0.6f, 2);
        _paint.Circle(at, 7, Palette.Background);
        _paint.Circle(at, 3.7f, AspectColor(simulation.BlockAspect(route, distance)));
    }
}

