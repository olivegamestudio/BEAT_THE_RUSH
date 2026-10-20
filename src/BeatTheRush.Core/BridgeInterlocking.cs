namespace BeatTheRush.Core;

/// <summary>Player intent and physical ownership remain separate when a route is changed.</summary>
internal sealed class BridgeInterlocking(IReadOnlyList<TrackRoute> routes)
{
    public ExclusiveSection Section { get; private set; } = new();
    public string? RequestedRoute { get; private set; } = routes[0].Definition.Id;
    public void Reset() { Section = new(); RequestedRoute = routes[0].Definition.Id; }
    public void ToggleRoute(string routeId)
    {
        if (!routes.Any(r => r.Definition.Id == routeId)) throw new ArgumentException("Unknown route.", nameof(routeId));
        RequestedRoute = RequestedRoute == routeId ? null : routeId;
    }
    public void HoldAll() => RequestedRoute = null;
    public SignalAspect PortalAspect(string routeId) => RequestedRoute != routeId ? SignalAspect.Red :
        Section.OwnerId is not null ? SignalAspect.Amber : SignalAspect.Green;
    public double MovementCeiling(TrainState train)
    {
        var route = train.Route;
        if (train.HasSection && train.Distance - train.Length > route.Release + 8)
        {
            Section.Release(train.Id); train.HasSection = false; train.SectionCleared = true;
        }
        if (train.HasSection || train.SectionCleared) return double.PositiveInfinity;
        var ready = route.Berth > route.Hold || train.BoardingComplete;
        if (ready && train.Distance >= route.Hold - 0.01 &&
            Section.TryAcquire(train.Id, route.Definition.Id, RequestedRoute))
        {
            train.HasSection = true;
            return double.PositiveInfinity;
        }
        return route.Hold;
    }
}

