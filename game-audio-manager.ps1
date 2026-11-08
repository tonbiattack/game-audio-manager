param(
    [string]$ConfigPath,
    [string]$SvclPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot 'config\games.json' }
if ([string]::IsNullOrWhiteSpace($SvclPath)) { $SvclPath = Join-Path $PSScriptRoot 'svcl.exe' }
$WatcherScriptPath = Join-Path $PSScriptRoot 'watch-game-output.ps1'
$WatchStatusPath = Join-Path $PSScriptRoot 'config\watcher-status.json'
$SettingsPath = Join-Path $PSScriptRoot 'config\settings.json'

. "$PSScriptRoot\lib\GameAudio.Config.ps1"
. "$PSScriptRoot\lib\GameAudio.Gui.ps1"
. "$PSScriptRoot\lib\GameAudio.Watch.ps1"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ActiveRenderDeviceNames {
    if (-not (Test-Path -LiteralPath $SvclPath -PathType Leaf)) { throw "svcl.exe was not found: $SvclPath" }
    $csv = @(& $SvclPath /Stdout /scomma '')
    if ($LASTEXITCODE -ne 0) { throw "Failed to list audio devices. svcl.exe exit code: $LASTEXITCODE" }
    return @($csv | ConvertFrom-Csv | Where-Object { $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and $_.'Device State' -eq 'Active' } | ForEach-Object { $_.'Device Name' })
}

function Invoke-GameOutputChange {
    param([string]$ProcessName, [string]$Device, [switch]$Reset)

    $hostPath = (Get-Process -Id $PID).Path
    $arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'set-game-output.ps1'), '-ProcessName', $ProcessName, '-SvclPath', $SvclPath)
    if ($Reset) { $arguments += '-Reset' } else { $arguments += @('-Device', $Device) }
    $result = & $hostPath @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($result -join [Environment]::NewLine) }
    return ($result -join [Environment]::NewLine)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Application Audio Manager'
$form.Size = New-Object System.Drawing.Size(560, 430)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$gameLabel = New-Object System.Windows.Forms.Label
$gameLabel.Text = 'アプリケーション'
$gameLabel.Location = New-Object System.Drawing.Point(20, 22)
$gameLabel.AutoSize = $true
$form.Controls.Add($gameLabel)

$gameSelector = New-Object System.Windows.Forms.ComboBox
$gameSelector.Location = New-Object System.Drawing.Point(20, 44)
$gameSelector.Size = New-Object System.Drawing.Size(500, 24)
$gameSelector.DropDownStyle = 'DropDownList'
$gameSelector.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$gameSelector.ItemHeight = 24
$form.Controls.Add($gameSelector)

# Keep extracted application icons in memory only while the list is displayed.
$script:appIcons = @{}
$gameSelector.add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }

    $e.DrawBackground()
    $app = $sender.Items[$e.Index]
    $icon = $script:appIcons[[string]$app.ProcessName]
    if ($null -ne $icon) {
        $e.Graphics.DrawImage($icon, $e.Bounds.X + 5, $e.Bounds.Y + 4, 16, 16)
    }

    $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $color = if ($selected) { [System.Drawing.SystemColors]::HighlightText } else { $e.ForeColor }
    $textBounds = New-Object System.Drawing.Rectangle(($e.Bounds.X + 26), $e.Bounds.Y, ([Math]::Max(0, $e.Bounds.Width - 30)), $e.Bounds.Height)
    [System.Windows.Forms.TextRenderer]::DrawText(
        $e.Graphics, [string]$app.Name, $e.Font, $textBounds, $color,
        ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
         [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
         [System.Windows.Forms.TextFormatFlags]::NoPrefix))
    $e.DrawFocusRectangle()
})

$deviceLabel = New-Object System.Windows.Forms.Label
$deviceLabel.Text = '出力先'
$deviceLabel.Location = New-Object System.Drawing.Point(20, 86)
$deviceLabel.AutoSize = $true
$form.Controls.Add($deviceLabel)

$deviceSelector = New-Object System.Windows.Forms.ComboBox
$deviceSelector.Location = New-Object System.Drawing.Point(20, 108)
$deviceSelector.Size = New-Object System.Drawing.Size(500, 24)
$deviceSelector.DropDownStyle = 'DropDownList'
$form.Controls.Add($deviceSelector)

