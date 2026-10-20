namespace BeatTheRush.Core;

/// <summary>Boarding, platform pressure, and the passenger objective share one owner.</summary>
internal sealed class PassengerService(RulesDefinition rules, StationState state)
{
    private readonly RulesDefinition _rules = rules;
    private readonly StationState _state = state;
    public void Reset()
    {
        _state.Boarded = 0; _state.Outcome = GameOutcome.Playing;
        foreach (var platform in _state.Platforms)
        {
            platform.Waiting = Math.Min(platform.Definition.Capacity, _rules.InitialPassengers);
            platform.WaitSeconds = 0; platform.OverflowSeconds = 0;
        }
    }
    public void ServeTrain(TrainState train, double dt)
    {
        if (Math.Abs(train.Distance - train.Route.Berth) > 0.01 || train.Speed > 0.1) return;
        var platform = _state.Platforms.Single(p => p.Definition.Id == train.Route.Definition.Platform);
        platform.WaitSeconds = 0;
        var take = Math.Min(_rules.BoardingPerSecond * dt, Math.Min(train.Capacity - train.Load, platform.Waiting));
        train.Load += take; platform.Waiting -= take; _state.Boarded += take;
        train.Dwell += dt;
        if (train.Dwell >= _rules.DwellSeconds) train.BoardingComplete = true;
    }
    public void UpdateOutcome(double dt)
    {
        foreach (var platform in _state.Platforms)
        {
            platform.WaitSeconds = platform.Waiting >= 1 ? platform.WaitSeconds + dt : 0;
            platform.OverflowSeconds = platform.Waiting >= platform.Definition.Capacity - 0.001
                ? platform.OverflowSeconds + dt : 0;
        }
        // Fractional boarding must not leave the objective one rounding error short.
        if (_state.Boarded >= _rules.Goal - 1e-8)
        {
            _state.Boarded = Math.Max(_state.Boarded, _rules.Goal);
            _state.Outcome = GameOutcome.Won;
        }
        else if (_state.Platforms.Any(p => p.OverflowSeconds >= _rules.OverflowGrace))
            _state.Outcome = GameOutcome.Lost;
    }
}

