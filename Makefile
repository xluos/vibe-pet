# VibePet

.PHONY: build bundle clean run dist dmg sign

PRODUCT_NAME = VibePet
BUILD_DIR = .build/release
BUNDLE_DIR = $(PRODUCT_NAME).app
CONTENTS = $(BUNDLE_DIR)/Contents
VERSION = 2.0.2

build:
	swift build -c release

bundle: build
	mkdir -p $(CONTENTS)/MacOS
	mkdir -p $(CONTENTS)/Helpers
	mkdir -p $(CONTENTS)/Resources/Sounds
	cp $(BUILD_DIR)/VibePet $(CONTENTS)/MacOS/VibePet
	cp $(BUILD_DIR)/VibePetBridge $(CONTENTS)/Helpers/vibe-pet-bridge
	cp Info.plist $(CONTENTS)/Info.plist
	cp VibePet.icns $(CONTENTS)/Resources/VibePet.icns
	-cp Sources/VibePet/Resources/Sounds/*.wav $(CONTENTS)/Resources/Sounds/ 2>/dev/null || true
	# Copy SPM-processed .lproj bundles into Contents/Resources so Bundle.main
	# finds them. The SPM-generated VibePet_VibePet.bundle expects to live at
	# the .app root, which codesign rejects as unsealed content.
	rm -rf $(CONTENTS)/Resources/*.lproj
	-cp -R $(BUILD_DIR)/VibePet_VibePet.bundle/*.lproj $(CONTENTS)/Resources/ 2>/dev/null || true
	@echo "Built $(BUNDLE_DIR)"

# Ad-hoc sign (required for distribution without Developer ID)
sign: bundle
	codesign --force --deep --sign - $(BUNDLE_DIR)
	@echo "Signed $(BUNDLE_DIR) (ad-hoc)"

# Create DMG for distribution (requires: brew install create-dmg)
dmg: sign
	rm -f $(PRODUCT_NAME)-$(VERSION).dmg
	/opt/homebrew/bin/create-dmg \
		--volname "$(PRODUCT_NAME)" \
		--background "dmg_background.png" \
		--window-pos 200 120 \
		--window-size 660 400 \
		--icon-size 80 \
		--icon "$(PRODUCT_NAME).app" 160 190 \
		--app-drop-link 500 190 \
		--no-internet-enable \
		$(PRODUCT_NAME)-$(VERSION).dmg \
		$(BUNDLE_DIR)
	@echo "Created $(PRODUCT_NAME)-$(VERSION).dmg"

# Create ZIP for distribution
dist: sign
	rm -f $(PRODUCT_NAME)-$(VERSION).zip
	ditto -c -k --keepParent $(BUNDLE_DIR) $(PRODUCT_NAME)-$(VERSION).zip
	@echo "Created $(PRODUCT_NAME)-$(VERSION).zip"

clean:
	swift package clean
	rm -rf $(BUNDLE_DIR) dist_tmp *.dmg *.zip

run: bundle
	open $(BUNDLE_DIR)

install-launcher:
	bash Scripts/install-launcher.sh
