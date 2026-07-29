using System.Security;
using Avalonia;
using Avalonia.Markup.Xaml.Styling;
using Avalonia.Styling;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Navtool.App.Models;

namespace Navtool.App.Services;

public sealed class AppThemeService
{
    private const string PreferenceDirectoryName = "preferences";
    private const string PreferenceFileName = "theme.txt";
    private readonly ILogger<AppThemeService> _logger;
    private readonly string? _preferencePath;
    private Application? _application;
    private ResourceInclude? _activeResources;

    public AppThemeService(string? appDataRoot, ILogger<AppThemeService>? logger = null)
    {
        _logger = logger ?? NullLogger<AppThemeService>.Instance;
        _preferencePath = appDataRoot is null
            ? null
            : Path.Combine(appDataRoot, PreferenceDirectoryName, PreferenceFileName);
    }

    public static IReadOnlyList<AppThemeOption> AvailableThemes { get; } =
    [
        new(AppTheme.Light, "Light"),
        new(AppTheme.Dark, "Dark"),
        new(AppTheme.KindOfBlue, "Kind of Blue")
    ];

    public AppTheme SelectedTheme { get; private set; } = AppTheme.Light;

    public bool IsInitialized => _application is not null;

    public event EventHandler<AppTheme>? ThemeChanged;

    public static AppThemeService CreateTransient() => new(null);

    public void Initialize(Application application)
    {
        ArgumentNullException.ThrowIfNull(application);
        if (_application is not null && !ReferenceEquals(_application, application))
        {
            throw new InvalidOperationException(
                "The theme service cannot be initialized for more than one application.");
        }

        _application = application;
        SelectedTheme = LoadPreference();
        ApplyTheme(SelectedTheme);
    }

    public void SelectTheme(AppTheme theme)
    {
        if (!Enum.IsDefined(theme))
        {
            throw new ArgumentOutOfRangeException(nameof(theme));
        }

        if (_application is null)
        {
            throw new InvalidOperationException("The theme service must be initialized first.");
        }

        if (theme == SelectedTheme)
        {
            return;
        }

        ApplyTheme(theme);
        SelectedTheme = theme;
        PersistPreference(theme);
        ThemeChanged?.Invoke(this, theme);
    }

    private AppTheme LoadPreference()
    {
        if (_preferencePath is null || !File.Exists(_preferencePath))
        {
            return AppTheme.Light;
        }

        try
        {
            var value = File.ReadAllText(_preferencePath).Trim();
            if (Enum.TryParse<AppTheme>(value, ignoreCase: true, out var theme) &&
                Enum.IsDefined(theme))
            {
                return theme;
            }

            _logger.LogWarning(
                "Ignoring unsupported theme preference '{ThemePreference}' in {PreferencePath}.",
                value,
                _preferencePath);
        }
        catch (IOException exception)
        {
            _logger.LogWarning(
                exception,
                "Could not read the theme preference from {PreferencePath}.",
                _preferencePath);
        }
        catch (UnauthorizedAccessException exception)
        {
            _logger.LogWarning(
                exception,
                "Access was denied while reading the theme preference from {PreferencePath}.",
                _preferencePath);
        }
        catch (SecurityException exception)
        {
            _logger.LogWarning(
                exception,
                "Security policy prevented reading the theme preference from {PreferencePath}.",
                _preferencePath);
        }

        return AppTheme.Light;
    }

    private void PersistPreference(AppTheme theme)
    {
        if (_preferencePath is null)
        {
            return;
        }

        var directory = Path.GetDirectoryName(_preferencePath)!;
        var temporaryPath = Path.Combine(
            directory,
            $".{PreferenceFileName}.{Guid.NewGuid():N}.tmp");
        try
        {
            Directory.CreateDirectory(directory);
            File.WriteAllText(temporaryPath, theme.ToString());
            File.Move(temporaryPath, _preferencePath, overwrite: true);
        }
        catch (IOException exception)
        {
            _logger.LogWarning(
                exception,
                "Could not save the theme preference to {PreferencePath}.",
                _preferencePath);
        }
        catch (UnauthorizedAccessException exception)
        {
            _logger.LogWarning(
                exception,
                "Access was denied while saving the theme preference to {PreferencePath}.",
                _preferencePath);
        }
        catch (SecurityException exception)
        {
            _logger.LogWarning(
                exception,
                "Security policy prevented saving the theme preference to {PreferencePath}.",
                _preferencePath);
        }
        finally
        {
            try
            {
                File.Delete(temporaryPath);
            }
            catch (IOException exception)
            {
                _logger.LogDebug(
                    exception,
                    "Could not remove temporary theme preference file {TemporaryPath}.",
                    temporaryPath);
            }
            catch (UnauthorizedAccessException exception)
            {
                _logger.LogDebug(
                    exception,
                    "Access was denied while removing temporary theme preference file {TemporaryPath}.",
                    temporaryPath);
            }
        }
    }

    private void ApplyTheme(AppTheme theme)
    {
        var application = _application ??
            throw new InvalidOperationException("The theme service must be initialized first.");
        var resources = new ResourceInclude(new Uri("avares://Navtool.App/"))
        {
            Source = new Uri($"avares://Navtool.App/Themes/{theme}.axaml")
        };

        application.RequestedThemeVariant = theme == AppTheme.Light
            ? ThemeVariant.Light
            : ThemeVariant.Dark;

        if (_activeResources is not null)
        {
            application.Resources.MergedDictionaries.Remove(_activeResources);
        }

        application.Resources.MergedDictionaries.Add(resources);
        _activeResources = resources;
    }
}
