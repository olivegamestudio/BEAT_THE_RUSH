using BeatTheRush.Core;
using BeatTheRush.Game;
using Microsoft.Xna.Framework;
using Xunit;

namespace BeatTheRush.Game.Tests;

public sealed class PointerTests
{
    [Theory]
    [InlineData(1440, 810, 1440, 810)]
    [InlineData(1920, 1080, 1280, 720)]
    [InlineData(1200, 900, 1200, 900)]
    [InlineData(2560, 1080, 1280, 540)]
    public void MouseClickAtRenderedSignalSelectsItsRoute(int pixelsWide, int pixelsHigh, int clientWide, int clientHigh)
    {
        var sim = new StationSimulation(StationDefinition.Saltash());
        var session = new GameSession(sim);
        session.Handle(GameCommand.StartOrResume);
        var viewport = new CanvasViewport();
        viewport.Update(pixelsWide, pixelsHigh, default);
        var signal = sim.Graph.Routes.Single(r => r.Definition.Id == "west").Definition.Signal;
        var canvasPoint = Vector2.Transform(new(signal.X, signal.Y), GameLayout.WorldToCanvas);
        var destination = viewport.Destination;
        var screen = new Vector2(destination.X + canvasPoint.X / GameLayout.Width * destination.Width,
            destination.Y + canvasPoint.Y / GameLayout.Height * destination.Height);
        var client = new Vector2(screen.X * clientWide / pixelsWide, screen.Y * clientHigh / pixelsHigh);
        var click = new PointerClick();
        var converted = viewport.FromClient(client, clientWide, clientHigh);
        Assert.Null(click.Update(converted, true));
        var released = click.Update(converted, false);
        Assert.NotNull(released);
        SignalTapRouter.Apply(session, released.Value);
        Assert.Equal("west", sim.RequestedRoute);
        SignalTapRouter.Apply(session, released.Value);
        Assert.Null(sim.RequestedRoute);
    }

    [Fact]
    public void MouseCanStartAndPauseWithoutKeyboard()
    {
        var session = new GameSession(new StationSimulation(StationDefinition.Saltash()));
        SignalTapRouter.Apply(session, GameLayout.OverlayButton.Center.ToVector2());
        Assert.False(session.OverlayVisible);
        SignalTapRouter.Apply(session, GameLayout.PauseButton.Center.ToVector2());
        Assert.True(session.Paused);
        SignalTapRouter.Apply(session, GameLayout.OverlayButton.Center.ToVector2());
        Assert.False(session.Paused);
    }

    [Fact]
    public void DragAndFocusLossCancelPendingClick()
    {
        var click = new PointerClick();
        click.Update(new(100, 100), true);
        click.Update(new(200, 100), true);
        Assert.Null(click.Update(new(100, 100), false));
        click.Update(new(100, 100), true);
        click.Clear();
        Assert.Null(click.Update(new(100, 100), false));
    }

    [Fact]
    public void LetterboxClickDoesNotChangeSignal()
    {
        var sim = new StationSimulation(StationDefinition.Saltash());
        var session = new GameSession(sim);
        session.Handle(GameCommand.StartOrResume);
        var viewport = new CanvasViewport();
        viewport.Update(1200, 900, default);
        SignalTapRouter.Apply(session, viewport.FromClient(new(600, 20), 1200, 900));
        Assert.Equal("east", sim.RequestedRoute);
    }
}

