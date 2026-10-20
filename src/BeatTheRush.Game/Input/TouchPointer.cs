using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Input.Touch;
namespace BeatTheRush.Game;

internal sealed class TouchPointer
{
    private Vector2? _start;
    private int? _id;
    private bool _cancelled;
    public Vector2? Poll(CanvasViewport viewport)
    {
        var touches = TouchPanel.GetState();
        if (touches.Count > 1) _cancelled = true;
        Vector2? tap = null;
        foreach (var touch in touches)
        {
            var point = viewport.ToCanvas(touch.Position);
            if (touch.State == TouchLocationState.Pressed && _id is null)
            { _id = touch.Id; _start = point; _cancelled = touches.Count != 1; }
            if (touch.Id != _id) continue;
            if (_start is { } start && Vector2.Distance(start, point) > 18) _cancelled = true;
            if (touch.State == TouchLocationState.Released)
            {
                if (!_cancelled && _start is not null) tap = point;
                _id = null; _start = null;
            }
        }
        if (touches.Count == 0 && _id is not null) Clear();
        return tap;
    }
    public void Clear() { _start = null; _id = null; _cancelled = false; }
}

