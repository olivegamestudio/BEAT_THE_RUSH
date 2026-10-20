using BeatTheRush.Game;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Input;
using Xunit;
namespace BeatTheRush.Game.Tests;

public sealed class NavigationTests
{
    [Fact]
    public void MouseFlowReachesSaltashAndReturnsToStationBoards()
    {
        var flow = new AppFlow();
        Assert.Equal(AppScreen.Title, flow.Screen);
        ScreenInputRouter.Tap(flow, MenuLayout.PlayButton.Center.ToVector2());
        Assert.Equal(AppScreen.Stations, flow.Screen);
        ScreenInputRouter.Tap(flow, MenuLayout.StationCard(0).Center.ToVector2());
        Assert.Equal(AppScreen.Playing, flow.Screen);
        Assert.True(flow.Session!.OverlayVisible);
        ScreenInputRouter.Tap(flow, GameLayout.OverlayButton.Center.ToVector2());
        Assert.False(flow.Session.OverlayVisible);
        ScreenInputRouter.Tap(flow, GameLayout.PauseButton.Center.ToVector2());
        ScreenInputRouter.Tap(flow, MenuLayout.ReturnToStations.Center.ToVector2());
        Assert.Equal(AppScreen.Stations, flow.Screen);
        Assert.Null(flow.Session);
        ScreenInputRouter.Tap(flow, MenuLayout.BackButton.Center.ToVector2());
        Assert.Equal(AppScreen.Title, flow.Screen);
    }

    [Fact]
    public void UnavailableStationCannotStartAndMenuDoesNotAdvanceGame()
    {
        var flow = new AppFlow();
        flow.ShowStations();
        ScreenInputRouter.Tap(flow, MenuLayout.StationCard(1).Center.ToVector2());
        Assert.Equal(AppScreen.Stations, flow.Screen);
        Assert.Null(flow.Session);
        flow.SelectStation("saltash");
        flow.Update(1.0 / 60, true);
        Assert.Equal(0, flow.Session!.Simulation.Elapsed);
    }

    [Fact]
    public void KeyboardNavigationKeepsMenusSeparateFromGameplayCommands()
    {
        var flow = new AppFlow();
        ScreenInputRouter.Key(flow, Keys.Enter);
        ScreenInputRouter.Key(flow, Keys.Right);
        ScreenInputRouter.Key(flow, Keys.Enter);
        Assert.Equal(AppScreen.Stations, flow.Screen);
        ScreenInputRouter.Key(flow, Keys.Left);
        ScreenInputRouter.Key(flow, Keys.Enter);
        Assert.Equal(AppScreen.Playing, flow.Screen);
        ScreenInputRouter.Key(flow, Keys.Enter);
        Assert.True(flow.Session!.Started);
        flow.Pause();
        Assert.True(flow.Session.Paused);
    }

    [Fact]
    public void SplitFlapStartsBlankCyclesAndSettlesWithColumnDelay()
    {
        Assert.Equal(new FlapFrame(' ', ' ', 0), SplitFlapAnimation.Sample('B', 0));
        var half = SplitFlapAnimation.Sample('B', 0.025);
        Assert.Equal(' ', half.Leaving); Assert.Equal('A', half.Arriving);
        Assert.Equal(0.5f, half.Progress, 4);
        Assert.Equal(new FlapFrame('B', 'B', 0), SplitFlapAnimation.Sample('b', 1));
        Assert.Equal(new FlapFrame(' ', ' ', 0), SplitFlapAnimation.Sample('B', 0.1, 0.2));
        Assert.Equal(new FlapFrame(' ', ' ', 0), SplitFlapAnimation.Sample('#', 9999));
    }

    [Fact]
    public void MenuTrainsHoldAtTheirOwnRedSignals()
    {
        var railway = new MenuRailway();
        for (var i = 0; i < 1200; i++)
        {
            var before = railway.Trains.Select(t => t.Distance).ToArray();
            railway.Update(1.0 / 60);
            for (var t = 0; t < railway.Trains.Count; t++)
                foreach (var signal in railway.Signals.Where(s => s.Path == railway.Trains[t].Path))
                    if (signal.RedAt(railway.Elapsed) && before[t] <= signal.Distance)
                        Assert.True(railway.Trains[t].Distance <= Math.Max(before[t], signal.Distance - 32) + 0.001);
        }
    }
}

