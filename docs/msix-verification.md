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
| ログオン時の自動起動 | ✅ `StartupTask` へ移行して実測済み（#58。Run キーは仮想化されて効かない） |
| 設定ファイルの扱い | ✅ LocalState に統一し、EXE 版から初回取り込み（#58） |
| EXE 版との共存 | ✅ ミューテックスを分離し、同時起動できることを実測（#58） |
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
| 設定の読み込み | ✅ パッケージの LocalState に作成し、EXE 版の設定を初回に取り込んだ（#58） |
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
| 設定の引き継ぎ | ✅ パッケージの LocalState に EXE 版と同じ内容を作成（ハッシュ一致） |
| パッケージのデータ | ✅ `%LOCALAPPDATA%\Packages\<PFN>` は削除された |

### 4. 自動起動を StartupTask へ移行（#58 で修正・再実測）

**修正前（実測）**: `AutoStartRegistration.Enable()`（`HKCU\...\Run` への書き込み）をパッケージ内から
実行すると、パッケージ内では `IsEnabled()=True` と読めたのに、**パッケージ外からは値が存在しなかった**。
MSIX のレジストリ仮想化で `HKCU` の書き込みがパッケージ専用の場所へ移り、ログオンの `Run` としては
読まれないため、チェックしても黙って効かない状態だった。

**対応**:

- マニフェストに `uap5:Extension Category="windows.startupTask"` を宣言（`Enabled="false"`）
- アプリは `Windows.ApplicationModel.StartupTask`（`RequestEnableAsync` / `Disable`）で状態を変える
- EXE 版は従来どおり `HKCU\...\Run`（`RunKeyStartupRegistration`）

マニフェストの注意点: この拡張は **`<Application>` の子**に置く必要がある。`<Package>` 直下の
`<Extensions>` に入れると `makeappx` が `C00CE014: The app manifest must be valid as per schema` で
失敗する（実測）。

**再実測（パッケージ内の UI トグルを UI Automation で操作）**:

| 操作 | 結果 |
| --- | --- |
| 初期状態 | チェック Off、`State=0` |
| オンにする | チェック On、`State=2`、`settings.json` の `autoStartWithWindows=true`、**`HKCU\...\Run` には値が作られない** |
| アプリを再起動 | チェック On のまま（OS の状態から復元） |
| オフにする | チェック Off、`State=0`、設定も false |
| Windows 側で無効化（`State=1` を再現）してオンにする | OS が拒否し、チェックは Off のまま。「設定 > アプリ > スタートアップ」を促すメッセージを表示 |
| EXE 版でオンにする | 従来どおり `HKCU\...\Run` に `"<パス>"` が入り、オフで消える |

状態は `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\<PFN>\GameAudioManagerStartup`
の `State`（0=無効 / 1=ユーザーが無効化 / 2=有効）に保存される。タスク マネージャーの
「スタートアップ」タブにもこのタスクが並び、ユーザーがアプリを開かずに無効化できる。

### 5. 設定の保存先（#58 で決定）

**実測（修正前）**: パッケージ内から `%LOCALAPPDATA%` の 2 か所へ書き込みを試した。

