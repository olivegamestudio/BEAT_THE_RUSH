using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

internal sealed class StationSelectRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    private readonly SplitFlapRenderer _flaps = new(paint);
    public void Draw(AppFlow flow)
    {
        var back = MenuLayout.BackButton;
        _paint.Rounded(back.X, back.Y, back.Width, back.Height, 16, Palette.Panel);
        _paint.Line(new(122, 76), new(108, 90), Palette.Text, 3);
        _paint.Line(new(108, 90), new(122, 104), Palette.Text, 3);
        _paint.Text("BEAT THE RUSH", 188, 54, 18, Palette.Muted);
        _paint.Text("PICK YOUR STATION", 188, 97, 34, Palette.Text);
        _paint.Text("THE SIGNAL BOX IS YOURS", 1530 - _paint.Measure("THE SIGNAL BOX IS YOURS", 13), 111, 13, Palette.Muted);
        _paint.Line(new(70, 175), new(1530, 175), Palette.Border, 1);
        for (var i = 0; i < StationCatalog.Entries.Count; i++) DrawCard(flow, i);
    }
    private void DrawCard(AppFlow flow, int index)
    {
        var entry = StationCatalog.Entries[index]; var card = MenuLayout.StationCard(index);
        var ink = entry.Available ? Palette.Text : Palette.Muted * 0.65f;
        var selected = index == flow.SelectedStation;
        _paint.Rounded(card.X, card.Y, card.Width, card.Height, 12,
            entry.Available ? Palette.Amber * (selected ? 0.6f : 0.25f) : Palette.Border * 0.6f);
        _paint.Rounded(card.X + 2, card.Y + 2, card.Width - 4, card.Height - 4, 10, new Color(15, 25, 27));
        _paint.Circle(new(card.X + 24, card.Y + 22), 4, entry.Available ? Palette.Green : Palette.Muted * 0.4f);
        _paint.Text($"STATION {entry.Number:00}", card.X + 39, card.Y + 16, 11, Palette.Muted);
        var stars = flow.BestStars(entry.Id);
        if (stars > 0) _paint.Text(new string('*', stars), card.Right - 80, card.Y + 15, 14, Palette.Amber);
        var elapsed = entry.Available ? flow.ScreenElapsed : 9999;
        var delay = index * SplitFlapAnimation.TileDelay;
        _flaps.Line(entry.BoardName, 15, new(card.X + 24, card.Y + 40), new(38, 44), elapsed, delay, ink);
        _flaps.Line(entry.Region, 15, new(card.X + 24, card.Y + 99), new(13, 19), elapsed, delay + 0.25, Palette.Muted, 3);
        var status = !entry.Available ? "NOT IN SERVICE" : stars > 0 ? "CLEARED" : "ON TIME";
        _flaps.Line(status, 14, new(card.X + 460, card.Y + 99), new(13, 19), elapsed, delay + 0.4,
            entry.Available ? Palette.Green : Palette.Muted * 0.55f, 3);
    }
}

