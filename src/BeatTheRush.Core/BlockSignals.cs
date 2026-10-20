namespace BeatTheRush.Core;

internal static class BlockSignals
{
    public static SignalAspect Aspect(IReadOnlyList<TrainState> trains, TrackRoute route, double signalDistance, double blockLength = 240)
    {
        bool Occupied(double start, double end) => trains.Any(t => t.Route == route &&
            t.Distance >= start && t.Distance - t.Length < end);
        return Occupied(signalDistance, signalDistance + blockLength) ? SignalAspect.Red :
            Occupied(signalDistance + blockLength, signalDistance + blockLength * 2) ? SignalAspect.Amber : SignalAspect.Green;
    }
}
