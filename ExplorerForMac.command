#!/bin/bash

set -euo pipefail

show_message() {
    /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
    display dialog (item 1 of argv) with title "Explorer for Mac" buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

app_path=$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
try
    set selectedFile to choose folder with prompt "起動する Explorer for Mac.app を選択してください。"
    return POSIX path of selectedFile
on error number -128
    return ""
end try
APPLESCRIPT
)
app_path="${app_path%/}"

if [[ -z "$app_path" ]]; then
    exit 0
fi

if [[ ! -d "$app_path" || "$app_path" != *.app ]]; then
    show_message "選択した項目はアプリではありません。Explorer for Mac.app を選択してください。"
    exit 1
fi

info_plist="$app_path/Contents/Info.plist"
if [[ ! -f "$info_plist" ]]; then
    show_message "アプリの情報を読み取れませんでした。Explorer for Mac.app を選択してください。"
    exit 1
fi

bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)
if [[ "$bundle_identifier" != "com.example.ExplorerForMac" ]]; then
    show_message "選択したアプリは Explorer for Mac ではありません。何も変更していません。"
    exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
    show_message "アプリの署名整合性を確認できませんでした。安全のため何も変更していません。"
    exit 1
fi

app_name=$(/usr/bin/basename "$app_path")
if ! choice=$(/usr/bin/osascript - "$app_name" "$app_path" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set appName to item 1 of argv
    set appPath to item 2 of argv
    set messageText to appName & " を開きます。" & return & return & ¬
        "初回起動のため、このアプリ本体の隔離属性（com.apple.quarantine）を解除します。" & return & ¬
        "対象: " & appPath & return & return & ¬
        "これはAppleによる公証や開発元の確認を代替しません。信頼できる入手元のアプリの場合だけ続けてください。"
    set resultDialog to display dialog messageText with title "Explorer for Mac" with icon caution ¬
        buttons {"キャンセル", "確認して開く"} default button "キャンセル" cancel button "キャンセル"
    return button returned of resultDialog
end run
APPLESCRIPT
); then
    exit 0
fi

if [[ "$choice" != "確認して開く" ]]; then
    exit 0
fi

# Remove quarantine metadata only inside the selected Explorer for Mac bundle.
while IFS= read -r -d '' item_path; do
    if /usr/bin/xattr -p com.apple.quarantine "$item_path" >/dev/null 2>&1; then
        if ! /usr/bin/xattr -d com.apple.quarantine "$item_path" >/dev/null 2>&1; then
            show_message "隔離属性を解除できませんでした。アプリをApplicationsフォルダーへコピーしてから、もう一度実行してください。"
            exit 1
        fi
    fi
done < <(/usr/bin/find "$app_path" -print0)

if ! /usr/bin/open "$app_path"; then
    show_message "アプリを起動できませんでした。Applicationsフォルダーにある Explorer for Mac.app を選び直してください。"
    exit 1
fi
