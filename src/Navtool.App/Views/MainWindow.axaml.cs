using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using Avalonia.Platform.Storage;
using Mapsui;
using Mapsui.UI.Avalonia;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;

namespace Navtool.App.Views;

public partial class MainWindow : Window
{
    private static AppThemeService? _defaultThemeService;
    private static readonly FilePickerFileType GribFileType = new("GRIB forecasts")
    {
        Patterns = ["*.grib", "*.grb", "*.grib2", "*.grb2", "*.gri"],
        MimeTypes = ["application/octet-stream"]
    };

    private readonly AppThemeService _themeService;
    private Navigator? _subscribedNavigator;

    public MainWindow() : this(GetDefaultThemeService())
    {
    }

    public MainWindow(AppThemeService themeService)
    {
        ArgumentNullException.ThrowIfNull(themeService);
        _themeService = themeService;
        AvaloniaXamlLoader.Load(this);
        var themeSelector = this.FindControl<ComboBox>("ThemeSelector")!;
        themeSelector.ItemsSource = AppThemeService.AvailableThemes;
        themeSelector.SelectedItem = AppThemeService.AvailableThemes.Single(
            option => option.Theme == _themeService.SelectedTheme);
        themeSelector.SelectionChanged += OnThemeSelectionChanged;
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
        this.FindControl<ComboBox>("ThemeSelector")!.SelectionChanged -= OnThemeSelectionChanged;
        if (_subscribedNavigator is not null)
        {
            _subscribedNavigator.ViewportChanged -= OnViewportChanged;
        }
    }

    private void OnThemeSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (sender is ComboBox { SelectedItem: AppThemeOption option })
        {
            _themeService.SelectTheme(option.Theme);
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

        // async void event handler: any unhandled exception here would be raised on the
        // UI sync context and crash the app, so guard availability and catch failures.
        var storageProvider = StorageProvider;
        if (storageProvider is null || !storageProvider.CanOpen)
        {
            viewModel.ErrorMessage = "This platform does not support opening files.";
            return;
        }

        try
        {
            var files = await storageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
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
        catch (Exception exception)
        {
            viewModel.ErrorMessage = $"Choosing a GRIB file failed: {exception.Message}";
        }
    }

    private static AppThemeService GetDefaultThemeService()
    {
        if (_defaultThemeService is not null)
        {
            return _defaultThemeService;
        }

        _defaultThemeService = AppThemeService.CreateTransient();
        _defaultThemeService.Initialize(Avalonia.Application.Current ??
            throw new InvalidOperationException("An Avalonia application is required."));
        return _defaultThemeService;
    }
}