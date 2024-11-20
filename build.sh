# create-dmg.sh
#!/bin/bash

# Set project paths and variables
PROJECT_ROOT=$(pwd)
APP_NAME="Paste"
BUILD_DIR="${PROJECT_ROOT}/build"
RELEASE_DIR="${PROJECT_ROOT}/release"
DMG_NAME="PasteAI"

# 1. Build the project
echo "Building project..."
xcodebuild -project "${PROJECT_ROOT}/${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# 2. Create release directory
echo "Preparing release directory..."
mkdir -p "${RELEASE_DIR}"

# 3. Copy the built application
echo "Copying application..."
cp -R "${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app" "${RELEASE_DIR}/"

# 4. Install create-dmg if not installed
if ! command -v create-dmg &> /dev/null; then
    echo "Installing create-dmg..."
    brew install create-dmg
fi

# 5. Create DMG
echo "Creating DMG..."
create-dmg \
    --volname "PasteAI" \
    --volicon "Paste/Assets.xcassets/AppIcon.appiconset/MyIcon.icns" \
    --window-pos 200 120 \
    --window-size 800 500 \
    --icon-size 100 \
    --icon "PasteAI.app" 200 190 \
    --hide-extension "PasteAI.app" \
    --app-drop-link 600 185 \
    "release/PasteAI.dmg" \
    "release/"

# 6. Clean up build files
echo "Cleaning up build files..."
rm -rf "${BUILD_DIR}"

echo "Done! DMG file is located at: ${RELEASE_DIR}/${DMG_NAME}.dmg"
