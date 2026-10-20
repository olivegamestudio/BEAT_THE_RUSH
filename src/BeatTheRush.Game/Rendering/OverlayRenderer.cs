using BeatTheRush.Core;
using Microsoft.Xna.Framework;
using static BeatTheRush.Game.RenderMath;

namespace BeatTheRush.Game;

internal sealed class OverlayRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    public void Draw(GameSession session)
    {
        _paint.Fill(0, 0, GameLayout.Width, GameLayout.Height, new Color(5, 14, 16) * 0.84f);
        _paint.Rounded(360, 194, 880, 535, 24, Palette.Border);
        _paint.Rounded(362, 196, 876, 531, 22, Palette.Background);
        var outcome = session.Simulation.Outcome;
        var title = !session.Started ? "WORK THE BRIDGE" : outcome == GameOutcome.Won ? "A CLEAR ROAD" :
            outcome == GameOutcome.Lost ? "PLATFORM OVERWHELMED" : "TAKE A BREATHER";
        var eyebrow = !session.Started ? "SALTASH / YOUR FIRST SHIFT" : outcome == GameOutcome.Playing ? "SHIFT PAUSED" : "SHIFT COMPLETE";
        _paint.Text(eyebrow, 800, 236, 15, Palette.Amber, centered: true);
        _paint.Text(title, 800, 286, 34, Palette.Text, centered: true);
        if (!session.Started)
        {
            _paint.Text("The trains drive themselves. You give them the road.", 800, 361, 19, Palette.Muted, centered: true);
            _paint.Text("01", 430, 423, 18, Palette.Green);
            _paint.Text("Clear east or west. Only one train can use the bridge.", 477, 424, 16, Palette.Text);
            _paint.Text("02", 430, 468, 18, Palette.Green);
            _paint.Text("Let locals and fast trains board at both platforms.", 477, 469, 16, Palette.Text);
            _paint.Text("03", 430, 513, 18, Palette.Green);
            _paint.Text("Board 30 people before a platform stays full too long.", 477, 514, 16, Palette.Text);
        }
        else if (outcome != GameOutcome.Playing)
        {
            _paint.Text($"{(int)session.Simulation.Boarded} / {session.Simulation.Definition.Rules.Goal} PEOPLE BOARDED", 800, 374, 24,
                outcome == GameOutcome.Won ? Palette.Green : Palette.Red, centered: true);
            var stars = string.Join("   ", Enumerable.Range(0, 3).Select(i => i < session.Simulation.Stars ? "*" : "-"));
            _paint.Text(stars, 800, 435, 40, Palette.Amber, centered: true);
            _paint.Text(outcome == GameOutcome.Won ? "Both sides moving. A good shift on the Tamar." :
                "Give both platforms a regular service. Try another shift.", 800, 515, 17, Palette.Muted, centered: true);
        }
        else
        {
            _paint.Text("Your trains and passengers are waiting.", 800, 397, 22, Palette.Muted, centered: true);
            _paint.Text("Resume when you are ready to work the box.", 800, 449, 18, Palette.Text, centered: true);
        }
        _paint.Rounded(590, 570, 420, 80, 14, Palette.Green);
        var button = !session.Started ? "START SHIFT" : outcome == GameOutcome.Playing ? "RESUME SHIFT" : "ANOTHER SHIFT";
        _paint.Text(button, 800, 599, 22, Palette.Background, centered: true);
        var back = MenuLayout.ReturnToStations;
        _paint.Rounded(back.X, back.Y, back.Width, back.Height, 10, Palette.Panel);
        _paint.Text("STATIONS", back.Center.X, back.Y + 16, 14, Palette.Muted, centered: true);
    }
}


