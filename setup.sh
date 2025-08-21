#!/bin/bash

# ==============================================================================
# rex-go Project Generator
#
# This script generates all the necessary source files for the rex-go project:
# - main.go: The main application source code.
# - Makefile:  The build script for cross-compilation.
# - README.md: The project's documentation in English.
# - README.ja.md: The project's documentation in Japanese.
#
# Just run this script in an empty directory to set up the project.
# ==============================================================================

set -e

# --- Function to create main.go ---
create_main_go() {
    echo "--> Generating main.go..."
    cat << 'EOF' > main.go
// main.go
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"regexp"
)

// stringSlice is a custom type for handling multiple -r flags.
type stringSlice []string

func (s *stringSlice) String() string {
	return fmt.Sprintf("%v", *s)
}

func (s *stringSlice) Set(value string) error {
	*s = append(*s, value)
	return nil
}

// DefinitionFile is the struct for the JSON definition file.
type DefinitionFile struct {
	Patterns []string `json:"patterns"`
}

// version is set by the build process using ldflags
var version = "dev"

func main() {
	// --- Define command-line flags ---
	var regexPatterns stringSlice
	flag.Var(&regexPatterns, "r", "Regular expression with named capture groups. Can be specified multiple times.")
	configFile := flag.String("f", "", "Path to a JSON file containing an array of regex patterns.")
	inputFile := flag.String("i", "", "Input file path (default: stdin).")
	outputFile := flag.String("o", "", "Output file path (default: stdout).")
	uniqueValues := flag.Bool("u", false, "Ensure that values for a multi-valued field are unique.")
	showVersion := flag.Bool("version", false, "Show version information and exit.")

	// --- Customize help message ---
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage of %s:\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "A command-line tool to extract and merge fields from text using all specified regex patterns.\n\n")
		flag.PrintDefaults()
	}

	flag.Parse()

	if *showVersion {
		fmt.Printf("rex-go version %s\n", version)
		os.Exit(0)
	}

	// --- Load regex patterns from config file ---
	if *configFile != "" {
		file, err := os.Open(*configFile)
		if err != nil {
			log.Fatalf("Error: Could not open config file %s: %v", *configFile, err)
		}
		defer file.Close()

		var defs DefinitionFile
		decoder := json.NewDecoder(file)
		if err := decoder.Decode(&defs); err != nil {
			log.Fatalf("Error: Could not parse config file %s: %v", *configFile, err)
		}
		regexPatterns = append(regexPatterns, defs.Patterns...)
	}

	// --- Check for required flags ---
	if len(regexPatterns) == 0 {
		log.Println("Error: At least one regex pattern must be provided via -r or -f flag.")
		flag.Usage()
		os.Exit(1)
	}

	// --- Compile all regex patterns ---
	var compiledRegexes []*regexp.Regexp
	for _, pattern := range regexPatterns {
		re, err := regexp.Compile(pattern)
		if err != nil {
			log.Fatalf("Error: Invalid regular expression '%s': %v", pattern, err)
		}
		if len(re.SubexpNames()) <= 1 {
			log.Fatalf("Error: Regex '%s' must contain at least one named capture group.", pattern)
		}
		compiledRegexes = append(compiledRegexes, re)
	}

	// --- Set up input source ---
	var reader io.Reader
	if *inputFile != "" {
		file, err := os.Open(*inputFile)
		if err != nil {
			log.Fatalf("Error: Could not open input file %s: %v", *inputFile, err)
		}
		defer file.Close()
		reader = file
	} else {
		reader = os.Stdin
	}

	// --- Set up output destination ---
	var writer io.Writer
	if *outputFile != "" {
		file, err := os.Create(*outputFile)
		if err != nil {
			log.Fatalf("Error: Could not create output file %s: %v", *outputFile, err)
		}
		defer file.Close()
		writer = file
	} else {
		writer = os.Stdout
	}

	// --- Run the main processing logic ---
	if err := processLines(writer, reader, compiledRegexes, *uniqueValues); err != nil {
		log.Fatalf("Error during processing: %v", err)
	}
}

