# Piano Loudness

CP88 などの USB オーディオで録った動画の音量が小さいとき、動画のまま音声だけを
レベル調整・コンプレッサー・リミッター・ラウドネス正規化して書き出す iOS アプリ。

## 処理

音声のみ処理し、映像は再エンコードせずそのまま結合する。

```
入力ゲイン -> コンプレッサー -> ラウドネス正規化(目標 LUFS) -> リミッター -> AAC 256kbps
```

- ラウドネス測定: ITU-R BS.1770-4 (K 特性、ゲーティング付き)
- リミッター: ルックアヘッド型、天井は既定 -1 dBFS
- プリセット: Natural(-14 LUFS)、Loud(-12 LUFS)、Gain only

## ビルド

要 Xcode 16 以降と [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```
brew install xcodegen
xcodegen generate
open PianoLoudness.xcodeproj
```

`project.yml` の `bundleIdPrefix` と bundle ID は自分のものに変更すること。
テストは Xcode の Cmd+U、または GitHub Actions (`.github/workflows/ci.yml`)。

## 構成

- `Sources/PianoLoudness/Audio` — DSP と動画の読み書き (UI 非依存)
- `Sources/PianoLoudness/App` — SwiftUI 画面
- `Tests/PianoLoudnessTests` — DSP のユニットテスト
