using BeatTheRush.Core;
using Microsoft.Xna.Framework;
using static BeatTheRush.Game.RenderMath;

namespace BeatTheRush.Game;

internal sealed class HudRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    public void Draw(StationSimulation simulation)
    {
        for (var i = 0; i < 3; i++) _paint.Line(new(72 + i * 9, 40), new(82 + i * 9, 57), Palette.Amber, 4);
        _paint.Text("BEAT THE RUSH", 118, 39, 20, Palette.Text);
        _paint.Text(simulation.Definition.Name, 70, 82, 49, Palette.Text);
        _paint.Text(simulation.Definition.Subtitle, 72, 145, 15, Palette.Muted);
        _paint.Text(((int)(simulation.Boarded + 0.0001)).ToString("00"), 1085, 63, 58, Palette.Green);
        _paint.Text("/ " + simulation.Definition.Rules.Goal, 1190, 83, 28, Palette.Muted);
        _paint.Text("PEOPLE BOARDED", 1088, 137, 14, Palette.Muted);
        _paint.Text(simulation.Trains.Count.ToString("00"), 1324, 81, 31, Palette.Text);
        _paint.Text("TRAINS", 1324, 137, 14, Palette.Muted);
        _paint.Rounded(1430, 52, 100, 80, 16, Palette.Panel);
        _paint.Fill(1469, 78, 6, 27, Palette.Text);
        _paint.Fill(1485, 78, 6, 27, Palette.Text);
    }
}


