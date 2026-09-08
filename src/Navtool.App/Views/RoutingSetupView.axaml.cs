using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Platform.Storage;
using Navtool.App.ViewModels;

namespace Navtool.App.Views;

public partial class RoutingSetupView : UserControl
{
    public RoutingSetupView() => AvaloniaXamlLoader.Load(this);

    private async void OnChooseRegionalSourceClicked(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not RoutingSetupViewModel viewModel) return;
        try
        {
            var storage = TopLevel.GetTopLevel(this)?.StorageProvider;
            if (storage?.CanOpen is not true)
            {
                viewModel.ErrorMessage = "This platform does not support opening files.";
                return;
            }
            var files = await storage.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Choose a GSHHG binary shoreline source",
                AllowMultiple = false,
                FileTypeFilter =
                [
                    new FilePickerFileType("GSHHG binary shoreline") { Patterns = ["*.b", "*.bin"] },
                    FilePickerFileTypes.All
                ]
            });
            if (files.FirstOrDefault()?.TryGetLocalPath() is { } path)
                await viewModel.SelectRegionalSourceAsync(path);
        }
        catch (Exception exception)
        {
            viewModel.ErrorMessage = $"Choosing a regional shoreline failed: {exception.Message}";
        }
    }

    private async void OnImportBoatClicked(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not RoutingSetupViewModel viewModel) return;
        try
        {
            var storage = TopLevel.GetTopLevel(this)?.StorageProvider;
            if (storage?.CanOpen is not true)
            {
                viewModel.ErrorMessage = "This platform does not support opening files.";
                return;
            }
            var files = await storage.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Import boat polar",
                AllowMultiple = false,
                FileTypeFilter =
                [
                    new FilePickerFileType("Boat polars") { Patterns = ["*.pol", "*.csv", "*.txt"] },
                    FilePickerFileTypes.All
                ]
            });
            if (files.FirstOrDefault()?.TryGetLocalPath() is { } path)
                await viewModel.ImportBoatAsync(path);
        }
        catch (Exception exception)
        {
            viewModel.ErrorMessage = $"Choosing a boat polar failed: {exception.Message}";
        }
    }
}
