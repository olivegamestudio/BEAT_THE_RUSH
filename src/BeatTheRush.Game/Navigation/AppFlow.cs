namespace BeatTheRush.Game;

internal enum AppScreen { Title, Stations, Playing }

/// <summary>Navigation and screen lifetime. Gameplay rules remain in GameSession and its simulation.</summary>
internal sealed class AppFlow
{
    private readonly Dictionary<string, int> _bestStars = new();
    private string? _stationId;
    public AppScreen Screen { get; private set; } = AppScreen.Title;
    public GameSession? Session { get; private set; }
    public MenuRailway MenuRailway { get; } = new();
    public double ScreenElapsed { get; private set; }
    public int SelectedStation { get; private set; }

    public void ShowTitle() { Screen = AppScreen.Title; ScreenElapsed = 0; }
    public void ShowStations()
    {
        RecordStars();
        Session = null; Screen = AppScreen.Stations; ScreenElapsed = 0; SelectedStation = 0;
    }
    public bool SelectStation(string id)
    {
        var entry = StationCatalog.Entries.SingleOrDefault(s => s.Id == id);
        if (entry is not { Available: true }) return false;
        _stationId = id; Session = new(StationCatalog.Create(id));
        Screen = AppScreen.Playing; ScreenElapsed = 0;
        return true;
    }
    public void MoveSelection(int amount) => SelectedStation =
        (SelectedStation + amount + StationCatalog.Entries.Count) % StationCatalog.Entries.Count;
    public int BestStars(string id) => _bestStars.GetValueOrDefault(id);
    public void Pause() => Session?.Pause();
    public void Update(double seconds, bool active)
    {
        if (!active || seconds <= 0) return;
        ScreenElapsed += seconds;
        if (Screen == AppScreen.Title) MenuRailway.Update(seconds);
        else if (Screen == AppScreen.Playing) { Session!.Update(seconds, true); RecordStars(); }
    }
    private void RecordStars()
    {
        if (Session is null || _stationId is null) return;
        if (Session.Simulation.Outcome == BeatTheRush.Core.GameOutcome.Playing) return;
        var stars = Session.Simulation.Stars;
        if (stars > BestStars(_stationId)) _bestStars[_stationId] = stars;
    }
}


