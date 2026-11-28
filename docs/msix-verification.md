# MSIX 実測レポート: パッケージ内からの音声ルーティングと配布時の挙動

最終更新: 2026-11-28（実測日: 2026-11-28）
対象 Issue: #39（親 #35）

## 結論

**MSIX 化してもアプリ別の出力先変更は動く。** これまで仮説だった「パッケージ内から
`Windows.Media.Internal.AudioPolicyConfig` を呼べるか」「OS が設定をパッケージ外に保存するか」は、
実測で**どちらも成立**した。指定デバイスは、対象アプリが次に作る音声セッションに実際に適用された。

ただし MSIX を配布形態にするには、**アプリ側の作り直しが必要な点が 3 つ**見つかった
（自動起動・設定の保存先・既存 EXE 版との単一インスタンス衝突）。

一方、**署名済み MSIX の実インストールと WACK はこの環境では実行できていない**（管理者権限が必要）。
ストア提出の可否を左右する非公開 API の扱いも、ストアポリシー 10.2.8 が
「サポートされない方法での未文書化 API の使用」を禁じる形で残っており、**個別判断**になる。
**「MSIX ならストアに出せる」とは言えない。**

| 判断材料 | 結果 |
| --- | --- |
| MSIX 内から音声ルーティング API を呼べるか | ✅ 成功（`Recorded=True`） |
| OS の設定ストアはパッケージ外から見えるか | ✅ 見える（`HKCU\Software\Microsoft\Multimedia\Audio\DefaultEndpoint`） |
| 実際の音声セッションに反映されるか | ✅ 反映（新規セッションが指定デバイスに載った） |
| アプリ本体は MSIX で起動・常駐できるか | ✅ 起動・トレイ常駐・単一インスタンスとも動作 |
| ログオン時の自動起動 | ❌ **MSIX では効かない**（HKCU Run が仮想化される） |
| 設定ファイルの扱い | ⚠️ 既存ユーザーは実フォルダ、新規ユーザーはパッケージ内キャッシュ（アンインストールで消える） |
| 署名済み MSIX のインストール | ❌ 未検証（証明書の信頼に管理者権限が必要） |
| WACK | ❌ 未実行（`appcert.exe` が管理者権限を要求） |
| ストアポリシー（非公開 API） | ⚠️ 未確定（条文は「unsupported ways」を禁止。前例あり／下記） |

## 検証環境

| 項目 | 値 |
| --- | --- |
| OS | Windows 11（`WindowsProductName` は "Windows 10 Pro"、ビルド 26300） |
| 実行ユーザー | 標準ユーザー（管理者グループ所属だが UAC 分割トークン、**非昇格**） |
| 開発者モード | 有効（`AllowDevelopmentWithoutDevLicense=1`、`AllowAllTrustedApps=1`） |
| Windows SDK | 10.0.26100.0（`makeappx.exe` / `signtool.exe`） |
| .NET SDK | 10.0.404 |
| 音声デバイス | 複数のアクティブなレンダー端点（既定: ヘッドホン (Soundcore Space A40)、ほかに USB スピーカー、ディスプレイ音声） |

## 測定方法

署名済み MSIX のインストールは、証明書を信頼させる操作に管理者権限が必要で、この環境では
実行できない（理由は「未検証の項目」に記載）。代わりに **開発者モードのルーズ登録**
（`Add-AppxPackage -Register <レイアウト>\AppxManifest.xml`）を使った。
これは署名検証を伴わないが、**パッケージ ID を持つ本物のパッケージ実行**になり、
アプリコンテナ・レジストリ仮想化・ファイル仮想化・AUMID 起動は本番と同じ経路を通る。

実測には最小構成のプローブ（`tools/msix-probe`）を使った。プローブは製品版と同じ
`GameAudioManager.Core` を参照するので、成功は**製品コードの経路が動いた**ことを意味する。

```powershell
# 1. プローブのシナリオ（モード: route / reset / observe / startup / settings）
#    artifacts\msix-probe-scenario.json に書く。パッケージ内の probe-config.json が
#    このファイルを指すので、再パッケージせずにモードを変えられる。
# 2. パッケージ生成と登録
./scripts/pack-probe-msix.ps1 -Register -ScenarioPath <リポジトリ>\artifacts\msix-probe-scenario.json
# 3. AUMID 起動（パッケージ ID が付与される）
Start-Process explorer.exe -ArgumentList "shell:AppsFolder\Tonbiattack.GameAudioManager.MsixProbe_m8z88z54g2w36!MsixProbe"
# 4. 結果は artifacts\msix-probe-result.json に JSON で出る
# 5. 後片付け
./scripts/pack-probe-msix.ps1 -Unregister
```

