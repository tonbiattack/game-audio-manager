param(
    [string]$ConfigPath,
    [string]$SvclPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot 'config\games.json' }
if ([string]::IsNullOrWhiteSpace($SvclPath)) { $SvclPath = Join-Path $PSScriptRoot 'svcl.exe' }

. "$PSScriptRoot\lib\GameAudio.Config.ps1"
. "$PSScriptRoot\lib\GameAudio.Gui.ps1"
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
$form.Size = New-Object System.Drawing.Size(560, 330)
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
$form.Controls.Add($gameSelector)

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

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = '更新'
$refreshButton.Location = New-Object System.Drawing.Point(445, 205)
$refreshButton.Size = New-Object System.Drawing.Size(75, 28)
$form.Controls.Add($refreshButton)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(20, 205)
$status.Size = New-Object System.Drawing.Size(410, 85)
$status.AutoEllipsis = $true
$form.Controls.Add($status)

$script:guiState = @()
$script:activeDevices = @()
function Update-GameAudioGui {
    try {
        $games = @()
        if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
            $games = @(Get-GameConfiguration -Path $ConfigPath)
        }
        $script:activeDevices = @(Get-ActiveRenderDeviceNames)
        $processes = @(Get-Process -ErrorAction SilentlyContinue)
        $runningNames = @($processes | Select-Object -ExpandProperty ProcessName)
        $configured = @(Get-GameAudioGuiState -Games $games -ActiveDevices $script:activeDevices -RunningProcessNames $runningNames)
        $knownNames = @($configured | ForEach-Object { $_.ProcessName })
        # Show interactive applications even when they have not been added to JSON.
        # Background processes without a window can still be controlled via -ProcessName.
        $discovered = @($processes | Where-Object { $_.MainWindowHandle -ne 0 -and $knownNames -notcontains $_.ProcessName } |
            Sort-Object ProcessName -Unique | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.ProcessName
                    ProcessName = $_.ProcessName
                    OutputDevices = [string[]]@()
                    IsRunning = $true
                    PreferredDevice = $null
                }
            })
        $script:guiState = @($configured) + @($discovered)
        $gameSelector.Items.Clear()
        foreach ($game in $script:guiState) { [void]$gameSelector.Items.Add($game) }
        $gameSelector.DisplayMember = 'Name'
        $deviceSelector.Items.Clear()
        foreach ($device in $script:activeDevices) { [void]$deviceSelector.Items.Add($device) }
        if ($gameSelector.Items.Count -gt 0) { $gameSelector.SelectedIndex = 0 }
        $status.Text = '更新しました。'
    }
    catch { $status.Text = "設定またはデバイスの取得に失敗しました: $($_.Exception.Message)" }
}

function Update-SelectedGameStatus {
    $game = $gameSelector.SelectedItem
    if ($null -eq $game) { return }
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

$gameSelector.add_SelectedIndexChanged({ Update-SelectedGameStatus })
$deviceSelector.add_SelectedIndexChanged({ Update-SelectedGameStatus })
$refreshButton.add_Click({ Update-GameAudioGui; Update-SelectedGameStatus })
$preferredButton.add_Click({
    try { $request = New-GameAudioApplyRequest -Game $gameSelector.SelectedItem -ActiveDevices $script:activeDevices -UsePreferred; $status.Text = Invoke-GameOutputChange -ProcessName $request.ProcessName -Device $request.Device } catch { $status.Text = "適用に失敗しました: $($_.Exception.Message)" }
})
$selectedButton.add_Click({
    try { $request = New-GameAudioApplyRequest -Game $gameSelector.SelectedItem -ActiveDevices $script:activeDevices -SelectedDevice ([string]$deviceSelector.SelectedItem); $status.Text = Invoke-GameOutputChange -GameName $request.GameName -Device $request.Device } catch { $status.Text = "適用に失敗しました: $($_.Exception.Message)" }
})
$resetButton.add_Click({
    try { $status.Text = Invoke-GameOutputChange -ProcessName $gameSelector.SelectedItem.ProcessName -Reset } catch { $status.Text = "リセットに失敗しました: $($_.Exception.Message)" }
})

Update-GameAudioGui
Update-SelectedGameStatus
[void]$form.ShowDialog()
