# Explorer for Mac

Windows Explorer の情報設計と操作感を macOS ネイティブ UI で実現するファイルブラウザーです。現在は安全な読み取り専用版です。

## 現在の機能

- フォルダーツリー、詳細一覧、プレビューペインの3ペイン表示
- 戻る、進む、上へ移動、パスの直接入力
- 複数タブと再起動後のセッション復元
- 名前、更新日時、種類、サイズによる並べ替え
- 隠しファイルの表示切り替え
- フォルダー変更の自動反映
- 複数選択、Quick Look、Finderで表示、パスのコピー
- 外付けボリュームの表示

## ビルド

Xcode で `ExplorerForMac.xcodeproj` を開き、`ExplorerForMac` スキームを実行します。コマンドラインでは次のように検証できます。

```sh
xcodebuild -project ExplorerForMac.xcodeproj -scheme ExplorerForMac CODE_SIGNING_ALLOWED=NO build
swift test
```

この段階ではコピー、移動、名前変更、削除などの書き込み操作を意図的に実装していません。

## macOSのフォルダーアクセス許可

Desktop、Documents、DownloadsはmacOSが保護するフォルダーです。本アプリは、起動時やサイドバー表示時にはこれらへアクセスせず、ユーザーが実際に開いた時だけ内容を読み取ります。

macOSによる初回の許可確認自体はアプリから無効化できません。何度も確認される場合は、Apple Development証明書で安定してコード署名するか、アプリメニューの「フルディスクアクセス設定を開く…」から一度だけ許可してください。署名なしの開発ビルドは、再ビルド後にmacOSから別の実行ファイルとして扱われる場合があります。