## 実測結果

### 1. パッケージ内からの音声ルーティング（本題）

対象 `pwsh.exe` を、既定のヘッドホンから USB スピーカー
`{0.0.0.00000000}.{0fa80fd7-39d7-4164-9c69-e3eac8c51f60}` へ切り替えた。実行はすべて
**パッケージ内プロセス**（`IsPackaged=True`）。

| 手順 | 結果 |
| --- | --- |
| 工場作成（`AudioPolicyConfigRoutingService.IsSupported`） | `True` |
| `IsAvailable` | `True` |
| `SetPreferredDevice("pwsh.exe", <USB スピーカー>)` | `Recorded=True`、`AppliedToLiveSession=False` |
| 戻りメッセージ | `Applied 'スピーカー (4- USB Audio Device)' to pwsh.exe (1 process(es)). Applies when the app next creates an audio session.` |
| 呼び出し直後のセッション | 既存セッションは既定のヘッドホンのまま（Windows の仕様どおり） |
| 対象アプリのセッションを作り直した後 | **`スピーカー (4- USB Audio Device)` に載った** |
| パッケージ外から見たレジストリ | `HKCU\Software\Microsoft\Multimedia\Audio\DefaultEndpoint\96cf3206_0` に `000_000`〜`002_000` として USB スピーカーのパスが書き込まれていた |
| `ResetToDefault("pwsh.exe")`（パッケージ内から） | `Recorded=True` |
| リセット後にセッションを作り直した後 | 既定のヘッドホンへ戻った |

つまり **「パッケージ内から API を呼べる」「OS がパッケージ外に永続化する」「実音声に反映される」
「元に戻せる」の 4 点が実測で揃った。** 以前の仮説（レジストリ仮想化の影響を受けない）は、
この経路については**正しかった**。

補足: 設定の読み戻し（`GetPersistedDefaultAudioEndpoint` 相当）は、このビルドでは
空文字を返した（`GameAudioManager.Core` のコメントにある既知の挙動と一致）。書き込み側の
成否はレジストリと実セッションで判定できるため、実用上の問題にはならない。

### 2. アプリ本体の MSIX 実行

`artifacts\GameAudioManager.msix` を展開したレイアウトを登録し、AUMID で起動した。

| 項目 | 結果 |
| --- | --- |
| 起動 | ✅ プロセスが `...\artifacts\app-package\GameAudioManager.exe` として起動 |
| ウィンドウ | ✅ 表示（1200x720、日本語 UI、ダークテーマ） |
| デバイス列挙 | ✅ 20 端点（アクティブ/未接続/無効を含む）を一覧表示 |
| 音声セッション列挙 | ✅ アプリ一覧と状態が出る（自動適用も動作中と表示） |
| 設定の読み込み | ✅ `%LOCALAPPDATA%\GameAudioManager\settings.json` を読んだ |
| トレイ常駐 | ✅ `CloseMainWindow()` 後もプロセスは生き残り、ウィンドウだけ消えた |
| 単一インスタンス | ✅ AUMID で二重起動してもプロセスは 1 つのまま |

スクリーンショット: `docs/images/msix-app-window.png`（MSIX 実行時の画面）

### 3. 更新とアンインストール

ルーズ登録でバージョンを上げる更新を再現した（`0.2.0.0` → `0.2.1.0`）。

| 項目 | 結果 |
| --- | --- |
| 更新の登録 | ✅ 成功（`-ForceApplicationShutdown` で旧プロセスは終了） |
| 更新後の設定 | ✅ `settings.json` のハッシュが更新前後で同一 |
| 更新後の起動 | ✅ 起動・ウィンドウ表示とも成功 |
| アンインストール | ✅ `Remove-AppxPackage` で実行中プロセスも終了し、パッケージが消えた |
| 実フォルダの設定 | ✅ `%LOCALAPPDATA%\GameAudioManager\settings.json` は残った（下記の理由） |
| パッケージのデータ | ✅ `%LOCALAPPDATA%\Packages\<PFN>` は削除された |

### 4. 自動起動は MSIX では効かない（要修正）

`AutoStartRegistration.Enable()`（`HKCU\...\Run` への書き込み）を**パッケージ内から**実行した。

| 視点 | 結果 |
| --- | --- |
| パッケージ内から `IsEnabled()` | `True`（書けたように見える） |
| パッケージ内から読んだ値 | `"C:\...\artifacts\probe-package\MsixProbe.exe"` |
| **パッケージ外から読んだ値** | **空（存在しない）** |

