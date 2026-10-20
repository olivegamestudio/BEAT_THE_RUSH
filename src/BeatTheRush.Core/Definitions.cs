using System.Text.Json;
using System.Text.Json.Serialization;

namespace BeatTheRush.Core;

public sealed record NodeDefinition(string Id, float X, float Y);
public sealed record PointDefinition(float X, float Y);
public sealed record EdgeDefinition(string Id, string From, string To, PointDefinition[]? Via = null);
public sealed record PlatformDefinition(string Id, string Name, float X, float Y, float Width, float Height, int Capacity);
public sealed record RouteDefinition(string Id, string Direction, string[] Nodes, string Platform,
    string Berth, string SectionHold, string SectionRelease, PointDefinition Signal);
public sealed record RulesDefinition(int Goal, double DwellSeconds, double BoardingPerSecond,
    double PassengerIntervalMin, double PassengerIntervalMax, double TrainIntervalMin,
    double TrainIntervalMax, double OverflowGrace, double ExpressChance,
    double LocalSpeed, double ExpressSpeed, int MaxTrains, double InitialPassengers);
public sealed record SceneryDefinition(float RiverLeft, float RiverRight, float BridgeLeft, float BridgeRight, float BridgeY);
public sealed record StationDefinition(string Id, string Name, string Subtitle, string SectionName,
    NodeDefinition[] Nodes, EdgeDefinition[] Edges, PlatformDefinition[] Platforms,
    RouteDefinition[] Routes, RulesDefinition Rules, SceneryDefinition Scenery)
{
    public static StationDefinition Saltash()
    {
        using var stream = typeof(StationDefinition).Assembly.GetManifestResourceStream(
            "BeatTheRush.Core.Stations.saltash.json") ?? throw new InvalidOperationException("Saltash definition is missing.");
        return JsonSerializer.Deserialize(stream, DefinitionJsonContext.Default.StationDefinition)
            ?? throw new InvalidDataException("Saltash definition is empty.");
    }
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(StationDefinition))]
internal partial class DefinitionJsonContext : JsonSerializerContext;

