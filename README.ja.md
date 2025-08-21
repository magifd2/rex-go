# rex-go

`rex-go` は、テキストデータから正規表現を使ってフィールドを抽出し、JSON形式で出力するコマンドラインツールです。Splunkの `rex` コマンドのように、ログファイルなどの非構造化テキストから構造化データを手軽に作成することを目的としています。

このツールはGo言語で書かれており、単一の実行ファイルとしてクロスプラットフォームで動作します。

---

## 特徴

- **柔軟な入出力**: 標準入力（パイプ）またはファイルからの入力をサポートし、結果を標準出力またはファイルへ書き出せます。
- **複数の正規表現**: コマンドライン (`-r`) や設定ファイル (`-f`) から複数の正規表現パターンを指定できます。
- **結果のマージ**: 指定されたすべての正規表現が入力の各行に適用され、マッチした結果は1つのJSONオブジェクトにマージされます。
- **複数値の配列化**: 複数のパターンで同じフィールド名がキャプチャされた場合、そのフィールドの値は自動的に配列にまとめられます。
- **値のユニーク化**: `-u` オプションを使用することで、配列化された値の重複を排除できます。
- **ポータブル**: Goの実行環境がないマシンでも動作する、単一の実行可能ファイルを生成します。

---

## インストールとビルド

Go言語の環境がセットアップされている必要があります。

ビルドされるバイナリのバージョンは、gitタグから自動的に決定されます。例えば、最新のタグが `v1.0.0` の場合、バイナリのバージョンは `v1.0.0` となります。コミットされていない変更がある場合は、`-dirty` サフィックスが追加されます（例: `v1.0.0-dirty`）。

`make` コマンドを実行するだけでアプリケーションをビルドできます。以下のターゲットが利用可能です。

- **`make build`**: 現在のOSとアーキテクチャ向けの実行ファイルを `dist/` ディレクトリにビルドします。
- **`make all`**: 全てのターゲットプラットフォーム（Linux, Windows, macOS）向けにクロスコンパイルを行い、`dist/` 内の各プラットフォーム用サブディレクトリにバイナリを配置します。

- **`make package`**: 全てのバイナリをビルドし、各プラットフォーム向けに圧縮アーカイブ（Windows向けは.zip、Linux/macOS向けは.tar.gz）を `dist/archives/` ディレクトリに作成します。これらのアーカイブは配布準備ができています。
- **`make clean`**: `dist/` ディレクトリと全てのビルド成果物を削除します。

通常は `make all` を実行すれば、配布用の全ファイルが生成されます。バイナリを配布する予定がある場合は、`make package` を推奨します。

---

## 使い方

### コマンドラインオプション

```
Usage of rex-go:
A command-line tool to extract and merge fields from text using all specified regex patterns.

  -f string
    	Path to a JSON file containing an array of regex patterns.
  -i string
    	Input file path (default: stdin).
  -o string
    	Output file path (default: stdout).
  -r value
    	Regular expression with named capture groups. Can be specified multiple times.
  -u	Ensure that values for a multi-valued field are unique.
  --version
      Show version information and exit.
```

### 使用例

#### 1. 基本的な抽出

Apacheのアクセスログから情報を抽出します。

```bash
echo '127.0.0.1 - frank [10/Oct/2000] "GET /api" 200' | \
./rex-go -r '(?P<client_ip>[^ ]+) - (?P<user>[^ ]+) \[(?P<date>[^\]]+)\] "(?P<method>\w+) (?P<uri>[^ "]+)" (?P<status>\d{3})'
```

**出力:**
```json
{"client_ip":"127.0.0.1","date":"10/Oct/2000","method":"GET","status":"200","uri":"/api","user":"frank"}
```

#### 2. 複数のパターンで結果をマージ

1行のログから、異なる正規表現を使って `level` と `status` の両方を抽出します。

```bash
echo "request failed with level=error, status=500" | \
./rex-go -r 'level=(?P<level>\w+)' -r 'status=(?P<status>\d+)'
```

**出力:**
```json
{"level":"error","status":"500"}
```

#### 3. 複数値を配列にまとめる

`user=` と `alias=` の両方から `name` という共通のフィールド名で値を抽出し、配列にまとめます。

```bash
echo "user=admin, alias=root" | \
./rex-go -r 'user=(?P<name>\w+)' -r 'alias=(?P<name>\w+)'
```

**出力:**
```json
{"name":["admin","root"]}
```

#### 4. 配列の値をユニークにする (`-u` オプション)

重複する値が含まれる場合でも、`-u` フラグを付けることでユニークな値のみを配列に格納します。

```bash
echo "user=admin, alias=root, user=admin" | \
./rex-go -u -r 'user=(?P<name>\w+)' -r 'alias=(?P<name>\w+)'
```

**出力:**
```json
{"name":["admin","root"]}
```

#### 5. 設定ファイルを使う (`-f` オプション)

`patterns.json` という名前で以下のファイルを作成します。

```json
{
  "patterns": [
    "level=(?P<level>\\w+)",
    "status=(?P<status>\\d+)"
  ]
}
```

このファイルを `-f` オプションで指定して実行します。

```bash
echo "level=info, status=200" | ./rex-go -f patterns.json
```

**出力:**
```json
{"level":"info","status":"200"}
```
---

## ライセンス

このプロジェクトは [MITライセンス](https://opensource.org/licenses/MIT) の下で公開されています。
