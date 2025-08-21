# ==============================================================================
# Makefile for rex-go
# ==============================================================================

# --- Variables ---

# Target binary name
TARGET := rex-go

# Version information to be embedded in the binary.
# For dynamic versioning from git, you can use:
VERSION ?= $(shell git describe --tags --always --dirty)

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

# --- Packaging Targets ---

.PHONY: package package-linux-amd64 package-linux-arm64 package-windows-amd64 package-windows-arm64 package-mac-universal

package: all package-linux-amd64 package-linux-arm64 package-windows-amd64 package-windows-arm64 package-mac-universal
	@echo "\n==> All packages created successfully."
	@echo "==> Packages are in the '$(DIST_DIR)/archives' directory:"
	@find $(DIST_DIR)/archives -type f -exec ls -lh {} + | awk '{print "  " $0}'

package-linux-amd64: build-linux-amd64
	@echo "  Compressing linux-amd64 to tar.gz..."
	@mkdir -p $(DIST_DIR)/archives
	@cd $(DIST_DIR)/linux-amd64 && tar -czf ../archives/$(TARGET)-linux-amd64-$(VERSION).tar.gz . > /dev/null

package-linux-arm64: build-linux-arm64
	@echo "  Compressing linux-arm64 to tar.gz..."
	@mkdir -p $(DIST_DIR)/archives
	@cd $(DIST_DIR)/linux-arm64 && tar -czf ../archives/$(TARGET)-linux-arm64-$(VERSION).tar.gz . > /dev/null

package-windows-amd64: build-windows-amd64
	@echo "  Compressing windows-amd64 to zip..."
	@mkdir -p $(DIST_DIR)/archives
	@cd $(DIST_DIR)/windows-amd64 && zip -r ../archives/$(TARGET)-windows-amd64-$(VERSION).zip . > /dev/null

package-windows-arm64: build-windows-arm64
	@echo "  Compressing windows-arm64 to zip..."
	@mkdir -p $(DIST_DIR)/archives
	@cd $(DIST_DIR)/windows-arm64 && zip -r ../archives/$(TARGET)-windows-arm64-$(VERSION).zip . > /dev/null

package-mac-universal: build-mac-universal
	@echo "  Compressing darwin-universal to tar.gz..."
	@mkdir -p $(DIST_DIR)/archives
	@cd $(DIST_DIR)/darwin-universal && tar -czf ../archives/$(TARGET)-darwin-universal-$(VERSION).tar.gz . > /dev/null