// processLines reads from the input line by line, applies all regexes to merge results, and outputs as JSON.
// If the unique flag is true, values in arrays will be unique.
func processLines(writer io.Writer, reader io.Reader, regexes []*regexp.Regexp, unique bool) error {
	scanner := bufio.NewScanner(reader)

	for scanner.Scan() {
		line := scanner.Text()
		combinedResult := make(map[string]interface{})

		for _, re := range regexes {
			matches := re.FindStringSubmatch(line)
			if matches == nil {
				continue
			}

			fieldNames := re.SubexpNames()
			for i, name := range fieldNames {
				if i != 0 && name != "" {
					newValue := matches[i]

					if existingValue, ok := combinedResult[name]; ok {
						if slice, isSlice := existingValue.([]string); isSlice {
							shouldAppend := true
							if unique {
								for _, v := range slice {
									if v == newValue {
										shouldAppend = false
										break
									}
								}
							}
							if shouldAppend {
								combinedResult[name] = append(slice, newValue)
							}
						} else {
							existingString := existingValue.(string)
							if !unique || existingString != newValue {
								combinedResult[name] = []string{existingString, newValue}
							}
						}
					} else {
						combinedResult[name] = newValue
					}
				}
			}
		}

		if len(combinedResult) > 0 {
			jsonData, err := json.Marshal(combinedResult)
			if err != nil {
				log.Printf("Warning: Could not marshal combined data to JSON for line: %s. Error: %v", line, err)
				continue
			}
			if _, err := fmt.Fprintln(writer, string(jsonData)); err != nil {
				return fmt.Errorf("failed to write to output: %w", err)
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("error reading from input: %w", err)
	}

	return nil
}
EOF
}

# --- Function to create Makefile ---
create_makefile() {
    echo "--> Generating Makefile..."
    cat << 'EOF' > Makefile
# ==============================================================================
# Makefile for rex-go
# ==============================================================================

# --- Variables ---

# Target binary name
TARGET := rex-go

# Version information to be embedded in the binary.
# For dynamic versioning from git, you can use:
# VERSION ?= $(shell git describe --tags --always --dirty)
VERSION ?= 1.0.0

# Go parameters
GO := go
GO_BUILD_FLAGS := -trimpath
# Embed version info into the binary. Requires a `var version string` in the main package.
LDFLAGS := -ldflags="-s -w -X main.version=$(VERSION)"

# Output directory for all binaries
DIST_DIR := dist


# --- Main Targets ---

.PHONY: all build clean

# Default target: build for the host system
build:
	@echo "==> Building for host OS/ARCH..."
	@mkdir -p $(DIST_DIR)
	$(GO) build $(GO_BUILD_FLAGS) $(LDFLAGS) -o $(DIST_DIR)/$(TARGET) main.go

# Build for all supported platforms
all: clean build-linux-amd64 build-linux-arm64 build-windows-amd64 build-windows-arm64 build-mac-universal
	@echo "\n==> All builds completed successfully."
	@echo "==> Artifacts are in the '$(DIST_DIR)' directory:"
	@find $(DIST_DIR) -type f -exec ls -l {} + | awk '{print "  " $$0}'


# --- Cross-Compilation Targets ---

.PHONY: build-linux-amd64 build-linux-arm64 build-windows-amd64 build-windows-arm64

build-linux-amd64:
	$(eval OUT_DIR := $(DIST_DIR)/linux-amd64)
	@echo "==> Building for Linux (amd64)..."
	@mkdir -p $(OUT_DIR)
	@GOOS=linux GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) $(LDFLAGS) -o $(OUT_DIR)/$(TARGET) main.go

build-linux-arm64:
	$(eval OUT_DIR := $(DIST_DIR)/linux-arm64)
	@echo "==> Building for Linux (arm64)..."
	@mkdir -p $(OUT_DIR)
	@GOOS=linux GOARCH=arm64 $(GO) build $(GO_BUILD_FLAGS) $(LDFLAGS) -o $(OUT_DIR)/$(TARGET) main.go

build-windows-amd64:
	$(eval OUT_DIR := $(DIST_DIR)/windows-amd64)
	@echo "==> Building for Windows (amd64)..."
	@mkdir -p $(OUT_DIR)
	@GOOS=windows GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) $(LDFLAGS) -o $(OUT_DIR)/$(TARGET).exe main.go

build-windows-arm64:
	$(eval OUT_DIR := $(DIST_DIR)/windows-arm64)
	@echo "==> Building for Windows (arm64)..."
	@mkdir -p $(OUT_DIR)
	@GOOS=windows GOARCH=arm64 $(GO) build $(GO_BUILD_FLAGS) $(LDFLAGS) -o $(OUT_DIR)/$(TARGET).exe main.go


# --- macOS Specific Targets ---

.PHONY: build-mac-universal

# Build a universal binary for macOS (amd64 + arm64)
# This creates separate binaries for each architecture and merges them with `lipo`.
build-mac-universal:
	$(eval OUT_DIR := $(DIST_DIR)/darwin-universal)
	@echo "==> Building for macOS (amd64)..."
	@mkdir -p $(OUT_DIR)
	@GOOS=darwin GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) $(LDFLAGS) -o $(OUT_DIR)/$(TARGET)-amd64 main.go
	@echo "==> Building for macOS (arm64)..."
	@GOOS=darwin GOARCH=arm64 $(GO) build $(GO_BUILD_FLAGS) $(LDFLAGS) -o $(OUT_DIR)/$(TARGET)-arm64 main.go
	@echo "==> Creating macOS universal binary..."
	@lipo -create -output $(OUT_DIR)/$(TARGET) $(OUT_DIR)/$(TARGET)-amd64 $(OUT_DIR)/$(TARGET)-arm64
	@rm $(OUT_DIR)/$(TARGET)-amd64 $(OUT_DIR)/$(TARGET)-arm64
	@echo "==> Universal binary created at $(OUT_DIR)/$(TARGET)"


