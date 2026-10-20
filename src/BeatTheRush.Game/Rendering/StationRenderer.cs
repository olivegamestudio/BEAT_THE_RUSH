using BeatTheRush.Core;
namespace BeatTheRush.Game;

/// <summary>Draw order is explicit; each visual component owns only its own subject.</summary>
internal sealed class StationRenderer(Painter paint)
{
    private readonly SceneryRenderer _scenery = new(paint);
    private readonly TrackRenderer _tracks = new(paint);
    private readonly PlatformRenderer _platforms = new(paint);
    private readonly TrainRenderer _trains = new(paint);
    private readonly SignalRenderer _signals = new(paint);
    public void Draw(StationSimulation simulation, double animationTime)
    {
        _scenery.DrawBackground(simulation, animationTime);
        foreach (var edge in simulation.Graph.Edges) _tracks.Draw(edge);
        foreach (var route in simulation.Graph.Routes)
            for (double d = 380; d < route.Hold - 130; d += 240) _signals.DrawBlock(route, d, simulation);
        foreach (var platform in simulation.Platforms) _platforms.Draw(platform);
        foreach (var train in simulation.Trains) _trains.Draw(train, simulation.Definition.Rules);
        _scenery.DrawForeground(simulation.Definition.Scenery);
        foreach (var route in simulation.Graph.Routes) _signals.DrawPortal(route, simulation);
    }
}

