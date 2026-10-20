using BeatTheRush.Game;
using Foundation;
using UIKit;

namespace BeatTheRush.iOS;

[Register("AppDelegate")]
public sealed class AppDelegate : UIApplicationDelegate
{
    private RailwayGame? _game;

    public static void Main(string[] args) => UIApplication.Main(args, null, typeof(AppDelegate));

    public override void FinishedLaunching(UIApplication application)
    {
        _game = new RailwayGame { SafeAreaProvider = GetSafeInsets };
        _game.Run();
    }

    private static ScreenInsets GetSafeInsets()
    {
        var window = UIApplication.SharedApplication.ConnectedScenes
            .OfType<UIWindowScene>().SelectMany(scene => scene.Windows)
            .FirstOrDefault(candidate => candidate.IsKeyWindow);
        if (window is null) return default;
        var insets = window.SafeAreaInsets;
        var scale = (float)window.Screen.Scale;
        return new((float)insets.Left * scale, (float)insets.Top * scale,
            (float)insets.Right * scale, (float)insets.Bottom * scale);
    }

    public override void OnResignActivation(UIApplication application) => _game?.Pause();
    public override void DidEnterBackground(UIApplication application) => _game?.Pause();
}