MSIX のレジストリ仮想化により、`HKCU` への書き込みはパッケージ専用の場所へ移され、
ログオン時の `Run` キーとしては**読まれない**。つまり現状の実装のまま MSIX にすると、
「ログオン時に自動起動」は**チェックしても黙って効かない**。

対処: MSIX では `uap5:StartupTask` 拡張をマニフェストに追加し、アプリから
`Windows.ApplicationModel.StartupTask` で有効化する方式に変える必要がある
（ユーザーは「設定 > アプリ > スタートアップ」で個別に無効化できる）。

### 5. 設定ファイルの保存先が状況で変わる

パッケージ内から `%LOCALAPPDATA%` の 2 か所へ書き込みを試した。

| 書き込み先 | 実際に書かれた場所 | パッケージ外から見えるか |
| --- | --- | --- |
| `%LOCALAPPDATA%\GameAudioManager\`（既に存在するフォルダ） | 実フォルダ（そのまま） | 見える |
| `%LOCALAPPDATA%\GameAudioManagerMsixProbe\`（存在しないフォルダ） | `%LOCALAPPDATA%\Packages\<PFN>\LocalCache\Local\...` | 見えない |

MSIX のファイル仮想化は「既存の実ファイル/フォルダは素通し、新規作成はパッケージ内へ」という
挙動になるため、**同じアプリでも、アップグレードしたユーザーと新規インストールしたユーザーで
設定の保存先が変わる**。

- GitHub Releases 版から移行したユーザー: 実フォルダの設定をそのまま使う（移行不要）
- MSIX が初めてのユーザー: 設定はパッケージ内に作られ、**アンインストールで消える**

MSIX を選ぶ場合は、保存先を明示的に決める必要がある（例: 初回起動時に実フォルダへ移す、
`ApplicationData.Current.LocalFolder` に寄せて「アンインストールで消える」と明記する、
非仮想化リソースを使う）。

### 6. 既存の EXE 版と同時に起動できない

`SingleInstanceGuard` は `Local\GameAudioManager.SingleInstance` というセッション共通の
ミューテックスを使う。MSIX 版と GitHub Releases 版は同じ名前を使うため、
**先に起動している側が勝ち、後から起動した側はウィンドウを出すだけの「2 個目のインスタンス」として終了する**。

実測でも、ローカル版（`%LOCALAPPDATA%\Programs\GameAudioManager`）が常駐している状態で
MSIX 版を AUMID 起動すると、MSIX 版のプロセスは起動後に消え、既存のローカル版のウィンドウが前に出た。

対処: ストア版へ移行する際は「旧 EXE 版を終了・アンインストールしてから MSIX を入れる」手順を
案内する。または、ミューテックス名をパッケージ ID ごとに変える。

## 未検証の項目と、その理由

| 項目 | 状態 | 理由 |
| --- | --- | --- |
| 署名済み MSIX の実インストール（0x800B0109 の解消） | 未検証 | 署名のルート証明書を信頼させる操作に管理者権限が必要。非昇格セッションでは実行できない |
| 未署名 MSIX の `Add-AppxPackage -AllowUnsigned` | 不可 | 公式ドキュメントに、実行ファイルを含む未署名パッケージは**管理者権限が必要**と明記されている。加えてマニフェストに特別な OID が必要（実測では `0x80073D2C`） |
| WACK（Windows App Certification Kit） | 未実行 | `appcert.exe` の起動自体が管理者権限を要求（`要求された操作には管理者特権が必要です`） |
| OS 再起動後の設定反映 | 未検証 | 検証セッションを再起動できない |
| `StartupTask` による自動起動 | 未実装・未検証 | 現状の実装は `HKCU\Run`。MSIX 用の実装がまだ無い |

未署名パッケージの要件（引用）:

> To install an unsigned package, pass the `-AllowUnsigned` flag … In most scenarios, the unsigned
> package will contain executable content; so you'll need to run PowerShell as administrator.
> — [Create an unsigned MSIX package](https://learn.microsoft.com/en-us/windows/msix/package/unsigned-package)（2026-04-15 更新）

## 管理者権限で実行してもらう手順（残作業）

以下は**管理者 PowerShell** で実行する。実行後に結果を Issue #39 へ追記する。

```powershell
# 1. 署名済み MSIX のインストール検証（自己署名でよい。配布用ではない）
./scripts/make-test-msix.ps1 -CreateDevCertificate
# 表示された thumbprint を控える
Export-Certificate -Cert Cert:\CurrentUser\My\<thumbprint> -FilePath $env:TEMP\gam-dev.cer
Import-Certificate -FilePath $env:TEMP\gam-dev.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
# 管理者ではなく通常の PowerShell で
Add-AppxPackage -Path .\artifacts\GameAudioManager.msix
Get-AppxPackage Tonbiattack.GameAudioManager | Remove-AppxPackage
Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object Subject -eq 'CN=GameAudioManager-Dev' | Remove-Item

