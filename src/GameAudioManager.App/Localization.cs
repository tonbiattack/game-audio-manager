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
            ["DeviceNotConnected"] = ("未接続のデバイス", "Disconnected device"),

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
            ["StatusAutoStartBlockedByUser"] = (
                "Windows 側で無効にされています。「設定 > アプリ > スタートアップ」から有効にしてください。",
                "Turned off in Windows. Enable it in Settings > Apps > Startup."),
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

            // help window
            ["Help"] = ("使い方", "How to use"),
            ["HelpTitle"] = ("使い方", "How to use"),
            ["HelpClose"] = ("閉じる", "Close"),
            ["HelpOpenDocs"] = ("オンラインの説明を開く", "Open online documentation"),
            ["HelpOpenDocsFailed"] = ("ブラウザを開けませんでした。次の URL を開いてください: {0}", "Could not open a browser. Open this URL: {0}"),
            ["HelpIntro"] = (
                "このアプリは、Windows のアプリ・ゲームごとに「どのスピーカーから音を出すか」と「ミュートするか」を切り替えます。ウィンドウを閉じてもタスクトレイに残り、登録したアプリの出力先を自動で維持します。",
                "This app chooses which speakers each Windows application uses, and mutes apps individually. Closing the window keeps it in the tray, where it continues to maintain the configured output devices."),
            ["HelpFlowTitle"] = ("基本の流れ", "Basic steps"),
            ["HelpFlow"] = (
                "1. 一覧からアプリを選ぶ\n2. 「出力先」でデバイスを選び「適用」を押す\n3. 「ミュートする」で音を消す／「ミュートを解除」で戻す\n4. 出力先を自動で維持したいアプリは、行の「自動」にチェックを入れる\n5. 候補を増やしたい場合は、右側の「優先デバイス順」で「候補に追加」を押す",
                "1. Select an application in the list.\n2. Choose a device under Output and press Apply.\n3. Use Mute / Unmute to silence the app.\n4. Tick Auto on a row to keep its output device applied automatically.\n5. To add fallback devices, use Add under Output priority on the right."),
            ["HelpColumnsTitle"] = ("一覧の見方", "What the columns mean"),
            ["HelpColumns"] = (
                "・アプリ: 表示名。アイコンは実行ファイルから取得しています\n・状態: 適用済み / 反映待ち / デバイス未接続 / 失敗 / 未起動 / ルールなし\n・出力先: 実際に適用したデバイス名。未設定なら「既定の出力」\n・ミュート: 解除 / ミュート中 / 混在（複数デバイスで状態が違う）/ —（音声セッションなし）\n・自動: このアプリの出力先を自動で維持するか\n・プロセス: 実際のプロセス名",
                "Application: display name; the icon comes from the executable.\nState: Applied / Pending / Device missing / Failed / Not running / No rule.\nOutput: the device actually applied, or \"Windows default\".\nMute: Off / Muted / Mixed (devices disagree) / — (no audio session).\nAuto: whether this app's output is maintained automatically.\nProcess: the real process name."),
            ["HelpTimingTitle"] = ("出力先が反映されるタイミング", "When an output change takes effect"),
            ["HelpTiming"] = (
                "Windows の仕様により、出力先の変更は「次にそのアプリが音声セッションを作るとき」に反映されます。再生中の音は自動では移動しません。アプリを再起動するか、ゲーム内で音を出し直すと切り替わります。「Windows の既定へ戻す」も同じです。",
                "Windows applies an output change when the application next creates an audio session. Audio that is already playing does not move automatically; restart the app or start playback again. The same applies to Reset to Windows default."),
            ["HelpKeysTitle"] = ("キーボード操作", "Keyboard shortcuts"),
            ["HelpKeys"] = (
                "・Ctrl + F: 検索欄へ移動\n・Esc: 検索をクリア\n・F5: 一覧を更新\n・Ctrl + M: 選択中アプリのミュート切替\n・Ctrl + ,: 自動適用の開始 / 停止\n・F1: この使い方を開く",
                "Ctrl+F: focus the search box\nEsc: clear the search\nF5: refresh the list\nCtrl+M: toggle mute for the selected app\nCtrl+,: start or stop auto-apply\nF1: open this guide"),
            ["HelpTroubleTitle"] = ("うまくいかないとき", "Troubleshooting"),
            ["HelpTrouble"] = (
                "・ミュートの列が「—」のとき: そのアプリはまだ音を出していません。音を再生してから更新してください\n・状態が「デバイス未接続」のとき: 候補のデバイスが接続されていません。接続するか、優先デバイス順に別の候補を追加してください\n・状態が「失敗」のとき: この Windows のビルドではアプリ別の出力先変更が使えない可能性があります。ミュートは利用できます\n・アプリが一覧に出ないとき: ウィンドウを持たないプロセスは対象外です",
                "Mute shows —: the app has not produced audio yet. Play something, then refresh.\nState is Device missing: none of the candidate devices is connected. Connect one, or add another candidate.\nState is Failed: this Windows build may not allow per-app routing. Mute still works.\nAn app is missing from the list: processes without a window are not listed."),
            ["HelpFilesTitle"] = ("設定と保存場所", "Settings and storage"),
            ["HelpFiles"] = (
                "・設定: %LOCALAPPDATA%\\GameAudioManager\\settings.json\n・ログオン時の自動起動: チェックすると HKCU の Run に登録されます（管理者権限は不要）\n・終了するには、タスクトレイのアイコンを右クリックして「終了」を選びます",
                "Settings: %LOCALAPPDATA%\\GameAudioManager\\settings.json\nStart with Windows: ticking it adds an HKCU Run entry; no administrator rights needed.\nTo quit, right-click the tray icon and choose Exit."),

            // tray
            ["TrayOpen"] = ("開く", "Open"),
            ["TrayExit"] = ("終了", "Exit"),
            ["TrayTooltip"] = ("Game Audio Manager", "Game Audio Manager"),
            ["TrayHintTitle"] = ("タスクトレイに常駐しています", "Still running in the tray"),
            ["TrayHintText"] = (
                "ウィンドウを閉じても自動適用は続きます。もう一度起動するとこの画面が開きます。終了はトレイのアイコンから「終了」を選んでください。",
                "Auto-apply keeps running after you close the window. Launch the app again to reopen this window. To quit, right-click the tray icon and choose Exit."),
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



