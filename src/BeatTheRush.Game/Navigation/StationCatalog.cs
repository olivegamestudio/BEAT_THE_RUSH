using BeatTheRush.Core;
namespace BeatTheRush.Game;

internal sealed record StationEntry(string Id, int Number, string Name, string Region, bool Available)
{
    public string BoardName => Name.Length <= 15 ? Name.ToUpperInvariant() : Name.Split(' ')[0].ToUpperInvariant();
}
internal static class StationCatalog
{
    public static IReadOnlyList<StationEntry> Entries { get; } = new StationEntry[]
    {
        new("saltash", 1, "Saltash", "Cornwall", true),
        new("dawlish", 2, "Dawlish Warren", "Devon", false),
        new("worcester", 3, "Worcester Foregate Street", "Worcestershire", false),
        new("newark", 4, "Newark", "Nottinghamshire", false),
        new("crewe", 5, "Crewe", "Cheshire", false),
        new("lostwithiel", 6, "Lostwithiel", "Cornwall", false),
        new("birmingham", 19, "Birmingham New Street", "West Midlands", false)
    };
    public static StationSimulation Create(string id) => id switch
    {
        "saltash" => new(StationDefinition.Saltash()),
        _ => throw new ArgumentException("This station has not been rebuilt yet.", nameof(id))
    };
}