$preferredButton = New-Object System.Windows.Forms.Button
$preferredButton.Text = '優先デバイスを適用'
$preferredButton.Location = New-Object System.Drawing.Point(20, 156)
$preferredButton.Size = New-Object System.Drawing.Size(155, 30)
$form.Controls.Add($preferredButton)

$selectedButton = New-Object System.Windows.Forms.Button
$selectedButton.Text = '選択したデバイスを適用'
$selectedButton.Location = New-Object System.Drawing.Point(185, 156)
$selectedButton.Size = New-Object System.Drawing.Size(175, 30)
$form.Controls.Add($selectedButton)

$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Text = 'Windows の既定へ戻す'
$resetButton.Location = New-Object System.Drawing.Point(370, 156)
$resetButton.Size = New-Object System.Drawing.Size(150, 30)
$form.Controls.Add($resetButton)

$registerRuleButton = New-Object System.Windows.Forms.Button
$registerRuleButton.Text = '監視ルールに登録'
$registerRuleButton.Location = New-Object System.Drawing.Point(20, 192)
$registerRuleButton.Size = New-Object System.Drawing.Size(170, 30)
$form.Controls.Add($registerRuleButton)

$excludeRuleButton = New-Object System.Windows.Forms.Button
$excludeRuleButton.Text = '監視から除外'
$excludeRuleButton.Location = New-Object System.Drawing.Point(195, 192)
$excludeRuleButton.Size = New-Object System.Drawing.Size(130, 30)
$form.Controls.Add($excludeRuleButton)

$startWatchButton = New-Object System.Windows.Forms.Button
$startWatchButton.Text = '監視を開始'
$startWatchButton.Location = New-Object System.Drawing.Point(330, 192)
$startWatchButton.Size = New-Object System.Drawing.Size(105, 30)
$form.Controls.Add($startWatchButton)

$stopWatchButton = New-Object System.Windows.Forms.Button
$stopWatchButton.Text = '監視を停止'
$stopWatchButton.Location = New-Object System.Drawing.Point(440, 192)
$stopWatchButton.Size = New-Object System.Drawing.Size(105, 30)
$form.Controls.Add($stopWatchButton)

$autoStartWatcherCheckBox = New-Object System.Windows.Forms.CheckBox
$autoStartWatcherCheckBox.Text = 'GUI 起動時に監視を自動開始'
$autoStartWatcherCheckBox.Location = New-Object System.Drawing.Point(20, 230)
$autoStartWatcherCheckBox.Size = New-Object System.Drawing.Size(215, 22)
$form.Controls.Add($autoStartWatcherCheckBox)

$intervalLabel = New-Object System.Windows.Forms.Label
$intervalLabel.Text = '監視間隔(秒)'
$intervalLabel.Location = New-Object System.Drawing.Point(245, 233)
$intervalLabel.AutoSize = $true
$form.Controls.Add($intervalLabel)

$intervalSelector = New-Object System.Windows.Forms.NumericUpDown
$intervalSelector.Location = New-Object System.Drawing.Point(330, 229)
$intervalSelector.Size = New-Object System.Drawing.Size(70, 24)
$intervalSelector.Minimum = 1
$intervalSelector.Maximum = 3600
$form.Controls.Add($intervalSelector)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = '更新'
$refreshButton.Location = New-Object System.Drawing.Point(445, 229)
$refreshButton.Size = New-Object System.Drawing.Size(75, 28)
$form.Controls.Add($refreshButton)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(20, 262)
$status.Size = New-Object System.Drawing.Size(500, 62)
$status.AutoEllipsis = $true
$form.Controls.Add($status)

$watchStatusLabel = New-Object System.Windows.Forms.Label
$watchStatusLabel.Location = New-Object System.Drawing.Point(20, 330)
$watchStatusLabel.Size = New-Object System.Drawing.Size(500, 68)
$watchStatusLabel.AutoEllipsis = $true
$form.Controls.Add($watchStatusLabel)

$script:guiState = @()
$script:activeDevices = @()

function Update-AppIcons {
    param([object[]]$Processes, [object[]]$Applications)

    foreach ($bitmap in $script:appIcons.Values) {
        if ($null -ne $bitmap) { $bitmap.Dispose() }
    }
    $script:appIcons = @{}

    foreach ($app in $Applications) {
        $name = [string]$app.ProcessName
        if ($script:appIcons.ContainsKey($name)) { continue }

        # Some applications do not expose an executable path (access denied,
        # system processes, or packaged applications). Display text in that case.
        foreach ($process in @($Processes | Where-Object { $_.ProcessName -ieq $name })) {
            try {
                $path = $process.Path
                if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
                if ($null -eq $icon) { continue }
                try { $script:appIcons[$name] = $icon.ToBitmap() }
                finally { $icon.Dispose() }
                break
            }
            catch {
                # Missing or inaccessible icon: leave this app text-only.
            }
        }
    }
}