# 2. WACK（インストール済みの MSIX に対して実行）
& 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe' reset
& 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe' test `
    -packagepath .\artifacts\GameAudioManager.msix -reportoutputpath .\artifacts\wack-report.xml
```

## Store ポリシー（非公開 API）

**結論: MSIX でも「審査が通る」とは言えない。ただし条文は非公開 API の一切を禁じていない。**

現行の Microsoft Store Policies は **7.20（公開 2026-09-15、発効 2026-10-22）**。関係する条文は 10.2.8。

> You are required to use supported methods and must obtain user consent to change any user's
> Windows settings, preferences, settings UI, or modify the user's Windows experience in any way.
> Unsupported methods include but are not limited to use of accessibility APIs or **undocumented or
> unsupported APIs in unsupported ways**.
> — [Microsoft Store Policies](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies)

つまり禁止対象は「未文書化 API を使うこと」そのものではなく、**「サポートされない方法で使うこと」**。
本アプリの使い方は「ユーザーが UI で選んだ出力先を、そのアプリの既定出力として記録する」であり、
ユーザー操作に紐付く。10.2.8 の「同意」要件は満たしやすい設計だが、**審査は個別判断**で、
公式に「この API は可」と明言した文書は見つかっていない。

判断材料:

| 材料 | 内容 |
| --- | --- |
| 前例 | **EarTrumpet が Microsoft Store で配布されている**（発行元 File-New-Project、[Store 掲載](https://apps.microsoft.com/detail/9nblggh516xp)）。GitHub のソースで同じ `Windows.Media.Internal.AudioPolicyConfig` / `SetPersistedDefaultAudioEndpoint` / IID `ab3d4648-…` の使用を確認 |
| WACK | 「Supported API test」があり、インポートアドレス表（IAT）と承認済みプロファイル外の関数を検査する。**full trust の MSIX デスクトップアプリに必須適用されるかは資料上あいまい**。`RoGetActivationFactory` は文字列指定なので IAT には現れない |
| `runFullTrust` | restricted capability。Store 提出時に **Submission options で使用理由の記入と審査が必要**（更新時は原則再審査不要） |
| プライバシーポリシー | 10.5.1 により Desktop Bridge / Win32 製品は**常にプライバシーポリシーが必要**。プロセス名を扱うので用意する |
| 差し戻し時 | 公開 API には「アプリ別既定出力の永続化」に相当するものが無い。代替実装は現実的でない |

申請時に入れるべき内容（推奨）:

1. `runFullTrust` の理由（WPF のフルトラストデスクトップアプリであること）
2. Notes for certification に「使用する API、ユーザー同意のフロー、検証手順、外部依存なし（svcl.exe は削除済み）」を明記
3. EarTrumpet の Store URL と GitHub の一次情報を前例として添付
4. WACK レポートの保全
5. プライバシーポリシー URL（プロセス名は端末内のみで扱い、送信しない旨）

出典:

- [Microsoft Store Policies](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies)（7.20、2026-09-15 公開）
- [Windows App Certification Kit のテスト](https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-app-certification-kit-tests)
- [app capability declarations（runFullTrust）](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations)
- [Submission options の管理](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/manage-submission-options)
- [EarTrumpet の Store 掲載](https://apps.microsoft.com/detail/9nblggh516xp) /
  [音声ポリシー API の利用箇所（GitHub）](https://github.com/File-New-Project/EarTrumpet/blob/master/EarTrumpet/Interop/Helpers/AudioPolicyConfigFactoryImplFor21H2.cs)

## 提出方式の比較（MSIX / EXE・MSI）

| 観点 | MSIX | EXE / MSI（Win32） |
| --- | --- | --- |
| コード署名 | **ストアが再署名**。証明書の購入・PFX・トークン不要 | **提出者が Authenticode 署名**（Microsoft Trusted Root Program の CA チェーン）。自己署名不可、ストアは再署名しない |
| 配布 | ストアの CDN | **自前の HTTPS URL**（バージョン付き・提出後は差し替え不可） |
| インストール | パッケージ導入（UI なし） | **サイレント導入が必須**（EXE はスイッチを申告、MSI は `/qn`）。標準ユーザーで成功すること |
| 更新 | **ストアが管理**（約 24 時間ごとに確認、差分・段階配信） | **ストア経由の自動更新なし**。アプリ側で自己更新を実装 |
| アンインストール | 読み取り専用の WindowsApps とユーザー領域（仮想化） | **痕跡を残さないこと**が認証項目 |
| 審査 | ストア認証。WACK はローカル推奨 | ストア認証。WACK は「強く推奨」だが必須とは明記されていない |
| 主なコスト | 開発者登録（新規フローは $0）。署名は $0 | OV 証明書 約 $150–300/年、EV 約 $400+/年、または Azure Artifact Signing（Basic $9.99/月〜） |

出典: [Code signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)（2026-11-10 更新）、
[MSI/EXE パッケージ要件](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements)、
[Win32 アプリをストアで配布する](https://learn.microsoft.com/en-us/windows/apps/distribute-through-store/how-to-distribute-your-win32-app-through-microsoft-store)（2026-07-11 更新）、
[MSIX のパッケージ管理](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-package-management)、
[Azure Artifact Signing の料金](https://azure.microsoft.com/en-us/pricing/details/artifact-signing/)。

注意:

- 料金・登録料は**時期で変わる**。新規フローの登録料 $0 は 2026-11 時点の情報で、
  更新料の扱いは公式に明記が見当たらない（申請直前に Partner Center で確認する）。
- Azure Artifact Signing の **Store 提出での可否は資料が矛盾**して読める（Store eligible と読める記述と、
  そう読めない記述がある）。EXE/MSI を選ぶ場合は OV 証明書を前提に考えるのが安全。
- 実際に Store で MSIX と EXE/MSI の両方を同一製品として配布している例は確認できなかった。

## 配布方式の決定

実測と調査を踏まえ、次の方針とする。

1. **GitHub Releases の自己完結 EXE を維持する**（主配布。既存の出力先変更機能は削除しない）
2. **Microsoft Store へ出す場合は MSIX 方式を採る。EXE/MSI 方式は採用しない**
   - 理由: ストアが再署名するため証明書購入が不要、更新をストアが管理、パッケージ生成は既に動作、
     そして**コア機能（アプリ別出力先変更）がパッケージ内で動くことを実測で確認済み**
   - EXE/MSI 方式は CA 署名・不変 HTTPS URL・サイレント導入・自己更新のすべてを自前で満たす必要があり、
     同じ非公開 API の審査リスクを負ったうえで運用コストだけが増える
3. **提出は次の前提が揃ってから。揃わない限り提出しない**（いずれも未達なら審査通過は保証できない）
   - 非公開 API の扱いについて、Notes for certification で説明できる材料が揃っていること
   - MSIX 対応の改修（自動起動・設定保存先・単一インスタンス）が完了していること
   - 署名済み MSIX の実インストールと WACK を管理者権限で実施し、結果を記録していること
4. 既存ユーザーの移行手順（旧 EXE 版の終了・アンインストール → MSIX 導入）は
   **まだ用意していない**。#35 のチェックリストとして残す

**この決定は「MSIX なら審査が通る」ことを意味しない。** 非公開 API の利用は 10.2.8 の
「unsupported ways」に該当すると判断される可能性が残る。最終的な提出可否は所有者の判断とする。

## MSIX 採用時に必要な改修（提出前の前提）

1. `uap5:StartupTask` 拡張の追加と、`AutoStartRegistration` の MSIX 対応（自動起動）
2. 設定ファイルの保存先ポリシーの決定と、既存ユーザー向けの移行処理
3. 単一インスタンスのミューテックス名をパッケージ対応にする、または移行手順の明記
4. 署名済み MSIX のサイドロード検証（**テスト用のみ**。ストア提出はストアが再署名するため、
   配布用の OV/EV 証明書は不要）
5. `Partner Center` の予約名に合わせた `Identity Name` / `Publisher` の確定
6. WACK の実行と結果の記録（管理者権限）
7. `runFullTrust` の使用理由と、非公開 API の説明を提出時に記入できるようにする
8. プライバシーポリシーの用意（10.5.1 により Desktop Bridge 製品は必須）

## 再現に使ったファイル

| パス | 役割 |
| --- | --- |
| `tools/msix-probe/` | 測定用の最小アプリ（製品版 `GameAudioManager.Core` を参照） |
| `packaging/Probe/AppxManifest.xml` | プローブ用の最小マニフェスト（`runFullTrust` のみ） |
| `scripts/pack-probe-msix.ps1` | 発行 → パッケージ生成 → 登録 / 解除 |
