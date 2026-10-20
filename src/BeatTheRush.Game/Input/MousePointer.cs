#if !IOS
using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

/// <summary>Buffers all desktop button transitions, including a complete click between updates.</summary>
internal sealed class MousePointer(GameWindow window) : IDisposable
{
    private readonly SdlMouseEvents _events = new(window);
    private readonly PointerClick _click = new();
    private readonly Queue<Vector2> _ready = new();
    private bool _down;
    public Vector2? Poll(CanvasViewport viewport)
    {
        var bounds = window.ClientBounds;
        while (_events.TryRead(out var item))
        {
            if (item.Kind == MouseEventKind.Press) _down = true;
            else if (item.Kind == MouseEventKind.Release) _down = false;
            var point = viewport.FromClient(item.Position, bounds.Width, bounds.Height);
            if (_click.Update(point, _down) is { } tapped) _ready.Enqueue(tapped);
        }
        return _ready.TryDequeue(out var result) ? result : null;
    }
    public void Clear() { _events.Clear(); _ready.Clear(); _click.Clear(); _down = false; }
    public void Dispose() => _events.Dispose();
}
#endif

