using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

/// <summary>Uses the renderer's inverse camera transform to route a canvas tap.</summary>
internal static class SignalTapRouter
{
    public static void Apply(GameSession session, Vector2 point)
    {
        if (session.OverlayVisible)
        {
            if (GameLayout.OverlayButton.Contains(point)) session.Handle(GameCommand.StartOrResume);
            return;
        }
        if (GameLayout.PauseButton.Contains(point)) { session.Handle(GameCommand.Pause); return; }
        if (!GameLayout.MapBounds.Contains(point)) return;
        var world = Vector2.Transform(point, GameLayout.CanvasToWorld);
        foreach (var route in session.Simulation.Graph.Routes)
        {
            var signal = route.Definition.Signal;
            if (Vector2.Distance(world, new(signal.X, signal.Y)) > 42) continue;
            session.Handle(route.Definition.Id == "east" ? GameCommand.East : GameCommand.West);
            return;
        }
    }
}

