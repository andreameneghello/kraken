.PHONY: build run build-release bundle dist update install clean

APP_NAME = Kraken
APP_BUNDLE = $(APP_NAME).app
APP_VERSION = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || echo 1.0.0)
INSTALL_DIR = $(HOME)/Applications

# Default: build debug binary
build:
	swift build

# Build and run debug version
run: build
	.build/debug/$(APP_NAME)

# Build release binary (internal)
build-release:
	@echo "Building release binary..."
	swift build -c release

# Build release .app bundle
bundle: build-release
	@echo "Creating $(APP_BUNDLE)..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp .build/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp scripts/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp icons/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@echo "Built $(APP_BUNDLE)"

# Create distributable zip for Homebrew / GitHub releases
dist: clean bundle
	@echo "Creating $(APP_NAME)-$(APP_VERSION).zip..."
	@rm -f $(APP_NAME)-*.zip
	@ditto -c -k --keepParent $(APP_BUNDLE) $(APP_NAME)-$(APP_VERSION).zip
	@echo ""
	@echo "SHA-256:"
	@shasum -a 256 $(APP_NAME)-$(APP_VERSION).zip

# Install to ~/Applications and launch
update: bundle
	@echo "Quitting old instance..."
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 1
	@echo "Installing to $(INSTALL_DIR)..."
	@rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@echo "Launching..."
	@open $(INSTALL_DIR)/$(APP_BUNDLE)

# Just install without launching
install: bundle
	@echo "Installing to $(INSTALL_DIR)..."
	@rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@echo "Installed $(INSTALL_DIR)/$(APP_BUNDLE)"

# Clean build artifacts
clean:
	swift package clean
	@rm -rf $(APP_BUNDLE)
	@rm -f $(APP_NAME)-*.zip
