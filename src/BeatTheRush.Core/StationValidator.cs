namespace BeatTheRush.Core;

internal static class StationValidator
{
    public static void Validate(StationDefinition definition)
    {
        var r = definition.Rules;
        var positive = new[] { r.DwellSeconds, r.BoardingPerSecond, r.PassengerIntervalMin,
            r.PassengerIntervalMax, r.TrainIntervalMin, r.TrainIntervalMax, r.OverflowGrace,
            r.LocalSpeed, r.ExpressSpeed };
        if (positive.Any(v => !double.IsFinite(v) || v <= 0) || r.Goal < 1 || r.MaxTrains < 1 ||
            r.PassengerIntervalMin > r.PassengerIntervalMax || r.TrainIntervalMin > r.TrainIntervalMax ||
            !double.IsFinite(r.InitialPassengers) || r.InitialPassengers < 0 ||
            !double.IsFinite(r.ExpressChance) || r.ExpressChance is < 0 or > 1 ||
            definition.Routes.Length < 1 || definition.Platforms.Length < 1 ||
            definition.Platforms.Any(p => p.Capacity < 1 || p.Width <= 0 || p.Height <= 0))
            throw new ArgumentException("Station rules contain invalid ranges or capacities.");
        if (definition.Platforms.Select(p => p.Id).Distinct().Count() != definition.Platforms.Length)
            throw new ArgumentException("Platform IDs must be unique.");
    }
}
