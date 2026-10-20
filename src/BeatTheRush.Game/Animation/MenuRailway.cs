using BeatTheRush.Core;
using System.Numerics;
namespace BeatTheRush.Game;

internal sealed class MenuTrain(int path, double distance, double topSpeed, int carriages, int tint)
{
    public int Path { get; } = path;
    public double Distance { get; set; } = distance;
    public double Speed { get; set; }
    public double TopSpeed { get; } = topSpeed;
    public int Carriages { get; } = carriages;
    public int Tint { get; } = tint;
}
internal sealed record MenuSignal(int Path, double Distance, double Period, double Phase)
{
    public bool RedAt(double seconds) => (int)Math.Floor((seconds + Phase) / Period) % 2 == 0;
}

/// <summary>A decorative railway for the title screen, independent of any playable station.</summary>
internal sealed class MenuRailway
{
    public IReadOnlyList<TrackPath> Paths { get; }
    public IReadOnlyList<MenuTrain> Trains { get; }
    public IReadOnlyList<MenuSignal> Signals { get; }
    public double Elapsed { get; private set; }
    public MenuRailway()
    {
        Vector2 P(float x, float y) => new(x * 1.6f, y * 1.6f);
        Paths = new TrackPath[]
        {
            new([P(-320,120),P(1320,205)]), new([P(1320,250),P(-320,250)]),
            new([P(-320,400),P(1320,320)]), new([P(1320,40),P(-320,520)]),
            new([P(-320,520),P(1320,70)]), new([P(1320,300),P(-320,470)]),
            new([P(-320,470),P(1320,140)])
        };
        Trains = Paths.Select((p, i) => new MenuTrain(i, p.Length * 0.22 + i * 110, 110 + i * 13, 4 + i % 4, i % 4)).ToArray();
        Signals = new MenuSignal[]
        {
            new(0,Paths[0].Length * 0.28,3.2,0), new(2,Paths[2].Length * 0.28,4.2,0.7),
            new(0,Paths[0].Length * 0.72,5.2,1.4), new(2,Paths[2].Length * 0.72,3.2,2.1)
        };
    }
    public void Update(double dt)
    {
        Elapsed += dt;
        foreach (var train in Trains)
        {
            var cap = double.PositiveInfinity;
            foreach (var signal in Signals)
                if (signal.Path == train.Path && signal.RedAt(Elapsed) && train.Distance <= signal.Distance)
                    cap = Math.Min(cap, signal.Distance - 32);
            var target = Math.Min(train.TopSpeed, Math.Sqrt(2 * 100 * Math.Max(0, cap - train.Distance)));
            train.Speed = train.Speed < target ? Math.Min(target, train.Speed + dt * 100) : Math.Max(target, train.Speed - dt * 100);
            train.Distance = Math.Max(train.Distance, Math.Min(cap, train.Distance + train.Speed * dt));
            if (train.Distance > Paths[train.Path].Length + train.Carriages * 44) train.Distance = 0;
        }
    }
}