| 書き込み先 | 実際に書かれた場所 | パッケージ外から見えるか |
| --- | --- | --- |
| `%LOCALAPPDATA%\GameAudioManager\`（既に存在するフォルダ） | 実フォルダ（そのまま） | 見える |
| `%LOCALAPPDATA%\GameAudioManagerMsixProbe\`（存在しないフォルダ） | `%LOCALAPPDATA%\Packages\<PFN>\LocalCache\Local\...` | 見えない |

MSIX のファイル仮想化は「既存の実ファイル/フォルダは素通し、新規作成はパッケージ内へ」なので、
**アップグレードしたユーザーと新規インストールしたユーザーで保存先が変わってしまう**状態だった。

**決定と実装**:

| チャネル | 保存先 |
| --- | --- |
| GitHub Releases（EXE） | `%LOCALAPPDATA%\GameAudioManager\settings.json`（従来のまま） |
| Store（MSIX） | `%LOCALAPPDATA%\Packages\<PFN>\LocalState\GameAudioManager\settings.json` |

- パッケージの `LocalState` は更新で残り、アンインストールで消える（ストアの期待どおり）
- 初回起動時、MSIX 側に設定が無く EXE 版の設定がある場合だけ**コピーして引き継ぐ**
  （上書きしない・EXE 版のファイルは消さない・壊れていたら何もしない）
- 実測: 初回起動後に LocalState の `settings.json` が作られ、EXE 版と**ハッシュが一致**した

### 6. 単一インスタンスをチャネルごとに分離（#58 で修正・再実測）

**修正前**: `Local\GameAudioManager.SingleInstance` を両チャネルで共有していたため、
先に起動している側が勝ち、後から起動した側はウィンドウを出すだけで終了した。

**対応**: パッケージ版は `Local\GameAudioManager.SingleInstance.<PFN>` を使う。

**再実測**: EXE 版（`%LOCALAPPDATA%\Programs\...`）と MSIX 版が**同時に 2 プロセスで共存**した。
同じチャネル内の二重起動は従来どおり 1 プロセスのまま（2 個目は既存のウィンドウを前面に出す）。

注意: 同時起動は同じ設定を奪い合うので推奨しない（同じアプリの出力先を両方が書き換える）。
移行時は旧 EXE 版を終了・アンインストールする手順を案内する（README に追記）。

### 7. パッケージ ID（Partner Center の予約値と一致）

#58 に記載された予約値で作成し、実測で一致を確認した。

| 項目 | 値 |
| --- | --- |
| Identity Name | `tonbiattack.GameAudioManager`（旧 `Tonbiattack…` から変更） |
| Publisher | `CN=2F14A66E-02DF-43E2-93E0-5C5900B38D2E` |
| Package Family Name | `tonbiattack.GameAudioManager_e28ksxe3fc9w4`（予約値と一致） |
| Package Full Name | `tonbiattack.GameAudioManager_0.2.0.0_x64__e28ksxe3fc9w4` |

Publisher を実値にしたため、`scripts/pack-msix.ps1` の既定値も同じ値に変更した。
自己署名でサイドロードする場合は `make-test-msix.ps1` が証明書のサブジェクトで上書きする。


## 未検証の項目と、その理由

| 項目 | 状態 | 理由 |
| --- | --- | --- |
| 署名済み MSIX の実インストール（0x800B0109 の解消） | 未検証 | 署名のルート証明書を信頼させる操作に管理者権限が必要。非昇格セッションでは実行できない |
| 未署名 MSIX の `Add-AppxPackage -AllowUnsigned` | 不可 | 公式ドキュメントに、実行ファイルを含む未署名パッケージは**管理者権限が必要**と明記されている。加えてマニフェストに特別な OID が必要（実測では `0x80073D2C`） |
| WACK（Windows App Certification Kit） | 未実行 | `appcert.exe` の起動自体が管理者権限を要求（`要求された操作には管理者特権が必要です`） |
| OS 再起動後の設定反映 | 未検証 | 検証セッションを再起動できない |
| `StartupTask` のログオン時実際の起動 | 未検証 | 有効化（`State=2`）までは実測したが、サインアウト/再起動できないため実際の自動起動は未確認 |

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
4. 既存ユーザーの移行手順（旧 EXE 版の終了・アンインストール → MSIX 導入）は README に記載した
   （設定は初回起動で自動取り込み、自動起動は入れ直し）

**この決定は「MSIX なら審査が通る」ことを意味しない。** 非公開 API の利用は 10.2.8 の
「unsupported ways」に該当すると判断される可能性が残る。最終的な提出可否は所有者の判断とする。

## MSIX 採用時に必要な改修（提出前の前提）

1. ~~`uap5:StartupTask` 拡張の追加と、`AutoStartRegistration` の MSIX 対応（自動起動）~~ → #58 で完了
2. ~~設定ファイルの保存先ポリシーの決定と、既存ユーザー向けの移行処理~~ → #58 で完了
3. ~~単一インスタンスのミューテックス名をパッケージ対応にする~~ → #58 で完了（移行手順は README）
4. ~~`Partner Center` の予約名に合わせた `Identity Name` / `Publisher` の確定~~ → 予約値に更新し、PFN の一致を実測
5. 署名済み MSIX のサイドロード検証（**テスト用のみ**。ストア提出はストアが再署名するため、
   配布用の OV/EV 証明書は不要）
6. WACK の実行と結果の記録（管理者権限）
7. `runFullTrust` の使用理由と、非公開 API の説明を提出時に記入できるようにする
8. プライバシーポリシーの用意（10.5.1 により Desktop Bridge 製品は必須）

## 再現に使ったファイル

| パス | 役割 |
| --- | --- |
| `tools/msix-probe/` | 測定用の最小アプリ（製品版 `GameAudioManager.Core` を参照） |
| `packaging/Probe/AppxManifest.xml` | プローブ用の最小マニフェスト（`runFullTrust` のみ） |
| `scripts/pack-probe-msix.ps1` | 発行 → パッケージ生成 → 登録 / 解除 |
| `src/GameAudioManager.Core/Packaging/AppIdentity.cs` | パッケージ判定と、設定パス・ミューテックス名の解決 |
| `src/GameAudioManager.Core/Startup/StartupRegistration.cs` | 自動起動の抽象化と `HKCU\Run` 実装 |
| `src/GameAudioManager.App/Startup/StartupTaskRegistration.cs` | MSIX の `StartupTask` 実装（WinRT） |
| `src/GameAudioManager.Core/Configuration/SettingsMigration.cs` | EXE 版からの設定取り込み |
