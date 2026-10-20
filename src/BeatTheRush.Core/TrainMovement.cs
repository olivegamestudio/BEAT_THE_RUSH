namespace BeatTheRush.Core;

/// <summary>Integrates speed and position against following, boarding, and interlocking limits.</summary>
internal sealed class TrainMovement(RulesDefinition rules, StationState state,
    BridgeInterlocking interlocking, PassengerService passengers)
{
    private readonly RulesDefinition _rules = rules;
    private readonly StationState _state = state;
    private readonly BridgeInterlocking _interlocking = interlocking;
    private readonly PassengerService _passengers = passengers;
    public void Step(double dt)
    {
        // Read following limits from one snapshot, so list order cannot change movement authority.
        var positions = _state.Trains.Select(t => (Train: t, Distance: t.Distance)).ToArray();
        foreach (var train in _state.Trains.OrderBy(t => t.Id))
        {
            var route = train.Route;
            var cap = route.Path.Length + train.Length;
            if (!train.BoardingComplete) cap = Math.Min(cap, route.Berth);
            foreach (var other in positions)
                if (other.Train != train && other.Train.Route == route &&
                    (other.Distance > train.Distance || other.Distance == train.Distance && other.Train.Id < train.Id))
                    cap = Math.Min(cap, other.Distance - other.Train.Length - StationSimulation.FollowGap);

            cap = Math.Min(cap, _interlocking.MovementCeiling(train));

            var headroom = Math.Max(0, cap - train.Distance);
            var limit = train.Express ? _rules.ExpressSpeed : _rules.LocalSpeed;
            var target = Math.Min(limit, Math.Sqrt(2 * 95 * headroom));
            var delta = (train.Speed < target ? 140 : 95) * dt;
            var speed = train.Speed < target ? Math.Min(target, train.Speed + delta) : Math.Max(target, train.Speed - delta);
            var next = Math.Max(train.Distance, Math.Min(cap, train.Distance + speed * dt));
            train.Speed = (next - train.Distance) / dt;
            train.Distance = next;
            train.StoppedSeconds = train.Speed < 0.1 ? train.StoppedSeconds + dt : 0;
            train.Aspect = headroom < 1 ? SignalAspect.Red : headroom < 170 ? SignalAspect.Amber : SignalAspect.Green;
            _passengers.ServeTrain(train, dt);
        }

        _state.Trains.RemoveAll(train => train.Distance >= train.Route.Path.Length + train.Length - 0.001);
    }
}
