using System.Numerics;
using BeatTheRush.Core;
using Xunit;

namespace BeatTheRush.Core.Tests;

public sealed class SimulationTests
{
    private static StationSimulation Manual() => new(StationDefinition.Saltash(), automaticTraffic: false);
    private static void Run(StationSimulation simulation, double seconds)
    {
        for (var i = 0; i < seconds * 60; i++) simulation.Step(1.0 / 60);
    }

    [Fact]
    public void GraphRejectsMissingNodeAndMissingEdge()
    {
        var definition = StationDefinition.Saltash();
        Assert.Throws<ArgumentException>(() => new TrackGraph(definition with { Nodes = definition.Nodes.Skip(1).ToArray() }));
        Assert.Throws<ArgumentException>(() => new TrackGraph(definition with { Edges = definition.Edges.Skip(1).ToArray() }));
    }

    [Fact]
    public void PathExtrapolatesAtBothEndsForTrainBodies()
    {
        var path = new TrackPath([Vector2.Zero, new Vector2(100, 0)]);
        Assert.Equal(new Vector2(-20, 0), path.Sample(-20).Position);
        Assert.InRange(Vector2.Distance(new Vector2(120, 0), path.Sample(120).Position), 0, 0.001f);
    }

    [Fact]
    public void SwitchingDirectionCannotStealAnOccupiedSection()
    {
        var section = new ExclusiveSection();
        Assert.True(section.TryAcquire(1, "east", "east"));
        Assert.False(section.TryAcquire(2, "west", "west"));
        Assert.False(section.Release(2));
        Assert.Equal(1, section.OwnerId);
        Assert.True(section.Release(1));
        Assert.True(section.TryAcquire(2, "west", "west"));
    }

    [Fact]
    public void RedSignalHoldsWestboundBeforeBridge()
    {
        var sim = Manual();
        var train = sim.AddTrain("west", 3);
        Run(sim, 25);
        Assert.Equal(train.Route.Hold, train.Distance, 2);
        Assert.Null(sim.Section.OwnerId);
        Assert.False(train.BoardingComplete);
    }

    [Fact]
    public void ReservationRemainsUntilTailClearsBothThroats()
    {
        var sim = Manual();
        var east = sim.AddTrain("east", 5, distance: sim.Graph.Routes[0].Hold);
        east.BoardingComplete = true;
        sim.Step(1.0 / 60);
        Assert.Equal(east.Id, sim.Section.OwnerId);
        sim.ToggleRoute("west");
        var west = sim.AddTrain("west", 3, distance: sim.Graph.Routes[1].Hold);
        var sawEastNoseExit = false;
        for (var i = 0; i < 2400; i++)
        {
            sim.Step(1.0 / 60);
            if (east.Distance > east.Route.Release && east.Distance - east.Length <= east.Route.Release + 8)
            {
                sawEastNoseExit = true;
                Assert.Equal(east.Id, sim.Section.OwnerId);
                Assert.True(west.Distance <= west.Route.Hold + 0.01);
            }
        }
        Assert.True(sawEastNoseExit);
        Assert.True(west.Distance > west.Route.Hold + 200);
    }

    [Fact]
    public void FollowingPreservesGapWhileLeaderWaitsAtRed()
    {
        var sim = Manual();
        var leader = sim.AddTrain("west", 3, distance: 300);
        var follower = sim.AddTrain("west", 2);
        for (var i = 0; i < 1800; i++)
        {
            sim.Step(1.0 / 60);
            Assert.True(follower.Distance + StationSimulation.FollowGap <= leader.Distance - leader.Length + 0.001);
        }
        Assert.Equal(leader.Route.Hold - leader.Length - StationSimulation.FollowGap, follower.Distance, 2);
    }

    [Fact]
    public void BoardingHonoursCapacityAndDwell()
    {
        var sim = Manual();
        sim.Platforms[0].Waiting = 15;
        var train = sim.AddTrain("east", 2, distance: sim.Graph.Routes[0].Berth);
        Run(sim, 1);
        Assert.False(train.BoardingComplete);
        Assert.Equal(6, train.Load, 4);
        Run(sim, 2);
        Assert.True(train.BoardingComplete);
        Assert.Equal(6, sim.Boarded, 4);
        Assert.Equal(9, sim.Platforms[0].Waiting, 4);
    }

    [Fact]
    public void FullPlatformGetsGraceThenLosesAndFreezes()
    {
        var sim = Manual();
        sim.Platforms[0].Waiting = 16;
        Run(sim, 17);
        Assert.Equal(GameOutcome.Playing, sim.Outcome);
        Run(sim, 2);
        Assert.Equal(GameOutcome.Lost, sim.Outcome);
        var elapsed = sim.Elapsed;
        Run(sim, 5);
        Assert.Equal(elapsed, sim.Elapsed);
    }

    [Fact]
    public void ReachingGoalWins()
    {
        var definition = StationDefinition.Saltash();
        var sim = new StationSimulation(definition with { Rules = definition.Rules with { Goal = 3 } }, automaticTraffic: false);
        sim.AddTrain("east", 3, distance: sim.Graph.Routes[0].Berth);
        Run(sim, 2);
        Assert.Equal(GameOutcome.Won, sim.Outcome);
        Assert.Equal(3, sim.Stars);
    }

    [Fact]
    public void ResetReplaysTheSameSeedAndClearsReservations()
    {
        var sim = new StationSimulation(StationDefinition.Saltash());
        Run(sim, 45);
        var signature = Signature(sim);
        sim.ToggleRoute("west");
        sim.Reset();
        Run(sim, 45);
        Assert.Equal(signature, Signature(sim));
    }

    [Fact]
    public void SaltashCanBeCompletedAndNeverHasTwoTrainsInProtectedSection()
    {
        var sim = new StationSimulation(StationDefinition.Saltash());
        var sawEast = false; var sawWest = false;
        for (var i = 0; i < 60 * 360 && sim.Outcome == GameOutcome.Playing; i++)
        {
            if (i % 600 == 0) sim.ToggleRoute(sim.RequestedRoute == "east" ? "west" : "east");
            sim.Step(1.0 / 60);
            var occupying = sim.Trains.Where(t => t.Distance > t.Route.Hold + 0.01 &&
                t.Distance - t.Length <= t.Route.Release + 8).ToArray();
            Assert.True(occupying.Length <= 1, "Protected bridge and throats must have one owner.");
            foreach (var t in occupying) Assert.Equal(t.Id, sim.Section.OwnerId);
            sawEast |= sim.Section.OwnerRouteId == "east"; sawWest |= sim.Section.OwnerRouteId == "west";
        }
        Assert.True(sawEast && sawWest);
        Assert.Equal(GameOutcome.Won, sim.Outcome);
    }

    private static string Signature(StationSimulation sim) => string.Join("|",
        sim.Trains.Select(t => $"{t.Id}:{t.Route.Definition.Id}:{t.Distance:R}:{t.Load:R}")) +
        $"/{sim.Boarded:R}/{sim.Platforms[0].Waiting:R}/{sim.Platforms[1].Waiting:R}";
}


