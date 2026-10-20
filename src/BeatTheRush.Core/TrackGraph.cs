using System.Numerics;

namespace BeatTheRush.Core;

public readonly record struct TrackPose(Vector2 Position, float Angle);

/// <summary>Distance along a polyline. Extrapolation lets a whole train enter and leave naturally.</summary>
public sealed class TrackPath
{
    private readonly Vector2[] _points;
    private readonly double[] _distances;
    public IReadOnlyList<Vector2> Points => _points;
    public double Length => _distances[^1];

    public TrackPath(IEnumerable<Vector2> points)
    {
        _points = points.ToArray();
        if (_points.Length < 2 || _points.Any(p => !float.IsFinite(p.X) || !float.IsFinite(p.Y)))
            throw new ArgumentException("A track needs at least two finite points.");
        _distances = new double[_points.Length];
        for (var i = 1; i < _points.Length; i++)
        {
            var length = Vector2.Distance(_points[i - 1], _points[i]);
            if (length < 0.001f) throw new ArgumentException("Track segments must have positive length.");
            _distances[i] = _distances[i - 1] + length;
        }
    }

    public TrackPose Sample(double distance)
    {
        var i = Array.BinarySearch(_distances, distance);
        if (i < 0) i = ~i;
        i = Math.Clamp(i, 1, _points.Length - 1);
        var direction = _points[i] - _points[i - 1];
        var t = (float)((distance - _distances[i - 1]) / (_distances[i] - _distances[i - 1]));
        return new(_points[i - 1] + direction * t, MathF.Atan2(direction.Y, direction.X));
    }

    public float SmoothAngle(double distance, double halfWindow = 12)
    {
        var direction = Sample(distance + halfWindow).Position - Sample(distance - halfWindow).Position;
        return MathF.Atan2(direction.Y, direction.X);
    }
}

public sealed class TrackRoute
{
    public RouteDefinition Definition { get; }
    public TrackPath Path { get; }
    public double Berth { get; }
    public double Hold { get; }
    public double Release { get; }
    internal TrackRoute(RouteDefinition definition, TrackPath path, Dictionary<string, double> distances)
    {
        Definition = definition; Path = path;
        Berth = distances[definition.Berth]; Hold = distances[definition.SectionHold];
        Release = distances[definition.SectionRelease];
        if (Hold >= Release) throw new ArgumentException($"Route {definition.Id}: section exit must follow its entry.");
    }
}

/// <summary>The renderer and simulation use these same validated edges.</summary>
public sealed class TrackGraph
{
    private readonly Dictionary<string, NodeDefinition> _nodes;
    private readonly EdgeDefinition[] _edges;
    public IReadOnlyList<TrackPath> Edges { get; }
    public IReadOnlyList<TrackRoute> Routes { get; }

    public TrackGraph(StationDefinition definition)
    {
        _nodes = definition.Nodes.ToDictionary(n => n.Id);
        _edges = definition.Edges;
        if (_edges.Select(e => e.Id).Distinct().Count() != _edges.Length)
            throw new ArgumentException("Track edge IDs must be unique.");
        if (_edges.GroupBy(e => string.CompareOrdinal(e.From, e.To) < 0 ? (e.From, e.To) : (e.To, e.From)).Any(g => g.Count() > 1))
            throw new ArgumentException("Parallel edges require distinct junction nodes.");
        Edges = _edges.Select(e => new TrackPath(Span(e, e.From, includeStart: true))).ToArray();
        Routes = definition.Routes.Select(BuildRoute).ToArray();
        if (Routes.Select(r => r.Definition.Id).Distinct().Count() != Routes.Count)
            throw new ArgumentException("Route IDs must be unique.");
    }

    private Vector2 Point(string id)
    {
        if (!_nodes.TryGetValue(id, out var node)) throw new ArgumentException($"Unknown track node: {id}");
        return new(node.X, node.Y);
    }

    private IEnumerable<Vector2> Span(EdgeDefinition edge, string from, bool includeStart)
    {
        if (includeStart) yield return Point(from);
        var forward = edge.From == from;
        var via = edge.Via ?? [];
        foreach (var p in forward ? via : via.Reverse()) yield return new(p.X, p.Y);
        yield return Point(forward ? edge.To : edge.From);
    }

    private TrackRoute BuildRoute(RouteDefinition definition)
    {
        if (definition.Nodes.Length < 2) throw new ArgumentException("A route needs at least two nodes.");
        var points = new List<Vector2> { Point(definition.Nodes[0]) };
        var distances = new Dictionary<string, double> { [definition.Nodes[0]] = 0 };
        var distance = 0.0;
        for (var i = 1; i < definition.Nodes.Length; i++)
        {
            var from = definition.Nodes[i - 1]; var to = definition.Nodes[i];
            var edge = _edges.SingleOrDefault(e => e.From == from && e.To == to || e.To == from && e.From == to)
                ?? throw new ArgumentException($"Route {definition.Id}: no edge connects {from} to {to}.");
            foreach (var point in Span(edge, from, includeStart: false))
            {
                distance += Vector2.Distance(points[^1], point);
                points.Add(point);
            }
            distances.Add(to, distance);
        }
        foreach (var anchor in new[] { definition.Berth, definition.SectionHold, definition.SectionRelease })
            if (!distances.ContainsKey(anchor)) throw new ArgumentException($"Route {definition.Id}: missing anchor {anchor}.");
        return new(definition, new TrackPath(points), distances);
    }
}

