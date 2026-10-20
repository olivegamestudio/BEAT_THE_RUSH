namespace BeatTheRush.Core;

public enum GameOutcome { Playing, Won, Lost }
public enum SignalAspect { Green, Amber, Red }

public sealed class PlatformState(PlatformDefinition definition)
{
    public PlatformDefinition Definition { get; } = definition;
    public double Waiting { get; internal set; }
    public double WaitSeconds { get; internal set; }
    public double OverflowSeconds { get; internal set; }
    public double Fill => Waiting / Definition.Capacity;
}

public sealed class TrainState
{
    public const double CarLength = 38;
    public int Id { get; }
    public TrackRoute Route { get; }
    public int Carriages { get; }
    public bool Express { get; }
    public double Length => Carriages * CarLength;
    public double Capacity => Carriages * 3;
    public double Distance { get; internal set; }
    public double Speed { get; internal set; }
    public double Load { get; internal set; }
    public double Dwell { get; internal set; }
    public bool BoardingComplete { get; internal set; }
    public bool HasSection { get; internal set; }
    public bool SectionCleared { get; internal set; }
    public SignalAspect Aspect { get; internal set; }
    public double StoppedSeconds { get; internal set; }
    internal TrainState(int id, TrackRoute route, int carriages, bool express, double distance)
    {
        Id = id; Route = route; Carriages = carriages; Express = express; Distance = distance;
    }
}


internal sealed class StationState(IReadOnlyList<PlatformState> platforms)
{
    public List<TrainState> Trains { get; } = [];
    public IReadOnlyList<PlatformState> Platforms { get; } = platforms;
    public double Boarded { get; set; }
    public double Elapsed { get; set; }
    public GameOutcome Outcome { get; set; }
}

