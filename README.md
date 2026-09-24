# Explorer for Mac

Windows Explorer の情報設計と操作感を macOS ネイティブ UI で実現するファイルブラウザーです。

## 現在の機能

- フォルダーツリー、詳細一覧、プレビューペインの3ペイン表示
- 戻る、進む、上へ移動、パスの直接入力
- 複数タブ、タブの新しいウインドウへの分離、再起動後のセッション復元
- 名前、更新日時、種類、サイズによる並べ替え
- 隠しファイルの表示切り替え
- フォルダー変更の自動反映
- 複数選択、Quick Look、Finderで表示、パスのコピー
- 現在のフォルダー内の名前検索、ターミナルで開く
- Windows風のパンくずパスとコンテキストメニュー
- 右クリックメニューからの新しいフォルダー作成
- Finder機能拡張から、Finderで表示中のフォルダーを開く
- 外付けボリュームの表示

## Finder機能拡張

アプリをApplicationsフォルダーへ入れたあと、アプリメニューの「Finder機能拡張を管理…」を開き、`Explorer for Mac Finder Extension`を有効にします。Finderのツールバーボタン、またはフォルダー内のコンテキストメニューから、現在のフォルダーをExplorer for Macの新しいタブで開けます。

## 主なキーボード操作

| 操作 | ショートカット |
| --- | --- |
| 戻る | `Command + ←` |
| 進む | `Command + →` |
| 1階層上へ | `Command + ↑` |
| パスを入力 | `Command + L` |
| 現在のフォルダーを検索 | `Command + F` |
| 新規タブ | `Command + T` |
| Quick Look | `Space` |

## ビルド

macOS 13以降が必要です。Xcodeで `ExplorerForMac.xcodeproj` を開き、`ExplorerForMac` スキームを実行します。コマンドラインでは次のように検証できます。

```sh
xcodebuild -project ExplorerForMac.xcodeproj -scheme ExplorerForMac CODE_SIGNING_ALLOWED=NO build
swift test
```

現在の書き込み操作は新しいフォルダーの作成と、項目をゴミ箱へ移動する削除操作です。コピー、移動、名前変更はまだ実装していません。

## 配布用ファイルの作成

他のMacへ配布するZIP・DMG・チェックサムは、macOS上で次のコマンドから作成できます。

```sh
./scripts/build-release.sh
```

`artifacts/` にApple Silicon（arm64）とIntel（x86_64）両対応のUniversal 2アプリが生成されます。DMGを開き、`Explorer for Mac.app` を `Applications` へドラッグしてください。現在のビルドはアドホック署名のため、初回起動時にアプリを右クリックして「開く」を選ぶ必要があります。Finder機能拡張は、アプリメニューの「Finder機能拡張を管理…」から有効にしてください。

Gatekeeperの警告なしで配布するには、Apple Developer ProgramのDeveloper ID Application証明書で署名し、Appleへ公証（notarization）する必要があります。署名済み環境では、次のように証明書名を渡してビルドできます。

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-release.sh
```

## macOSのフォルダーアクセス許可

Desktop、Documents、DownloadsはmacOSが保護するフォルダーです。本アプリは、起動時やサイドバー表示時にはこれらへアクセスせず、ユーザーが実際に開いた時だけ内容を読み取ります。

macOSによる初回の許可確認自体はアプリから無効化できません。何度も確認される場合は、Apple Development証明書で安定してコード署名するか、アプリメニューの「フルディスクアクセス設定を開く…」から一度だけ許可してください。署名なしの開発ビルドは、再ビルド後にmacOSから別の実行ファイルとして扱われる場合があります。

## ライセンス

[MIT License](LICENSE)
