using BeatTheRush.Core;
namespace BeatTheRush.Game;

internal enum GameCommand { StartOrResume, Pause, Restart, East, West, Hold }
internal sealed class GameSession(StationSimulation simulation)
{
    public StationSimulation Simulation { get; } = simulation;
    public bool Started { get; private set; }
    public bool Paused { get; private set; }
    public bool OverlayVisible => !Started || Paused || Simulation.Outcome != GameOutcome.Playing;
    public void Pause() { if (Started) Paused = true; }
    public void Handle(GameCommand command)
    {
        switch (command)
        {
            case GameCommand.StartOrResume:
                if (Simulation.Outcome != GameOutcome.Playing) Simulation.Reset();
                Started = true; Paused = false; break;
            case GameCommand.Restart:
                Simulation.Reset(); Started = true; Paused = false; break;
            case GameCommand.Pause:
                if (Started && Simulation.Outcome == GameOutcome.Playing) Paused = !Paused;
                break;
            case GameCommand.East when !OverlayVisible: Simulation.ToggleRoute("east"); break;
            case GameCommand.West when !OverlayVisible: Simulation.ToggleRoute("west"); break;
            case GameCommand.Hold when !OverlayVisible: Simulation.HoldAll(); break;
        }
    }
    public void Update(double seconds, bool active)
    {
        if (!OverlayVisible && active && seconds > 0) Simulation.Step(seconds);
    }
}

