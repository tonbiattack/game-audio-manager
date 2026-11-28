using System.IO;
using System.Runtime.InteropServices;
using GameAudioManager.Core.Startup;
using Windows.ApplicationModel;

namespace GameAudioManager.App.Startup;

/// <summary>
/// Logon autostart through the MSIX <c>uap5:StartupTask</c> extension.
/// </summary>
/// <remarks>
/// <para>
/// The package manifest declares the task with <c>Enabled="false"</c>, so installing the
/// app never creates a logon entry on its own; the toggle in the window requests it and
/// Windows records the answer per user. That is also what makes the entry appear in
/// Task Manager's Startup tab, where the user can turn it off without the app's help.
/// </para>
/// <para>
/// <c>DisabledByUser</c> is sticky: Windows refuses <c>RequestEnableAsync</c> until the
/// user re-enables the task themselves, so the UI has to explain that instead of
/// retrying forever.
/// </para>
/// </remarks>
public sealed class StartupTaskRegistration : IStartupRegistration
{
    /// <summary>Task id declared by <c>packaging/Package/AppxManifest.xml</c>.</summary>
    public const string DefaultTaskId = "GameAudioManagerStartup";

    private readonly string _taskId;

    public StartupTaskRegistration(string taskId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(taskId);
        _taskId = taskId;
    }

    public async Task<StartupRegistrationStatus> GetStatusAsync()
    {
        try
        {
            var task = await StartupTask.GetAsync(_taskId);
            return Map(task.State);
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or FileNotFoundException)
        {
            return new StartupRegistrationStatus(
                StartupRegistrationState.Unavailable,
                $"StartupTask '{_taskId}' could not be read: {ex.Message}");
        }
    }

    public async Task<StartupRegistrationStatus> SetEnabledAsync(bool enabled)
    {
        try
        {
            var task = await StartupTask.GetAsync(_taskId);
            if (!enabled)
            {
                task.Disable();
                return Map(task.State);
            }

            // RequestEnableAsync re-reads the state Windows applied, which can differ
            // from the request (for example when the user disabled it in Task Manager).
            return Map(await task.RequestEnableAsync());
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or FileNotFoundException)
        {
            return new StartupRegistrationStatus(
                StartupRegistrationState.Unavailable,
                $"StartupTask '{_taskId}' could not be changed: {ex.Message}");
        }
    }

    private static StartupRegistrationStatus Map(StartupTaskState state)
    {
        return state switch
        {
            StartupTaskState.Enabled => new StartupRegistrationStatus(StartupRegistrationState.Enabled),
            StartupTaskState.Disabled => new StartupRegistrationStatus(StartupRegistrationState.Disabled),
            StartupTaskState.DisabledByUser => new StartupRegistrationStatus(StartupRegistrationState.DisabledByUser),
            _ => new StartupRegistrationStatus(
                StartupRegistrationState.Unavailable,
                $"StartupTask state '{state}' is not handled."),
        };
    }
}
