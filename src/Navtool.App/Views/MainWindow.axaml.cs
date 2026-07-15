using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using Avalonia.Platform.Storage;
using Mapsui;
using Mapsui.UI.Avalonia;
using Navtool.App.ViewModels;

namespace Navtool.App.Views;

public partial class MainWindow : Window
{
    private static readonly FilePickerFileType GribFileType = new("GRIB forecasts")
    {
        Patterns = ["*.grib", "*.grb", "*.grib2", "*.grb2", "*.gri"],
        MimeTypes = ["application/octet-stream"]
    };

    private Navigator? _subscribedNavigator;

    public MainWindow()
    {
        AvaloniaXamlLoader.Load(this);
        this.FindControl<MapControl>("MapView")!.MapTapped += OnMapTapped;
        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    private void OnLoaded(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (DataContext is not MainViewModel viewModel)
        {
            return;
        }

        _subscribedNavigator = viewModel.Map.Navigator;
        _subscribedNavigator.ViewportChanged += OnViewportChanged;
        viewModel.RequestWeatherRefreshFromViewport();
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        if (_subscribedNavigator is not null)
        {
            _subscribedNavigator.ViewportChanged -= OnViewportChanged;
        }
    }

    private void OnViewportChanged(object? sender, ViewportChangedEventArgs e)
    {
        if (DataContext is MainViewModel viewModel)
        {
            viewModel.RequestWeatherRefreshFromViewport();
        }
    }

    private void OnMapTapped(object? sender, MapEventArgs e)
    {
        if (DataContext is MainViewModel viewModel)
        {
            viewModel.HandleMapClick(e.WorldPosition, e.ScreenPosition);
            e.Handled = true;
        }
    }

    private async void OnChooseGribFileClicked(
        object? sender,
        Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (DataContext is not MainViewModel viewModel)
        {
            return;
        }

        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Choose an existing GRIB forecast",
            AllowMultiple = false,
            FileTypeFilter = [GribFileType, FilePickerFileTypes.All]
        });
        var path = files.FirstOrDefault()?.TryGetLocalPath();
        if (!string.IsNullOrWhiteSpace(path))
        {
            await viewModel.SelectLocalGribAsync(path);
        }
    }
}