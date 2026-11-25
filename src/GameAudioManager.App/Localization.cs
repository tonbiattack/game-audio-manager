using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;

namespace GameAudioManager.App;

/// <summary>
/// UI string table with a switchable language.
/// </summary>
/// <remarks>
/// <para>
/// Strings are addressed by key through an indexer, so XAML can bind
/// <c>{Binding [Key], Source={x:Static app:Localization.Instance}}</c>. Raising
/// <c>PropertyChanged("Item[]")</c> refreshes every binding when the language
/// changes, without rebuilding the window or restarting.
/// </para>
/// <para>
/// Keeping this hand-written rather than .resx avoids a build step and keeps the two
/// languages side by side, which makes missing translations obvious.
/// </para>
/// </remarks>
public sealed class Localization : INotifyPropertyChanged
{
    public const string Japanese = "ja";
    public const string English = "en";

    private static readonly IReadOnlyDictionary<string, (string Ja, string En)> Table =
        new Dictionary<string, (string, string)>(StringComparer.Ordinal)
        {
            // window / header
            ["AppTitle"] = ("Game Audio Manager", "Game Audio Manager"),
            ["Header"] = ("アプリケーション", "Applications"),
            ["Search"] = ("検索", "Search"),
            ["ShowNotRunning"] = ("未起動も表示", "Show inactive"),
            ["Refresh"] = ("更新", "Refresh"),
            ["WatcherStop"] = ("自動適用を停止", "Stop auto-apply"),
            ["WatcherStart"] = ("自動適用を開始", "Start auto-apply"),
            ["DarkTheme"] = ("ダークテーマ", "Dark theme"),
            ["Theme"] = ("テーマ", "Theme"),
            ["ThemeSystem"] = ("システム", "System"),
            ["ThemeLight"] = ("ライト", "Light"),
            ["ThemeDark"] = ("ダーク", "Dark"),
            ["Language"] = ("言語", "Language"),
            ["ImportLegacy"] = ("旧設定を取り込む…", "Import old settings…"),

            // list columns
            ["ColumnApp"] = ("アプリ", "Application"),
            ["ColumnState"] = ("状態", "State"),
            ["ColumnOutput"] = ("出力先", "Output"),
            ["ColumnMute"] = ("ミュート", "Mute"),
            ["ColumnAuto"] = ("自動", "Auto"),
            ["ColumnProcess"] = ("プロセス", "Process"),

            // row state
            ["StateApplied"] = ("適用済み", "Applied"),
            ["StatePending"] = ("反映待ち", "Pending"),
            ["StateNoDevice"] = ("デバイス未接続", "Device missing"),
            ["StateFailed"] = ("失敗", "Failed"),
            ["StateNotRunning"] = ("未起動", "Not running"),
            ["StateNoRule"] = ("ルールなし", "No rule"),
            ["MuteNone"] = ("—", "—"),
            ["MuteOn"] = ("ミュート中", "Muted"),
            ["MuteOff"] = ("解除", "Off"),
            ["MuteMixed"] = ("混在", "Mixed"),
            ["DefaultOutput"] = ("既定の出力", "Windows default"),

            // priority panel
            ["PriorityTitle"] = ("優先デバイス順（上が優先）", "Output priority (top first)"),
            ["AddCandidate"] = ("候補に追加", "Add"),
            ["RemoveCandidate"] = ("削除", "Remove"),
            ["MoveUp"] = ("上へ", "Up"),
            ["MoveDown"] = ("下へ", "Down"),

            // action bar
            ["OutputLabel"] = ("出力先", "Output"),
            ["Apply"] = ("適用", "Apply"),
            ["ResetToDefault"] = ("Windows の既定へ戻す", "Reset to Windows default"),
            ["MuteToggle"] = ("ミュート切替", "Toggle mute"),
            ["MuteOnButton"] = ("ミュートする", "Mute"),
            ["MuteOffButton"] = ("ミュートを解除", "Unmute"),
            ["AutoStartWithWindows"] = ("ログオン時に自動起動", "Start with Windows"),
            ["RoutingHint"] = (
                "出力先の変更は、アプリが次に音声セッションを作るときに反映されます。",
                "Output changes apply the next time the app creates an audio session."),

            // status messages
            ["StatusReady"] = ("準備中…", "Starting…"),
            ["StatusRunning"] = ("自動適用を実行中です。", "Auto-apply is running."),
            ["StatusStopped"] = ("自動適用は停止中です。", "Auto-apply is stopped."),
            ["StatusAutoStopped"] = ("自動適用を停止しました。", "Auto-apply stopped."),
            ["StatusAutoStarted"] = ("自動適用を開始しました。", "Auto-apply started."),
            ["StatusRefreshed"] = ("更新: {0}", "Refreshed: {0}"),
            ["StatusRefreshFailed"] = ("更新に失敗しました: {0}", "Refresh failed: {0}"),
            ["StatusThemeDark"] = ("ダークテーマに切り替えました。", "Switched to the dark theme."),
            ["StatusThemeLight"] = ("ライトテーマに切り替えました。", "Switched to the light theme."),
            ["StatusThemeSystem"] = ("システムのテーマに追従します。", "Following the system theme."),
            ["StatusLanguageChanged"] = ("表示言語を変更しました。", "Display language changed."),
            ["StatusActionFailed"] = ("操作に失敗しました: {0}", "Action failed: {0}"),
            ["StatusAutoStartOn"] = ("ログオン時に自動起動するよう登録しました。", "Registered to start with Windows."),
            ["StatusAutoStartOff"] = ("ログオン時の自動起動を解除しました。", "Removed the start-with-Windows entry."),
            ["StatusAutoStartFailed"] = ("自動起動の設定に失敗しました: {0}", "Could not change start with Windows: {0}"),
            ["StatusSaveFailed"] = ("設定の保存に失敗しました: {0}", "Could not save settings: {0}"),
            ["StatusWatchCycleFailed"] = ("自動適用でエラー: {0}", "Auto-apply error: {0}"),
            ["StatusNoSession"] = (
                "{0}: 音声セッションがありません。音声を再生してから更新してください。",
                "{0}: no audio session yet. Play some audio, then refresh."),
            ["StatusMuted"] = ("{0}: ミュートしました", "{0}: muted"),
            ["StatusUnmuted"] = ("{0}: ミュートを解除しました", "{0}: unmuted"),
            ["StatusMuteFailed"] = ("{0}: ミュートを変更できませんでした。", "{0}: could not change mute."),
            ["StatusAutoApplyOn"] = ("{0}: 自動適用を有効にしました。", "{0}: auto-apply enabled."),
            ["StatusAutoApplyOff"] = ("{0}: 自動適用を無効にしました。", "{0}: auto-apply disabled."),
            ["StatusApplied"] = ("{0} → {1}。{2}", "{0} → {1}. {2}"),
            ["StatusImportResult"] = (
                "旧設定を取り込みました: 追加 {0} 件 / 統合 {1} 件",
                "Imported old settings: {0} added, {1} merged"),
            ["StatusImportBackup"] = (
                "（既存設定を {0} に退避）",
                " (previous settings saved as {0})"),
            ["StatusImportUnresolved"] = (
                "（デバイス未接続のため名前のまま保持: {0} 件）",
                " ({0} device(s) kept by name because they are not connected)"),

            // dialogs
            ["ImportDialogTitle"] = ("旧バージョンの games.json を選択", "Select the previous games.json"),
            ["ImportDialogFilter"] = ("games.json|games.json|JSON|*.json|すべてのファイル|*.*", "games.json|games.json|JSON|*.json|All files|*.*"),
            ["ImportResultTitle"] = ("旧設定の取り込み", "Import result"),
            ["ImportResultBody"] = ("追加: {0} 件\n統合: {1} 件\n未接続で名前のまま保持: {2} 件", "Added: {0}\nMerged: {1}\nKept by name (not connected): {2}"),

            // tray
            ["TrayOpen"] = ("開く", "Open"),
            ["TrayExit"] = ("終了", "Exit"),
            ["TrayTooltip"] = ("Game Audio Manager", "Game Audio Manager"),
        };

