namespace BeatTheRush.Game;

internal readonly record struct FlapFrame(char Leaving, char Arriving, float Progress);
internal static class SplitFlapAnimation
{
    public const string Characters = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-'&/";
    public const double StepSeconds = 0.05, ColumnDelay = 0.04, TileDelay = 0.09;
    public static FlapFrame Sample(char target, double elapsed, double delay = 0)
    {
        target = char.ToUpperInvariant(target);
        var index = Characters.IndexOf(target);
        var local = elapsed - delay;
        if (index <= 0 || local <= 0) return new(' ', ' ', 0);
        if (local >= index * StepSeconds) return new(target, target, 0);
        var steps = local / StepSeconds;
        var complete = (int)Math.Floor(steps);
        return new(Characters[complete], Characters[complete + 1], (float)(steps - complete));
    }
}

