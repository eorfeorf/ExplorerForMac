# アーキテクチャ

アプリはAppKitで構築し、画面とファイルシステム処理を分離する。

```text
AppDelegate / MainWindowController
├── TabBar + AddressBar
├── BrowserViewController
│   ├── FolderTreeViewController
│   ├── FileListViewController
│   └── PreviewViewController
├── DirectoryService + DirectoryWatcher
├── FileItem + NavigationHistory
└── SessionStore
```

`DirectoryService`は並行キューでURLのリソース情報を読み取り、結果だけをメインキューへ返す。`DirectoryWatcher`は現在のフォルダーを監視し、短時間に連続した変更をまとめて一覧を再読み込みする。

各タブは独立した`NavigationHistory`と`BrowserViewController`を持つ。`SessionStore`はURL履歴、選択タブ、隠しファイル設定だけを`UserDefaults`へ保存し、ファイル内容やセキュリティスコープ情報は保存しない。
