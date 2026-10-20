using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

internal static class MenuLayout
{
    public static readonly Rectangle PlayButton = new(590, 525, 420, 96);
    public static readonly Rectangle BackButton = new(70, 50, 90, 80);
    public static readonly Rectangle ReturnToStations = new(590, 663, 420, 46);
    public static Rectangle StationCard(int index) => new(70 + index % 2 * 742, 220 + index / 2 * 150, 718, 132);
}