# --- Utility Targets ---

# Clean up build artifacts
clean:
	@echo "==> Cleaning up..."
	@rm -rf $(DIST_DIR)
EOF
}

# --- Function to create README.md (English) ---
create_readme_en() {
    echo "--> Generating README.md (English)..."
    cat << 'EOF' > README.md
# rex-go

`rex-go` is a command-line tool that extracts fields from text data using regular expressions and outputs them in JSON format. Like Splunk's `rex` command, its purpose is to easily create structured data from unstructured text such as log files.

This tool is written in Go and runs as a single, cross-platform executable.

---

## Features

- **Flexible I/O**: Supports input from standard input (pipes) or files, and writes results to standard output or files.
- **Multiple Regex Patterns**: Specify multiple regular expression patterns from the command line (`-r`) or a configuration file (`-f`).
- **Merged Results**: All specified regular expressions are applied to each line of input, and the matched results are merged into a single JSON object.
- **Multi-value Arrays**: If the same field name is captured by multiple patterns, its values are automatically collected into an array.
- **Unique Values**: The `-u` option ensures that values in a multi-valued array are unique.
- **Portable**: Generates a single executable file that runs on machines without a Go runtime environment.

---

## Installation & Build

A Go environment must be set up.

Simply run `make` to build the application. The following targets are available:

- **`make build`**: Builds a single executable for your current operating system and architecture in the `dist/` directory.
- **`make all`**: Cross-compiles for all target platforms (Linux, Windows, macOS) and places the binaries in platform-specific subdirectories within `dist/`.
- **`make clean`**: Removes the `dist/` directory and all build artifacts.

For most users, `make all` is the recommended command to generate all distributable files.

---

## Usage

### Command-Line Options

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

### Examples

#### 1. Basic Extraction

Extract information from an Apache access log.

```bash
echo '127.0.0.1 - frank [10/Oct/2000] "GET /api" 200' | \
./rex-go -r '(?P<client_ip>[^ ]+) - (?P<user>[^ ]+) \[(?P<date>[^\]]+)\] "(?P<method>\w+) (?P<uri>[^ "]+)" (?P<status>\d{3})'
```

**Output:**
```json
{"client_ip":"127.0.0.1","date":"10/Oct/2000","method":"GET","status":"200","uri":"/api","user":"frank"}
```

#### 2. Merging Results from Multiple Patterns

Extract both `level` and `status` from a single log line using different regular expressions.

```bash
echo "request failed with level=error, status=500" | \
./rex-go -r 'level=(?P<level>\w+)' -r 'status=(?P<status>\d+)'
```

**Output:**
```json
{"level":"error","status":"500"}
```

#### 3. Collecting Multiple Values into an Array

Extract values from both `user=` and `alias=` into a common field named `name`, which will be output as an array.

```bash
echo "user=admin, alias=root" | \
./rex-go -r 'user=(?P<name>\w+)' -r 'alias=(?P<name>\w+)'
```

**Output:**
```json
{"name":["admin","root"]}
```

#### 4. Making Array Values Unique (with `-u` option)

Even if duplicate values are captured, the `-u` flag ensures only unique values are stored in the array.

```bash
echo "user=admin, alias=root, user=admin" | \
./rex-go -u -r 'user=(?P<name>\w+)' -r 'alias=(?P<name>\w+)'
```

**Output:**
```json
{"name":["admin","root"]}
```

#### 5. Using a Configuration File (with `-f` option)

Create a file named `patterns.json` with the following content:

```json
{
  "patterns": [
    "level=(?P<level>\\w+)",
    "status=(?P<status>\\d+)"
  ]
}
```

Run the tool, specifying the file with the `-f` option.

```bash
echo "level=info, status=200" | ./rex-go -f patterns.json
```

**Output:**
```json
{"level":"info","status":"200"}
```
---

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
EOF
}

# --- Function to create README.ja.md (Japanese) ---
create_readme_ja() {
    echo "--> Generating README.ja.md (Japanese)..."
    cat << 'EOF' > README.ja.md
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

`make` コマンドを実行するだけでアプリケーションをビルドできます。以下のターゲットが利用可能です。

- **`make build`**: 現在のOSとアーキテクチャ向けの実行ファイルを `dist/` ディレクトリにビルドします。
- **`make all`**: 全てのターゲットプラットフォーム（Linux, Windows, macOS）向けにクロスコンパイルを行い、`dist/` 内の各プラットフォーム用サブディレクトリにバイナリを配置します。
- **`make clean`**: `dist/` ディレクトリと全てのビルド成果物を削除します。

通常は `make all` を実行すれば、配布用の全ファイルが生成されます。

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
EOF
}


# --- Main execution block ---
echo "🚀 Generating project files for rex-go..."

create_main_go
create_makefile
create_readme_en
create_readme_ja

echo ""
echo "🎉 All files have been generated successfully!"
echo "You can now build the project by running:"
echo "   make all"