    private string _language = English;

    private Localization()
    {
    }

    public static Localization Instance { get; } = new();

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Language
    {
        get => _language;
        set
        {
            var normalized = string.Equals(value, Japanese, StringComparison.OrdinalIgnoreCase) ? Japanese : English;
            if (string.Equals(_language, normalized, StringComparison.Ordinal))
            {
                return;
            }

            _language = normalized;
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo(normalized == Japanese ? "ja-JP" : "en-US");

            // "Item[]" refreshes every indexer binding in one go.
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsJapanese)));
        }
    }

    public bool IsJapanese
    {
        get => _language == Japanese;
        set => Language = value ? Japanese : English;
    }

    /// <summary>Language used on first run: the OS UI language when it is Japanese.</summary>
    public static string DetectSystemLanguage()
    {
        return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals(Japanese, StringComparison.OrdinalIgnoreCase)
            ? Japanese
            : English;
    }

    /// <summary>XAML entry point: <c>{Binding [Key], Source={x:Static app:Localization.Instance}}</c>.</summary>
    public string this[string key]
    {
        get
        {
            if (Table.TryGetValue(key, out var entry))
            {
                return _language == Japanese ? entry.Ja : entry.En;
            }

            // Show the key so a missing translation is visible instead of blank.
            return key;
        }
    }

    /// <summary>Formats a translated string.</summary>
    public string Format(string key, params object?[] args)
    {
        return string.Format(CultureInfo.CurrentCulture, this[key], args);
    }

    /// <summary>Sets the language from a settings value, falling back to detection.</summary>
    public string Resolve(string? configured)
    {
        if (string.Equals(configured, Japanese, StringComparison.OrdinalIgnoreCase))
        {
            return Japanese;
        }

        if (string.Equals(configured, English, StringComparison.OrdinalIgnoreCase))
        {
            return English;
        }

        return DetectSystemLanguage();
    }

    private static void Raise([CallerMemberName] string? name = null) =>
        Instance.PropertyChanged?.Invoke(Instance, new PropertyChangedEventArgs(name));
}
