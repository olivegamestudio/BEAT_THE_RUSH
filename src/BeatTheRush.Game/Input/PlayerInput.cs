using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Input;
using Microsoft.Xna.Framework.Input.Touch;
namespace BeatTheRush.Game;

/// <summary>Composes desktop mouse or mobile touch input with buffered keyboard commands.</summary>
internal sealed class PlayerInput : IDisposable
{
    private readonly GameWindow _window;
#if IOS
    private readonly TouchPointer _pointer = new();
#else
    private readonly MousePointer _pointer;
#endif
    private readonly Queue<Keys> _keys = new();
    private readonly HashSet<Keys> _held = new();
    public PlayerInput(GameWindow window)
    {
        _window = window;
#if !IOS
        _pointer = new(window);
        TouchPanel.EnableMouseTouchPoint = false;
        window.KeyDown += OnKeyDown;
        window.KeyUp += OnKeyUp;
#endif
    }
#if !IOS
    private void OnKeyDown(object? sender, InputKeyEventArgs args)
    { if (_held.Add(args.Key)) _keys.Enqueue(args.Key); }
    private void OnKeyUp(object? sender, InputKeyEventArgs args) => _held.Remove(args.Key);
#endif
    public void Clear() { _keys.Clear(); _held.Clear(); _pointer.Clear(); }
    public void Update(AppFlow flow, CanvasViewport viewport)
    {
        while (_keys.TryDequeue(out var key)) ScreenInputRouter.Key(flow, key);
        if (_pointer.Poll(viewport) is { } point) ScreenInputRouter.Tap(flow, point);
    }
    public void Dispose()
    {
#if !IOS
        _pointer.Dispose();
        _window.KeyDown -= OnKeyDown; _window.KeyUp -= OnKeyUp;
#endif
    }
}



