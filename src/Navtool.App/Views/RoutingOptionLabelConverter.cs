using System.Globalization;
using Avalonia.Data.Converters;
using Navtool.Core;

namespace Navtool.App.Views;

public sealed class RoutingOptionLabelConverter : IValueConverter
{
    public static RoutingOptionLabelConverter Instance { get; } = new();

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => value switch
    {
        RoutingQuality.NativeFast => "Fast",
        RoutingQuality.NativeBalanced => "Balanced",
        RoutingQuality.NativeAccurate => "Accurate",
        ForecastRefreshPolicy.PreferCache => "Reuse a covering cached run",
        ForecastRefreshPolicy.LatestAvailable => "Require the newest published run",
        RoutingLandSource.NaturalEarth => "Natural Earth (bundled)",
        RoutingLandSource.OpenStreetMap => "OpenStreetMap",
        RoutingLandSource.RegionalGshhg => "Regional GSHHG",
        RoutingLandSource.None => "No coastline source",
        _ => value?.ToString() ?? string.Empty
    };

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException("Routing option labels are display-only.");
}
