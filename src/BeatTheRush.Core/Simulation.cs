namespace BeatTheRush.Core;

/// <summary>Composition root and public game API; individual systems own their rules.</summary>
public sealed class StationSimulation
{
    public const double FollowGap = 30;
    private readonly StationState _state;
    private readonly BridgeInterlocking _interlocking;
    private readonly PassengerService _passengers;
    private readonly TrainMovement _movement;
    private readonly TrafficScheduler _traffic;
    private readonly bool _automaticTraffic;
    public StationDefinition Definition { get; }
    public TrackGraph Graph { get; }
    public IReadOnlyList<TrainState> Trains => _state.Trains;
    public IReadOnlyList<PlatformState> Platforms => _state.Platforms;
    public ExclusiveSection Section => _interlocking.Section;
    public string? RequestedRoute => _interlocking.RequestedRoute;
    public double Boarded => _state.Boarded;
    public double Elapsed => _state.Elapsed;
    public GameOutcome Outcome => _state.Outcome;
    public int Stars => Boarded >= Definition.Rules.Goal ? 3 :
        Boarded >= Definition.Rules.Goal / 2.0 ? 2 : Boarded >= 1 ? 1 : 0;

    public StationSimulation(StationDefinition definition, int seed = 2406, bool automaticTraffic = true)
    {
        StationValidator.Validate(definition);
        Definition = definition; Graph = new(definition); _automaticTraffic = automaticTraffic;
        _state = new(definition.Platforms.Select(p => new PlatformState(p)).ToArray());
        foreach (var route in Graph.Routes)
            if (!Platforms.Any(p => p.Definition.Id == route.Definition.Platform))
                throw new ArgumentException($"Route {route.Definition.Id}: platform does not exist.");
        _interlocking = new(Graph.Routes);
        _passengers = new(definition.Rules, _state);
        _movement = new(definition.Rules, _state, _interlocking, _passengers);
        _traffic = new(definition, Graph, _state, seed, automaticTraffic);
        Reset();
    }
    public void Reset()
    {
        _state.Trains.Clear(); _state.Elapsed = 0;
        _interlocking.Reset(); _passengers.Reset(); _traffic.Reset();
    }
    public void ToggleRoute(string routeId) => _interlocking.ToggleRoute(routeId);
    public void HoldAll() => _interlocking.HoldAll();
    public SignalAspect PortalAspect(string routeId) => _interlocking.PortalAspect(routeId);
    public SignalAspect BlockAspect(TrackRoute route, double signalDistance, double blockLength = 240) =>
        BlockSignals.Aspect(_state.Trains, route, signalDistance, blockLength);
    internal TrainState AddTrain(string routeId, int carriages, bool express = false, double distance = 0) =>
        _traffic.AddTrain(routeId, carriages, express, distance);
    public void Step(double dt)
    {
        if (!double.IsFinite(dt) || dt <= 0 || dt > 0.25) throw new ArgumentOutOfRangeException(nameof(dt));
        if (Outcome != GameOutcome.Playing) return;
        _state.Elapsed += dt;
        if (_automaticTraffic) _traffic.Update(dt);
        _movement.Step(dt);
        _passengers.UpdateOutcome(dt);
    }
}