function Update-GameAudioGui {
    try {
        $games = @()
        if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
            $games = @(Get-GameConfiguration -Path $ConfigPath)
        }
        $script:activeDevices = @(Get-ActiveRenderDeviceNames)
        $processes = @(Get-Process -ErrorAction SilentlyContinue)
        $runningNames = @($processes | Select-Object -ExpandProperty ProcessName)
        $configured = @()
        if ($games.Count -gt 0) {
            $configured = @(Get-GameAudioGuiState -Games $games -ActiveDevices $script:activeDevices -RunningProcessNames $runningNames)
        }
        # Show interactive applications even when they have not been added to JSON.
        # Background processes without a window can still be controlled via -ProcessName.
        $discovered = @(Get-DiscoveredGameAudioApplications -Processes $processes -ConfiguredGames $games)
        $script:guiState = @($configured) + @($discovered)
        $gameSelector.Items.Clear()
        Update-AppIcons -Processes $processes -Applications $script:guiState
        foreach ($game in $script:guiState) { [void]$gameSelector.Items.Add($game) }
        $gameSelector.DisplayMember = 'Name'
        $deviceSelector.Items.Clear()
        foreach ($device in $script:activeDevices) { [void]$deviceSelector.Items.Add($device) }
        if ($gameSelector.Items.Count -gt 0) { $gameSelector.SelectedIndex = 0 }
        $status.Text = '更新しました。'
    }
    catch { $status.Text = "設定またはデバイスの取得に失敗しました: $($_.Exception.Message)" }
}

function Update-WatchStatusDisplay {
    $running = Test-GameAudioWatchRunning -StatusPath $WatchStatusPath
    $startWatchButton.Enabled = -not $running
    $stopWatchButton.Enabled = $running
    try {
        $watchData = Get-GameAudioWatchStatus -StatusPath $WatchStatusPath
        $watchStatusLabel.Text = Format-GameAudioWatchStatusText -Status $watchData -Running $running
    }
    catch {
        $watchStatusLabel.Text = "監視状態の表示に失敗しました: $($_.Exception.Message)"
    }
}

function Update-SelectedGameStatus {
    $game = $gameSelector.SelectedItem
    if ($null -eq $game) { return }
    $hasRule = (@($game.OutputDevices)).Count -gt 0
    $registerRuleButton.Enabled = ($deviceSelector.SelectedIndex -ge 0 -or $hasRule)
    $excludeRuleButton.Enabled = $hasRule
    if (-not $game.IsRunning) {
        $status.Text = "$($game.Name) は起動していません。起動後に更新してください。"
        $preferredButton.Enabled = $false
        $selectedButton.Enabled = $false
        $resetButton.Enabled = $false
        return
    }
    $preferredButton.Enabled = -not [string]::IsNullOrWhiteSpace($game.PreferredDevice)
    $selectedButton.Enabled = $deviceSelector.SelectedIndex -ge 0
    $resetButton.Enabled = $true
    if ($game.PreferredDevice) { $status.Text = "優先デバイス: $($game.PreferredDevice)" } else { $status.Text = '設定した優先デバイスは接続されていません。接続中のデバイスを選択してください。' }
}

function Save-GuiSettings {
    try {
        Set-GameAudioManagerSettings -Path $SettingsPath -WatchIntervalSeconds ([int]$intervalSelector.Value) -AutoStartWatcher $autoStartWatcherCheckBox.Checked
    }
    catch { $status.Text = "設定の保存に失敗しました: $($_.Exception.Message)" }
}

