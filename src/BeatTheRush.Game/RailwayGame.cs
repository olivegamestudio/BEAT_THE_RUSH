using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input.Touch;
namespace BeatTheRush.Game;

/// <summary>MonoGame lifecycle adapter. Behaviour lives in composed components.</summary>
public sealed class RailwayGame : Microsoft.Xna.Framework.Game
{
    private readonly GraphicsDeviceManager _graphics;
    private readonly AppFlow _flow = new();
    private readonly CanvasViewport _viewport = new();
    private PlayerInput _input = null!;
    private GameRenderer _renderer = null!;
#if !IOS
    private int _frame;
    public int SmokeTestFrames { get; set; }
    public string SmokeScreen { get; set; } = "saltash";
    public string? ScreenshotPath { get; set; }
#endif
    public Func<ScreenInsets>? SafeAreaProvider { get; init; }
    public RailwayGame()
    {
        _graphics = new(this)
        {
            PreferredBackBufferWidth = 1440, PreferredBackBufferHeight = 810,
            SupportedOrientations = DisplayOrientation.LandscapeLeft | DisplayOrientation.LandscapeRight,
            SynchronizeWithVerticalRetrace = true, GraphicsProfile = GraphicsProfile.Reach
        };
#if IOS
        _graphics.IsFullScreen = true;
#else
        Window.AllowUserResizing = true;
        Window.Title = "Beat the Rush";
        IsMouseVisible = true;
#endif
        IsFixedTimeStep = true;
        TargetElapsedTime = TimeSpan.FromSeconds(1.0 / 60);
        MaxElapsedTime = TimeSpan.FromSeconds(0.25);
        Deactivated += (_, _) => { Pause(); _input?.Clear(); };
    }
    public void Pause() => _flow.Pause();
    protected override void LoadContent()
    {
        _input = new(Window); _renderer = new(GraphicsDevice);
#if !IOS
        if (SmokeTestFrames > 0)
        {
            if (SmokeScreen == "stations") _flow.ShowStations();
            else if (SmokeScreen == "saltash") { _flow.SelectStation("saltash"); _flow.Session!.Handle(GameCommand.StartOrResume); }
        }
#endif
        base.LoadContent();
    }
    protected override void Update(GameTime gameTime)
    {
        var viewport = GraphicsDevice.Viewport;
        _viewport.Update(viewport.Width, viewport.Height, SafeAreaProvider?.Invoke() ?? default);
        TouchPanel.DisplayWidth = viewport.Width; TouchPanel.DisplayHeight = viewport.Height;
        if (IsActive) _input.Update(_flow, _viewport);
        else _input.Clear();
        _flow.Update(gameTime.ElapsedGameTime.TotalSeconds, IsActive);
        base.Update(gameTime);
    }
    protected override void Draw(GameTime gameTime)
    {
        _renderer.Draw(_flow, _viewport);
#if !IOS
        if (SmokeTestFrames > 0 && ++_frame >= SmokeTestFrames)
        {
            if (ScreenshotPath is { } path) _renderer.SaveScreenshot(path);
            Exit();
        }
#endif
        base.Draw(gameTime);
    }
    protected override void UnloadContent()
    { _input?.Dispose(); _renderer?.Dispose(); base.UnloadContent(); }
}


