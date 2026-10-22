<p align="center">
  <img src="Resources/AppIcon-source.png" alt="Mercury icon" width="128" height="128">
</p>

# Mercury

[English](README.md) | **日本語**

Gmail に新着メールが届いた瞬間に、macOS のネイティブ通知でお知らせする、小さな無料のオープンソース
メニューバーアプリです。IMAP の **IDLE** で受信を監視するので、ポーリングも Mail.app の起動も不要。
Dock アイコンなし、テレメトリなしです。

## 機能

- 即時通知（Gmail からプッシュされるので待ち時間なし）
- Gmail アカウントを最大 2 つまで対応。未読数をメニューバーに表示
- 最近のメール一覧：未読を先頭に、または時系列で表示
- メールごとのクイックアクション：フラグ、既読/未読、認証コードのコピー、本文中のリンク選択
- スワイプ操作パネル（ベータ）：Mail.app のように 2 本指でメールをスワイプ。Liquid Glass 風の見た目もオプションで選択可
- Mail.app または Gmail で開く、グローバルショートカット、通知の一時停止、ログイン時に起動

## インストール

**ダウンロード：** [Releases](../../releases) から最新の `Mercury.dmg` を入手して開き、`Mercury` を
`Applications` にドラッグします。Apple による署名と公証済みのため、追加の操作なしで開けます。

**自分でビルドする**（Xcode Command Line Tools のみ必要）：

```bash
git clone https://github.com/FireBarret/mercury.git
cd mercury
./build_app.sh
open build/Mercury.app
```

## セットアップ

サードパーティ製アプリから Gmail を使うには **アプリパスワード** が必要です。

1. [2 段階認証プロセス](https://myaccount.google.com/signinoptions/two-step-verification)を有効にする
2. [アプリパスワード](https://myaccount.google.com/apppasswords)を作成する
3. Mercury を開き、Gmail アドレスとアプリパスワードを入力して **Save & Connect** をクリック

## 使い方

- メニューバーのアイコンをクリックすると、最近のメール、**Check Now**、**Open Gmail**、
  **Pause Notifications**、**Mark All as Read**、**Preferences** が表示されます。
- 通知をクリックすると、そのメールが開きます。開く先（Mail.app かブラウザの Gmail）は環境設定で選べます。
- 新着時に Mail.app をバックグラウンドで更新することもできます（環境設定 →「When new mail arrives」）。
  初回のみ、Mercury が Mail を操作することを許可するよう macOS が確認します。
- グローバルショートカットは 環境設定 → General で設定できます。
- **スワイプ操作パネル（ベータ）：** 環境設定 → General でオンにします。メールを左右にスワイプすると
  アクションが現れ、大きくスワイプすると外側のアクションが実行されます。割り当てるアクションは自由に選べます。
  ⌘, で環境設定、Esc でパネルを閉じます。

通知が表示されない場合は、システム設定 → 通知 → Mercury を確認してください。
画面共有中は macOS が通知バナーを自動的に抑制します。

## プライバシー

- アプリパスワードは macOS のキーチェーンに保存されます。
- Mercury が通信するのは TLS 接続の `imap.gmail.com`、Mail.app、ローカル設定のみです。
  解析ツールやサードパーティのサーバーは使いません。
- オープンソースで、小規模・依存ライブラリなし。サンドボックスなし、公証なしです。

## コントリビュート

Issue や PR を歓迎します。小さく、依存なしの方針を保ってください。

## ライセンス

[MIT](LICENSE)
