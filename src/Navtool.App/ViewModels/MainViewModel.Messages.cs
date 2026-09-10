using Navtool.App.Models;
using Navtool.Core;

namespace Navtool.App.ViewModels;

public partial class MainViewModel
{
    private readonly List<RoutingMessage> _routingMessages = [];
    private readonly List<RoutingMessage> _routingWarnings = [];
    private string? _ownedRoutingError;
    private string? _ownedRoutingWarning;

    public long MessageGeneration { get; private set; }

    public IReadOnlyList<RoutingMessage> CurrentMessages
    {
        get
        {
            var messages = new List<RoutingMessage>(_routingMessages);
            if (!string.IsNullOrWhiteSpace(ErrorMessage) && ErrorMessage != _ownedRoutingError)
                messages.Add(new("error", "Error", ErrorMessage, RoutingMessageSeverity.Error));
            if (!string.IsNullOrWhiteSpace(WarningMessage))
            {
                var scopedWarnings = WarningMessage == _ownedRoutingWarning ? _routingWarnings : [];
                messages.AddRange(scopedWarnings);
                foreach (var warning in WarningMessage.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
                             .Distinct(StringComparer.Ordinal))
                    if (!scopedWarnings.Any(message => message.Summary == warning))
                        messages.Add(new($"warning:{warning}", "Notice", warning, RoutingMessageSeverity.Warning));
            }
            if (!string.IsNullOrWhiteSpace(RoutingSetup.ErrorMessage))
                messages.Add(new("setup", "Routing setup", RoutingSetup.ErrorMessage, RoutingMessageSeverity.Error));
            if (!string.IsNullOrWhiteSpace(PreferenceError))
                messages.Add(new("preferences", "Preferences", PreferenceError, RoutingMessageSeverity.Error));
            return messages;
        }
    }

    private void ClearRoutingMessages()
    {
        // Only clear aggregate strings owned by this outcome, not a newer unrelated error.
        if (_ownedRoutingError is not null && ErrorMessage == _ownedRoutingError) ErrorMessage = null;
        if (_ownedRoutingWarning is not null && WarningMessage == _ownedRoutingWarning) WarningMessage = null;
        _ownedRoutingError = null;
        _ownedRoutingWarning = null;
        _routingMessages.Clear();
        _routingWarnings.Clear();
        MessageGeneration++;
        OnPropertyChanged(nameof(CurrentMessages));
    }

    internal void SetRoutingFailure(ForecastModel model, int legIndex, string reason, Coordinate? endpoint = null)
    {
        var id = $"route:{model}:{legIndex}";
        var existing = _routingMessages.FindIndex(message => message.Id == id);
        endpoint ??= existing >= 0 ? _routingMessages[existing].Endpoint : null;
        var summary = reason;
        string? details = null;
        var coverageIndex = reason.IndexOf(" The loaded forecast covers ", StringComparison.Ordinal);
        if (endpoint is not null && coverageIndex >= 0)
        {
            summary = reason[..coverageIndex];
            details = reason[(coverageIndex + 1)..];
        }
        var message = new RoutingMessage(id, $"{ModelName(model)} / leg {legIndex + 1}",
            summary, endpoint is null ? RoutingMessageSeverity.Error : RoutingMessageSeverity.Warning,
            model, legIndex, endpoint, details);
        if (existing < 0) _routingMessages.Add(message);
        else _routingMessages[existing] = message;
        OnPropertyChanged(nameof(CurrentMessages));
    }

    private void OwnRoutingOutcomeMessages()
    {
        _ownedRoutingError = ErrorMessage;
        _ownedRoutingWarning = WarningMessage;
        OnPropertyChanged(nameof(CurrentMessages));
    }

    private bool IsRoutingFailureRepresented(string reason) =>
        _routingMessages.Any(message => string.Equals(
            message.Details is null ? message.Summary : $"{message.Summary} {message.Details}",
            reason, StringComparison.Ordinal));

    private void CaptureRoutingWarnings(ForecastModel model, IEnumerable<string> warnings)
    {
        foreach (var warning in warnings.Distinct(StringComparer.Ordinal))
        {
            var message = new RoutingMessage($"warning:{model}:{warning}", $"{ModelName(model)} notice",
                warning, RoutingMessageSeverity.Warning, model);
            if (!_routingWarnings.Contains(message)) _routingWarnings.Add(message);
        }
    }

    private void AddCancellationMessage()
    {
        if (_routingMessages.Count != 0) return;
        _routingMessages.Add(new("cancelled", "Calculation cancelled", "Cancelled by user. No provisional path was retained.",
            RoutingMessageSeverity.Information));
        OnPropertyChanged(nameof(CurrentMessages));
    }
}
