using BeatTheRush.Game;

using var game = new RailwayGame();
if (args.Contains("--smoke-test")) game.SmokeTestFrames = 180;
var screenIndex = Array.IndexOf(args, "--screen");
if (screenIndex >= 0 && screenIndex + 1 < args.Length) game.SmokeScreen = args[screenIndex + 1];
var screenshotIndex = Array.IndexOf(args, "--screenshot");
if (screenshotIndex >= 0 && screenshotIndex + 1 < args.Length) game.ScreenshotPath = args[screenshotIndex + 1];
game.Run();

