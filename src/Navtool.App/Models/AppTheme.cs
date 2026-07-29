namespace Navtool.App.Models;

public enum AppTheme
{
    Light,
    Dark,
    KindOfBlue
}

public sealed record AppThemeOption(AppTheme Theme, string DisplayName)
{
    public override string ToString() => DisplayName;
}
