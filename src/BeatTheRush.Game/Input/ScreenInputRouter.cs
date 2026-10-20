using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Input;
namespace BeatTheRush.Game;

internal static class ScreenInputRouter
{
    public static void Tap(AppFlow flow, Vector2 point)
    {
        switch (flow.Screen)
        {
            case AppScreen.Title:
                if (MenuLayout.PlayButton.Contains(point)) flow.ShowStations();
                break;
            case AppScreen.Stations:
                if (MenuLayout.BackButton.Contains(point)) { flow.ShowTitle(); return; }
                for (var i = 0; i < StationCatalog.Entries.Count; i++)
                    if (MenuLayout.StationCard(i).Contains(point)) { flow.SelectStation(StationCatalog.Entries[i].Id); return; }
                break;
            case AppScreen.Playing:
                if (flow.Session!.OverlayVisible && MenuLayout.ReturnToStations.Contains(point)) flow.ShowStations();
                else SignalTapRouter.Apply(flow.Session, point);
                break;
        }
    }
    public static void Key(AppFlow flow, Keys key)
    {
        if (flow.Screen == AppScreen.Title)
        {
            if (key is Keys.Enter or Keys.Space) flow.ShowStations();
            return;
        }
        if (flow.Screen == AppScreen.Stations)
        {
            switch (key)
            {
                case Keys.Escape or Keys.Back: flow.ShowTitle(); break;
                case Keys.Left: flow.MoveSelection(-1); break;
                case Keys.Right: flow.MoveSelection(1); break;
                case Keys.Up: flow.MoveSelection(-2); break;
                case Keys.Down: flow.MoveSelection(2); break;
                case Keys.Enter: flow.SelectStation(StationCatalog.Entries[flow.SelectedStation].Id); break;
            }
            return;
        }
        var command = key switch
        {
            Keys.Enter => GameCommand.StartOrResume,
            Keys.Space or Keys.Escape => GameCommand.Pause,
            Keys.R => GameCommand.Restart, Keys.E => GameCommand.East,
            Keys.W => GameCommand.West, Keys.H => GameCommand.Hold, _ => (GameCommand?)null
        };
        if (command is { } value) flow.Session!.Handle(value);
    }
}