$gameSelector.add_SelectedIndexChanged({ Update-SelectedGameStatus })
$deviceSelector.add_SelectedIndexChanged({ Update-SelectedGameStatus })
$refreshButton.add_Click({ Update-GameAudioGui; Update-SelectedGameStatus })
$preferredButton.add_Click({
    try { $request = New-GameAudioApplyRequest -Game $gameSelector.SelectedItem -ActiveDevices $script:activeDevices -UsePreferred; $status.Text = Invoke-GameOutputChange -ProcessName $request.ProcessName -Device $request.Device } catch { $status.Text = "適用に失敗しました: $($_.Exception.Message)" }
})
$selectedButton.add_Click({
    try { $request = New-GameAudioApplyRequest -Game $gameSelector.SelectedItem -ActiveDevices $script:activeDevices -SelectedDevice ([string]$deviceSelector.SelectedItem); $status.Text = Invoke-GameOutputChange -ProcessName $request.ProcessName -Device $request.Device } catch { $status.Text = "適用に失敗しました: $($_.Exception.Message)" }
})
$resetButton.add_Click({
    try { $status.Text = Invoke-GameOutputChange -ProcessName $gameSelector.SelectedItem.ProcessName -Reset } catch { $status.Text = "リセットに失敗しました: $($_.Exception.Message)" }
})
$registerRuleButton.add_Click({
    $game = $gameSelector.SelectedItem
    if ($null -eq $game) { return }
    try {
        $request = ConvertTo-GameAudioRuleRequest -Game $game -SelectedDevice ([string]$deviceSelector.SelectedItem)
        $deviceArgument = @()
        if (-not [string]::IsNullOrWhiteSpace($request.Device)) { $deviceArgument = @($request.Device) }
        Set-GameAudioRule -Path $ConfigPath -ProcessName $request.ProcessName -Name $request.Name -OutputDevices $deviceArgument
        $status.Text = "$($request.Name) を監視ルール ($ConfigPath) に保存しました。"
        Update-GameAudioGui
        Update-SelectedGameStatus
    }
    catch { $status.Text = "監視ルールの保存に失敗しました: $($_.Exception.Message)" }
})
$excludeRuleButton.add_Click({
    $game = $gameSelector.SelectedItem
    if ($null -eq $game) { return }
    try {
        Remove-GameAudioRule -Path $ConfigPath -ProcessName $game.ProcessName
        $status.Text = "$($game.Name) を監視ルールから除外しました。"
        Update-GameAudioGui
        Update-SelectedGameStatus
    }
    catch { $status.Text = "監視ルールの除外に失敗しました: $($_.Exception.Message)" }
})
$startWatchButton.add_Click({
    try {
        if (Test-GameAudioWatchRunning -StatusPath $WatchStatusPath) {
            $status.Text = '監視はすでに動作しています。'
            return
        }
        Start-GameAudioWatchProcess -WatcherScriptPath $WatcherScriptPath -IntervalSeconds ([int]$intervalSelector.Value)
        $status.Text = '監視を起動しました。'
    }
    catch { $status.Text = "監視の起動に失敗しました: $($_.Exception.Message)" }
})
$stopWatchButton.add_Click({
    try {
        [void](Stop-GameAudioWatch)
        $status.Text = '監視の停止を要求しました。'
    }
    catch { $status.Text = "監視の停止に失敗しました: $($_.Exception.Message)" }
})
$autoStartWatcherCheckBox.add_CheckedChanged({ Save-GuiSettings })
$intervalSelector.add_ValueChanged({ Save-GuiSettings })

$watchTimer = New-Object System.Windows.Forms.Timer
$watchTimer.Interval = 3000
$watchTimer.add_Tick({ Update-WatchStatusDisplay })

try {
    $settings = Get-GameAudioManagerSettings -Path $SettingsPath
    $autoStartWatcherCheckBox.Checked = $settings.AutoStartWatcher
    $intervalSelector.Value = [Math]::Max(1, [Math]::Min(3600, $settings.WatchIntervalSeconds))
    if ($autoStartWatcherCheckBox.Checked) {
        try {
            if (-not (Test-GameAudioWatchRunning -StatusPath $WatchStatusPath)) {
                Start-GameAudioWatchProcess -WatcherScriptPath $WatcherScriptPath -IntervalSeconds ([int]$intervalSelector.Value)
            }
        }
        catch { $status.Text = "監視の起動に失敗しました: $($_.Exception.Message)" }
    }
}
catch { $status.Text = "設定の読み込みに失敗しました: $($_.Exception.Message)" }

Update-GameAudioGui
Update-SelectedGameStatus
Update-WatchStatusDisplay
$watchTimer.Start()
try { [void]$form.ShowDialog() }
finally {
    $watchTimer.Stop()
    $watchTimer.Dispose()
    foreach ($bitmap in $script:appIcons.Values) {
        if ($null -ne $bitmap) { $bitmap.Dispose() }
    }
    $form.Dispose()
}
