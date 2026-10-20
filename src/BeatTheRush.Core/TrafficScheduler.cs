namespace BeatTheRush.Core;

/// <summary>Owns seeded arrivals and admission at route entrances.</summary>
internal sealed class TrafficScheduler(StationDefinition definition, TrackGraph graph, StationState state, int seed, bool automatic)
{
    private readonly StationDefinition _definition = definition;
    private readonly TrackGraph _graph = graph;
    private readonly StationState _state = state;
    private Random _random = new(seed);
    private int _nextId;
    private double _passengerTimer, _trainTimer;
    public void Reset()
    {
        _random = new(seed); _nextId = 1; _passengerTimer = 1.4; _trainTimer = 7;
        if (!automatic) return;
        AddTrain(_graph.Routes[0].Definition.Id, 3, distance: 230);
        if (_graph.Routes.Count > 1) AddTrain(_graph.Routes[1].Definition.Id, 2, distance: 240);
    }
    private double Between(double min, double max) => min + _random.NextDouble() * (max - min);
    public TrainState AddTrain(string routeId, int carriages, bool express = false, double distance = 0)
    {
        if (carriages < 1) throw new ArgumentOutOfRangeException(nameof(carriages));
        var route = _graph.Routes.Single(r => r.Definition.Id == routeId);
        var train = new TrainState(_nextId++, route, carriages, express, distance);
        _state.Trains.Add(train);
        return train;
    }
    public void Update(double dt)
    {
        var r = _definition.Rules;
        _passengerTimer -= dt;
        if (_passengerTimer <= 0)
        {
            var platform = _state.Platforms[_random.Next(_state.Platforms.Count)];
            platform.Waiting = Math.Min(platform.Definition.Capacity, platform.Waiting + 1);
            _passengerTimer += Between(r.PassengerIntervalMin, r.PassengerIntervalMax);
        }
        _trainTimer -= dt;
        if (_trainTimer > 0) return;
        var routes = _graph.Routes.OrderBy(route => _state.Trains.Count(t => t.Route == route)).ToArray();
        foreach (var route in routes)
        {
            // New stock waits outside the scene until there is enough room for its whole body.
            if (_state.Trains.Count >= r.MaxTrains) break;
            if (_state.Trains.Any(t => t.Route == route && t.Distance - t.Length < StationSimulation.FollowGap)) continue;
            var express = _random.NextDouble() < r.ExpressChance;
            AddTrain(route.Definition.Id, express ? _random.Next(4, 6) : _random.Next(2, 4), express);
            break;
        }
        _trainTimer += Between(r.TrainIntervalMin, r.TrainIntervalMax);
    }
}
