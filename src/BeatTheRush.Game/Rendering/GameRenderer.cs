using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
namespace BeatTheRush.Game;

/// <summary>Owns graphics resources and composes dedicated screen and scene renderers.</summary>
internal sealed class GameRenderer : IDisposable
{
    private readonly GraphicsDevice _device;
    private readonly SpriteBatch _batch;
    private readonly Painter _paint;
    private readonly RenderTarget2D _canvas;
    private readonly RasterizerState _clip = new() { ScissorTestEnable = true };
    private readonly StationRenderer _station;
    private readonly HudRenderer _hud;
    private readonly OverlayRenderer _overlay;
    private readonly TitleScreenRenderer _title;
    private readonly StationSelectRenderer _selection;
    public GameRenderer(GraphicsDevice device)
    {
        _device = device; _batch = new(device); _paint = new(device, _batch);
        _canvas = new(device, GameLayout.Width, GameLayout.Height, false, SurfaceFormat.Color, DepthFormat.None);
        _station = new(_paint); _hud = new(_paint); _overlay = new(_paint);
        _title = new(_paint); _selection = new(_paint);
    }
    public void Draw(AppFlow flow, CanvasViewport viewport)
    {
        _device.SetRenderTarget(_canvas);
        _device.Clear(Palette.Background);
        if (flow.Screen == AppScreen.Playing) DrawStation(flow.Session!, flow.ScreenElapsed);
        else
        {
            _batch.Begin(samplerState: SamplerState.LinearClamp);
            if (flow.Screen == AppScreen.Title) _title.Draw(flow);
            else _selection.Draw(flow);
            _batch.End();
        }
        _device.SetRenderTarget(null);
        _device.Clear(Palette.Background);
        _batch.Begin(samplerState: SamplerState.LinearClamp);
        _batch.Draw(_canvas, viewport.Destination, Color.White);
        _batch.End();
    }
    private void DrawStation(GameSession session, double animationTime)
    {
        _batch.Begin(samplerState: SamplerState.LinearClamp);
        _hud.Draw(session.Simulation);
        var bounds = GameLayout.MapBounds;
        _paint.Rounded(bounds.X, bounds.Y, bounds.Width, bounds.Height, 20, new Color(28, 44, 39));
        _batch.End();
        _device.ScissorRectangle = new(bounds.X + 2, bounds.Y + 2, bounds.Width - 4, bounds.Height - 4);
        _batch.Begin(samplerState: SamplerState.LinearClamp, rasterizerState: _clip, transformMatrix: GameLayout.WorldToCanvas);
        _station.Draw(session.Simulation, animationTime);
        _batch.End();
        if (!session.OverlayVisible) return;
        _batch.Begin(samplerState: SamplerState.LinearClamp);
        _overlay.Draw(session);
        _batch.End();
    }
    public void SaveScreenshot(string path)
    {
        using var stream = File.Create(path);
        _canvas.SaveAsPng(stream, GameLayout.Width, GameLayout.Height);
    }
    public void Dispose() { _paint.Dispose(); _canvas.Dispose(); _batch.Dispose(); _clip.Dispose(); }
}

