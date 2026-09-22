# シレン6の音声出力切替: 調査記録

## 目的

Steam 版『不思議のダンジョン 風来のシレン6 とぐろ島探検録』だけの音声出力先を、Windows 上で切り替える。

## 確認できたこと

- 実行ファイルとプロセス名は `ShirenTheWanderer6.exe` / `ShirenTheWanderer6`。
- `detect-shiren-process.ps1` は、ゲーム起動中にプロセス、PID、ウィンドウタイトル、実行ファイルのパスを正しく検出した。
- ゲームを起動していないときの `Shiren 6 process was not found.` は正常な診断結果である。
- `set-shiren-output.ps1 -List` が失敗した原因は、同スクリプトが利用する `svcl.exe` が未配置だったことであり、ゲーム検出の失敗ではない。

## svcl.exe を使う現在の方式

`set-shiren-output.ps1` は NirSoft SoundVolumeCommandLine の `svcl.exe` を使い、シレン6に対する出力先設定を変更する。

`svcl.exe` はリポジトリ直下に置く。別の場所にある場合は `-SvclPath` で明示する。

```powershell
# 利用可能なデバイスを確認
.\set-shiren-output.ps1 -List

# シレン6を Realtek(R) Audio へ出力
.\set-shiren-output.ps1 -Device "Realtek(R) Audio"

# Windows の既定出力へ戻す
.\set-shiren-output.ps1 -Reset
```

確認時点で `C:\apps\toggle-shiren-mute\svcl.exe` は配置済みである。

デバイス名は PC ごとに異なる。`-List` の `指定値` を、`-Device` にそのまま指定する。検証環境では `Realtek(R) Audio`、`Soundcore Space A40`、`AMD High Definition Audio Device` が指定値として表示された。`表示名`（例: `Speaker`、`ヘッドホン`）ではない点に注意する。

## 追加ダウンロードなしで実現する選択肢

Windows の公開 Core Audio API は、オーディオ端点の列挙、ストリーム／セッションの管理、音量制御などを提供する。ただし、特定アプリの既定出力先を変更する公開・文書化済み API は見当たらない。

Windows 内部にはアプリ別出力設定に使われる COM コンポーネントがあり、検証環境では PowerShell から生成できた。そのため、PowerShell に COM インターフェース定義を組み込めば `svcl.exe` なしでの自動化は技術的には可能である。

ただし、そのインターフェースは未文書であり、Windows の更新で互換性が失われる可能性がある。標準 API だけでサポートされた実装ではない。

## 判断

通常は `svcl.exe` を使う方式を推奨する。PowerShell 側で未文書 API の詳細を抱えずに済み、Windows の内部変更に対する追随をツール側に委ねられるためである。

外部実行ファイルの配置・実行が組織のセキュリティ方針などで許可されない場合に限り、PowerShell 単体の未文書 API 方式を検討する。その場合は Windows 更新後に動作確認する運用が必要になる。

## 検証環境

- Windows 11（build 26200）
- PowerShell 7.6.6
- Steam 版シレン6

## 参考資料

- [Microsoft Learn: About the Windows Core Audio APIs](https://learn.microsoft.com/en-us/windows/win32/coreaudio/about-the-windows-core-audio-apis)
- [Microsoft Learn: Core Audio Interfaces](https://learn.microsoft.com/en-us/windows/win32/coreaudio/core-audio-interfaces)
- [NirSoft: SoundVolumeCommandLine](https://www.nirsoft.net/utils/sound_volume_command_line.html)
