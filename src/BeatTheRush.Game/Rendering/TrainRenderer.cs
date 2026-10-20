using BeatTheRush.Core;
using Microsoft.Xna.Framework;
using static BeatTheRush.Game.RenderMath;

namespace BeatTheRush.Game;

internal sealed class TrainRenderer(Painter paint)
{
    private readonly Painter _paint = paint;
    public void Draw(TrainState train, RulesDefinition rules)
    {
        var path = train.Route.Path;
        var head = V(path.Sample(train.Distance).Position);
        // Movement authority is visible as short coloured dashes immediately ahead.
        for (var d = 15; d <= 90; d += 15)
        {
            var a = V(path.Sample(train.Distance + d).Position);
            var b = V(path.Sample(train.Distance + d + 6).Position);
            _paint.Line(a, b, AspectColor(train.Aspect) * 0.65f, 3);
        }
        for (var c = train.Carriages - 1; c >= 0; c--)
        {
            var distance = train.Distance - (c + 0.5) * TrainState.CarLength;
            var pose = path.Sample(distance);
            var center = V(pose.Position);
            var angle = path.SmoothAngle(distance);
            var direction = new Vector2(MathF.Cos(angle), MathF.Sin(angle));
            var tint = train.Express ? new Color(182, 68, 58) : new Color(52, 144, 104);
            _paint.Box(center + new Vector2(1, 2), 36, 21, angle, new Color(15, 24, 22));
            _paint.Box(center, 34, 18, angle, tint);
            _paint.Box(center, 26, 11, angle, train.Express ? new Color(217, 177, 149) : new Color(186, 213, 184));
            _paint.Box(center - direction * 9, 4, 9, angle, new Color(77, 107, 95));
            _paint.Box(center + direction * 9, 4, 9, angle, new Color(77, 107, 95));
            if (c == 0) _paint.Box(center + direction * 15, 2, 12, angle, Palette.Text);
        }
        if (!train.BoardingComplete && Math.Abs(train.Distance - train.Route.Berth) < 0.1)
        {
            _paint.Rounded(head.X - 46, head.Y - 39, 92, 22, 7, Palette.Background);
            _paint.Text("BOARDING", head.X, head.Y - 33, 10, Palette.Green, centered: true);
            _paint.Fill(head.X - 38, head.Y - 15, 76 * (float)Math.Min(1, train.Dwell / rules.DwellSeconds), 2, Palette.Green);
        }
        else if (train.Express)
        {
            _paint.Text("FAST", head.X, head.Y - 30, 10, Palette.Amber, centered: true);
        }
        if (train.StoppedSeconds > 8)
        {
            _paint.Circle(head + new Vector2(0, 28), 9, Palette.Amber * 0.2f);
            _paint.Text("!", head.X, head.Y + 22, 12, Palette.Amber, centered: true);
        }
    }
}


