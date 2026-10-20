using BeatTheRush.Core;
using Microsoft.Xna.Framework;
namespace BeatTheRush.Game;
internal static class RenderMath
{
    public static Vector2 V(System.Numerics.Vector2 p) => new(p.X, p.Y);
    public static Color AspectColor(SignalAspect aspect) => aspect switch
    {
        SignalAspect.Green => Palette.Green, SignalAspect.Amber => Palette.Amber, _ => Palette.Red
    };
}

