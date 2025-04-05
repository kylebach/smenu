APP_NAME = smenu
BUILD_DIR = build
RESOURCES_DIR = $(BUILD_DIR)/$(APP_NAME).app/Contents/Resources
MACOS_DIR = $(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS

CC = clang
CFLAGS = -Wall -framework Cocoa
SRC = smenu.m

all: app

app: prepare
	$(CC) $(CFLAGS) $(SRC) -o $(MACOS_DIR)/$(APP_NAME)
	chmod +x $(MACOS_DIR)/$(APP_NAME)
	which codesign > /dev/null && codesign --force --entitlements app.entitlements --sign - $(BUILD_DIR)/$(APP_NAME).app || echo "Codesign not available, skipping app signing"

prepare:
	mkdir -p $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/$(APP_NAME).app/Contents
	mkdir -p $(MACOS_DIR)
	mkdir -p $(RESOURCES_DIR)
	cp Info.plist $(BUILD_DIR)/$(APP_NAME).app/Contents/

install: app
	cp -R $(BUILD_DIR)/$(APP_NAME).app /Applications/

startup: install
	mkdir -p ~/Library/LaunchAgents
	cp ski.bachin.smenu.plist ~/Library/LaunchAgents/

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all app prepare install startup clean
