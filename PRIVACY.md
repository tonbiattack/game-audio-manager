# プライバシーポリシー / Privacy Policy

最終更新 / Last updated: 2026-11-28

Game Audio Manager（以下「本アプリ」）は、利用者の個人情報を収集しません。

Game Audio Manager does not collect personal information.

## 収集しないもの / What is not collected

- 氏名・メールアドレス・アカウント情報（氏名、メールアドレス、アカウント情報）
- 利用状況の統計、テレメトリ、クラッシュレポートの送信
- 音声の内容、録音データ

## 端末内で扱う情報 / Information handled on the device

| 情報 / Data | 用途 / Purpose | 保存 / Storage |
| --- | --- | --- |
| 設定（出力先の割り当て、ミュート、テーマ、言語、自動起動） | 動作の維持 | 設定ファイル（下記） |
| 音声デバイスの ID と名前 | 出力先の切り替え | 設定ファイル |
| アプリのプロセス名・音声セッションの状態 | 一覧表示と出力先の適用 | 保存しない（メモリ上のみ） |

These values are read locally to build the app list and to apply the output device you chose.
They are never transmitted.

## ネットワーク通信 / Network access

本アプリはネットワーク通信を行いません。Microsoft Store 版の更新は Microsoft Store が行います。

The app makes no network requests. Updates of the Microsoft Store version are delivered by the Store.

## 第三者提供 / Sharing

取得した情報を第三者へ提供することはありません。

No data is shared with third parties.

## 保存場所と削除 / Storage location and removal

| 配布 / Distribution | 設定ファイル / Settings file |
| --- | --- |
| GitHub Releases（EXE） | `%LOCALAPPDATA%\GameAudioManager\settings.json` |
| Microsoft Store（MSIX） | `%LOCALAPPDATA%\Packages\<パッケージ ID>\LocalState\GameAudioManager\settings.json` |

- Microsoft Store 版をアンインストールすると、上記のパッケージ データは削除されます。
- GitHub Releases 版は、上記ファイルと `%LOCALAPPDATA%\GameAudioManager` フォルダを削除してください。

Uninstalling the Microsoft Store version removes its package data. For the GitHub Releases build,
delete the folder above.

## お問い合わせ / Contact

- https://github.com/tonbiattack/game-audio-manager/issues
