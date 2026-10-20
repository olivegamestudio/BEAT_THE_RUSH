#if !IOS
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;

internal enum MouseEventKind { Move, Press, Release }
internal readonly record struct MouseEvent(MouseEventKind Kind, Vector2 Position);

/// <summary>Observes this SDL window's events without removing them from MonoGame's queue.</summary>
internal sealed class SdlMouseEvents : IDisposable
{
    private readonly ConcurrentQueue<MouseEvent> _events = new();
    private readonly uint _windowId;
    private readonly EventWatch _watch;
    private bool _disposed;
    public SdlMouseEvents(GameWindow window)
    {
        _windowId = GetWindowId(window.Handle);
        if (_windowId == 0) throw new InvalidOperationException("Cannot bind mouse events to the game window.");
        _watch = Observe;
        AddEventWatch(_watch, IntPtr.Zero);
    }
    public bool TryRead(out MouseEvent item) => _events.TryDequeue(out item);
    public void Clear() { while (_events.TryDequeue(out _)) { } }

    // SDL2's mouse button and motion events share the type/window/x/y offsets.
    // The callback can run off the game thread; only immutable samples enter the queue.
    private int Observe(IntPtr userData, IntPtr nativeEvent)
    {
        var type = Marshal.ReadInt32(nativeEvent);
        if (type is not (0x400 or 0x401 or 0x402) ||
            unchecked((uint)Marshal.ReadInt32(nativeEvent, 8)) != _windowId) return 0;
        if (type != 0x400 && Marshal.ReadByte(nativeEvent, 16) != 1) return 0;
        var kind = type == 0x401 ? MouseEventKind.Press : type == 0x402 ? MouseEventKind.Release : MouseEventKind.Move;
        _events.Enqueue(new(kind, new(Marshal.ReadInt32(nativeEvent, 20), Marshal.ReadInt32(nativeEvent, 24))));
        return 0;
    }
    public void Dispose()
    {
        if (_disposed) return;
        DeleteEventWatch(_watch, IntPtr.Zero);
        GC.KeepAlive(_watch);
        _disposed = true;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int EventWatch(IntPtr userData, IntPtr nativeEvent);
    // SDL2 is already loaded by MonoGame before this component is constructed.
    [DllImport("SDL2.dll", EntryPoint = "SDL_GetWindowID", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint GetWindowId(IntPtr window);
    [DllImport("SDL2.dll", EntryPoint = "SDL_AddEventWatch", CallingConvention = CallingConvention.Cdecl)]
    private static extern void AddEventWatch(EventWatch watch, IntPtr userData);
    [DllImport("SDL2.dll", EntryPoint = "SDL_DelEventWatch", CallingConvention = CallingConvention.Cdecl)]
    private static extern void DeleteEventWatch(EventWatch watch, IntPtr userData);
}
#endif

