using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

/// <summary>Recognises a click without treating a drag or a release from outside as a tap.</summary>
internal sealed class PointerClick
{
    private Vector2? _start;
    private bool _wasDown;
    private bool _cancelled;
    public Vector2? Update(Vector2 position, bool down)
    {
        if (down && !_wasDown) { _start = position; _cancelled = false; }
        if (_start is { } start && Vector2.Distance(start, position) > 18) _cancelled = true;
        Vector2? click = !down && _wasDown && !_cancelled && _start is not null ? position : null;
        if (!down) _start = null;
        _wasDown = down;
        return click;
    }
    public void Clear() { _start = null; _wasDown = false; _cancelled = false; }
}

