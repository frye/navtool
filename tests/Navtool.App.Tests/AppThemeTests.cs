using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Presenters;
using Avalonia.Controls.Primitives;
using Avalonia.Headless.XUnit;
using Avalonia.LogicalTree;
using Avalonia.Media;
using Avalonia.Styling;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.App.Views;

namespace Navtool.App.Tests;

public sealed class AppThemeTests
{
    [AvaloniaFact]
    public void ThemeSelectionUpdatesTheOpenWindowAndEndpointToolStates()
    {
        var service = AppThemeService.CreateTransient();
        service.Initialize(Application.Current!);
        var viewModel = CreateViewModel();
        viewModel.IsInspectingLocalGrib = true;
        var window = new MainWindow(service)
        {
            DataContext = viewModel
        };

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            var selector = Assert.IsType<ComboBox>(window.FindControl<ComboBox>("ThemeSelector"));
            var startButton = Assert.IsType<ToggleButton>(
                window.FindControl<ToggleButton>("SetStartButton"));
            var destinationButton = Assert.IsType<ToggleButton>(
                window.FindControl<ToggleButton>("SetDestinationButton"));
            var calculateButton = Assert.IsType<Button>(
                window.FindControl<Button>("CalculateRoutesButton"));
            var cancelButton = Assert.IsType<Button>(
                window.FindControl<Button>("CancelButton"));

            Assert.Equal("Light", Assert.IsType<AppThemeOption>(selector.SelectedItem).DisplayName);
            Assert.IsAssignableFrom<ISolidColorBrush>(window.Background);
            Assert.False(viewModel.CalculateCommand.CanExecute(null));
            Assert.False(calculateButton.IsEffectivelyEnabled);
            Assert.Equal(
                Avalonia.Layout.HorizontalAlignment.Center,
                cancelButton.HorizontalContentAlignment);
            Assert.Equal(
                Avalonia.Layout.VerticalAlignment.Center,
                cancelButton.VerticalContentAlignment);

            foreach (var option in AppThemeService.AvailableThemes)
            {
                selector.SelectedItem = option;

                Assert.Equal(option.Theme, service.SelectedTheme);
                Assert.Equal(
                    option.Theme == AppTheme.Light ? ThemeVariant.Light : ThemeVariant.Dark,
                    Application.Current!.RequestedThemeVariant);
                Assert.IsAssignableFrom<ISolidColorBrush>(window.Background);
                Assert.Equal(
                    FindColorResource("DisabledBackgroundColor"),
                    GetPresenterBackground(calculateButton));
            }

            viewModel.SetStartCommand.Execute(null);
            Assert.True(startButton.IsChecked);
            Assert.False(destinationButton.IsChecked);
            Assert.Equal(
                FindColorResource("ActiveToolBackgroundColor"),
                GetPresenterBackground(startButton));

            viewModel.SetDestinationCommand.Execute(null);
            Assert.False(startButton.IsChecked);
            Assert.True(destinationButton.IsChecked);
            Assert.Equal(
                FindColorResource("ActiveToolBackgroundColor"),
                GetPresenterBackground(destinationButton));
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void EachThemeProvidesReadableSemanticButtonAndTextPairs()
    {
        var service = AppThemeService.CreateTransient();
        service.Initialize(Application.Current!);

        foreach (var option in AppThemeService.AvailableThemes)
        {
            service.SelectTheme(option.Theme);

            AssertContrast("TextPrimaryColor", "WindowBackgroundColor", 4.5);
            AssertContrast("TextMutedColor", "SurfaceColor", 4.5);
            AssertContrast("AccentTextColor", "AccentColor", 4.5);
            AssertContrast("AccentTextColor", "AccentHoverColor", 4.5);
            AssertContrast("AccentTextColor", "AccentPressedColor", 4.5);
            AssertContrast("ActiveToolTextColor", "ActiveToolBackgroundColor", 4.5);
            AssertContrast("TextPrimaryColor", "SurfaceRaisedColor", 4.5);
            AssertContrast("TextPrimaryColor", "ControlHoverColor", 4.5);
            AssertContrast("TextPrimaryColor", "ControlPressedColor", 4.5);
            AssertContrast("DisabledTextColor", "DisabledBackgroundColor", 4.5);

            foreach (var key in new[]
                     {
                         "ControlHoverColor",
                         "ControlPressedColor",
                         "DisabledBackgroundColor",
                         "DisabledTextColor",
                         "FocusColor",
                         "DangerTextColor",
                         "WarningTextColor"
                     })
            {
                Assert.IsType<Color>(FindResource(key));
            }
        }
    }

    [AvaloniaFact]
    public void PlanningInputsUseSemanticColorsInEveryTheme()
    {
        var service = AppThemeService.CreateTransient();
        service.Initialize(Application.Current!);
        var window = new MainWindow(service)
        {
            DataContext = CreateViewModel()
        };

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            Dispatcher.UIThread.RunJobs();

            foreach (var option in AppThemeService.AvailableThemes)
            {
                service.SelectTheme(option.Theme);
                var enabledForeground = FindColorResource("TextPrimaryColor");
                var enabledBackground = FindColorResource("SurfaceRaisedColor");
                var disabledForeground = FindColorResource("DisabledTextColor");
                var disabledBackground = FindColorResource("DisabledBackgroundColor");
                var inputs = window.GetLogicalDescendants()
                    .OfType<TemplatedControl>()
                    .Where(control =>
                        control is TextBox or ComboBox or DatePicker or TimePicker or NumericUpDown)
                    .ToArray();

                Assert.NotEmpty(inputs);
                Assert.Contains(inputs, control => control is TextBox);
                Assert.Contains(inputs, control => control is ComboBox);
                Assert.Contains(inputs, control => control is DatePicker);
                Assert.Contains(inputs, control => control is TimePicker);
                Assert.Contains(inputs, control => control is NumericUpDown);
                Assert.All(inputs, input =>
                {
                    var expectedForeground = input.IsEffectivelyEnabled
                        ? enabledForeground
                        : disabledForeground;
                    var expectedBackground = input.IsEffectivelyEnabled
                        ? enabledBackground
                        : disabledBackground;
                    Assert.Equal(
                        expectedForeground,
                        Assert.IsAssignableFrom<ISolidColorBrush>(input.Foreground).Color);
                    Assert.Equal(
                        expectedBackground,
                        Assert.IsAssignableFrom<ISolidColorBrush>(input.Background).Color);
                });
            }
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void FluentControlStatesUseSemanticColorsInEveryTheme()
    {
        var service = AppThemeService.CreateTransient();
        service.Initialize(Application.Current!);
        var window = new MainWindow(service)
        {
            DataContext = CreateViewModel()
        };
        var mappings = new (string ResourceKey, string ColorKey)[]
        {
            ("ButtonForeground", "TextPrimaryColor"),
            ("ButtonForegroundPointerOver", "TextPrimaryColor"),
            ("ButtonForegroundPressed", "TextPrimaryColor"),
            ("ButtonForegroundDisabled", "DisabledTextColor"),
            ("ButtonBackground", "SurfaceRaisedColor"),
            ("ButtonBackgroundPointerOver", "ControlHoverColor"),
            ("ButtonBackgroundPressed", "ControlPressedColor"),
            ("ButtonBackgroundDisabled", "DisabledBackgroundColor"),
            ("ToggleButtonForegroundChecked", "ActiveToolTextColor"),
            ("ToggleButtonBackgroundChecked", "ActiveToolBackgroundColor"),
            ("TextControlForeground", "TextPrimaryColor"),
            ("TextControlForegroundDisabled", "DisabledTextColor"),
            ("TextControlPlaceholderForeground", "TextMutedColor"),
            ("ComboBoxForegroundFocused", "TextPrimaryColor"),
            ("ComboBoxForegroundDisabled", "DisabledTextColor"),
            ("ComboBoxItemForegroundSelected", "ActiveToolTextColor"),
            ("ComboBoxItemBackgroundSelected", "ActiveToolBackgroundColor"),
            ("DatePickerButtonForeground", "TextPrimaryColor"),
            ("DatePickerButtonForegroundDisabled", "DisabledTextColor"),
            ("TimePickerButtonForeground", "TextPrimaryColor"),
            ("TimePickerButtonForegroundDisabled", "DisabledTextColor"),
            ("ExpanderHeaderForeground", "TextPrimaryColor"),
            ("ExpanderHeaderForegroundDisabled", "DisabledTextColor"),
            ("ToolTipForeground", "TextPrimaryColor"),
            ("ToolTipBackground", "SurfaceColor"),
            ("MenuFlyoutItemForeground", "TextPrimaryColor"),
            ("MenuFlyoutItemForegroundDisabled", "DisabledTextColor")
        };

        try
        {
            window.Show();

            foreach (var option in AppThemeService.AvailableThemes)
            {
                service.SelectTheme(option.Theme);
                Dispatcher.UIThread.RunJobs();

                foreach (var (resourceKey, colorKey) in mappings)
                {
                    Assert.True(
                        window.TryFindResource(resourceKey, out var value),
                        $"{resourceKey} must be available in {option.DisplayName}.");
                    Assert.Equal(
                        FindColorResource(colorKey),
                        Assert.IsAssignableFrom<ISolidColorBrush>(value).Color);
                }
            }
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void CompactPickerTemplateTextUsesSemanticColorsInEveryTheme()
    {
        var service = AppThemeService.CreateTransient();
        service.Initialize(Application.Current!);
        var window = new MainWindow(service)
        {
            DataContext = CreateViewModel()
        };

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            var datePicker = Assert.IsType<DatePicker>(
                window.FindControl<DatePicker>("DepartureDatePicker"));
            var timePicker = Assert.IsType<TimePicker>(
                window.FindControl<TimePicker>("DepartureTimePicker"));
            datePicker.SelectedDate = new DateTimeOffset(
                2026,
                8,
                4,
                0,
                0,
                0,
                TimeSpan.Zero);
            timePicker.SelectedTime = new TimeSpan(8, 22, 0);
            Dispatcher.UIThread.RunJobs();

            foreach (var option in AppThemeService.AvailableThemes)
            {
                service.SelectTheme(option.Theme);
                Dispatcher.UIThread.RunJobs();
                var expectedForeground = FindColorResource("TextPrimaryColor");

                AssertTemplateTextForeground(
                    datePicker,
                    expectedForeground,
                    "PART_DayTextBlock",
                    "PART_MonthTextBlock",
                    "PART_YearTextBlock");
                AssertTemplateTextForeground(
                    timePicker,
                    expectedForeground,
                    "PART_HourTextBlock",
                    "PART_MinuteTextBlock");
            }
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void ThemePreferenceIsRestoredAndInvalidValuesFallBackToLight()
    {
        var root = CreateTemporaryDirectory();
        try
        {
            var preferenceDirectory = Path.Combine(root, "preferences");
            Directory.CreateDirectory(preferenceDirectory);
            var preferencePath = Path.Combine(preferenceDirectory, "theme.txt");
            File.WriteAllText(preferencePath, AppTheme.KindOfBlue.ToString());

            var restored = new AppThemeService(root);
            restored.Initialize(Application.Current!);

            Assert.Equal(AppTheme.KindOfBlue, restored.SelectedTheme);
            Assert.Equal(ThemeVariant.Dark, Application.Current!.RequestedThemeVariant);

            File.WriteAllText(preferencePath, "unsupported");
            var invalid = new AppThemeService(root);
            invalid.Initialize(Application.Current!);

            Assert.Equal(AppTheme.Light, invalid.SelectedTheme);
            Assert.Equal(ThemeVariant.Light, Application.Current!.RequestedThemeVariant);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [AvaloniaFact]
    public void SelectingThemePersistsItAtomically()
    {
        var root = CreateTemporaryDirectory();
        try
        {
            var service = new AppThemeService(root);
            service.Initialize(Application.Current!);

            service.SelectTheme(AppTheme.Dark);

            var preferenceDirectory = Path.Combine(root, "preferences");
            Assert.Equal(
                AppTheme.Dark.ToString(),
                File.ReadAllText(Path.Combine(preferenceDirectory, "theme.txt")));
            Assert.Empty(Directory.EnumerateFiles(preferenceDirectory, "*.tmp"));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static MainViewModel CreateViewModel() =>
        new(
            null,
            null,
            TimeProvider.System,
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));

    private static object FindResource(string key)
    {
        Assert.True(
            Application.Current!.Resources.TryGetResource(
                key,
                Application.Current.ActualThemeVariant,
                out var value));
        Assert.NotNull(value);
        return value;
    }

    private static void AssertContrast(string foregroundKey, string backgroundKey, double minimum)
    {
        var foreground = FindColorResource(foregroundKey);
        var background = FindColorResource(backgroundKey);
        var lighter = Math.Max(RelativeLuminance(foreground), RelativeLuminance(background));
        var darker = Math.Min(RelativeLuminance(foreground), RelativeLuminance(background));

        Assert.True(
            (lighter + 0.05) / (darker + 0.05) >= minimum,
            $"{foregroundKey} must have at least {minimum:0.0}:1 contrast against {backgroundKey}.");
    }

    private static double RelativeLuminance(Color color) =>
        0.2126 * Linearize(color.R) +
        0.7152 * Linearize(color.G) +
        0.0722 * Linearize(color.B);

    private static double Linearize(byte component)
    {
        var value = component / 255d;
        return value <= 0.04045
            ? value / 12.92
            : Math.Pow((value + 0.055) / 1.055, 2.4);
    }

    private static string CreateTemporaryDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"navtool-theme-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private static Color FindColorResource(string key) =>
        Assert.IsType<Color>(FindResource(key));

    private static Color GetPresenterBackground(TemplatedControl control)
    {
        control.ApplyTemplate();
        var presenter = control.GetVisualDescendants()
            .OfType<ContentPresenter>()
            .Single(candidate => candidate.Name == "PART_ContentPresenter");
        return Assert.IsAssignableFrom<ISolidColorBrush>(presenter.Background).Color;
    }

    private static void AssertTemplateTextForeground(
        TemplatedControl control,
        Color expectedForeground,
        params string[] partNames)
    {
        control.ApplyTemplate();
        var textParts = control.GetVisualDescendants()
            .OfType<TextBlock>()
            .Where(part => partNames.Contains(part.Name))
            .ToArray();

        Assert.Equal(partNames.Length, textParts.Length);
        Assert.All(textParts, part =>
        {
            Assert.True(part.IsEffectivelyVisible, $"{part.Name} must be visible.");
            Assert.False(string.IsNullOrWhiteSpace(part.Text), $"{part.Name} must display a value.");
            Assert.Equal(
                expectedForeground,
                Assert.IsAssignableFrom<ISolidColorBrush>(part.Foreground).Color);
        });
    }
}
