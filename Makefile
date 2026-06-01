.PHONY: build run release update install clean

APP_NAME = Kraken
APP_BUNDLE = $(APP_NAME).app
INSTALL_DIR = $(HOME)/Applications

# Default: build debug binary
build:
	swift build

# Build and run debug version
run: build
	.build/debug/$(APP_NAME)

# Build release binary
release:
	@echo "Building release binary..."
	swift build -c release

# Build release .app bundle
bundle: release
	@echo "Creating $(APP_BUNDLE)..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp .build/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp scripts/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@echo "Built $(APP_BUNDLE)"

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
