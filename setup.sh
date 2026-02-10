#!/bin/bash

# MicroLLM App Setup Script
# Run this script to set up the project

set -e

echo "========================================"
echo "  MicroLLM App Setup"
echo "========================================"
echo ""

# Check Flutter installation
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found in PATH"
    echo ""
    echo "Please install Flutter first:"
    echo "  1. Download from: https://docs.flutter.dev/get-started/install"
    echo "  2. Extract and add to PATH"
    echo "  3. Run: flutter doctor"
    echo ""
    exit 1
fi

echo "✅ Flutter found: $(flutter --version | head -1)"
echo ""

# Check Android SDK
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
    echo "⚠️  ANDROID_HOME not set. Trying to detect..."
    if [ -d "$HOME/Library/Android/sdk" ]; then
        export ANDROID_HOME="$HOME/Library/Android/sdk"
        echo "   Found at: $ANDROID_HOME"
    elif [ -d "$HOME/Android/Sdk" ]; then
        export ANDROID_HOME="$HOME/Android/Sdk"
        echo "   Found at: $ANDROID_HOME"
    fi
fi

# Update local.properties with actual paths
FLUTTER_PATH=$(which flutter | xargs dirname | xargs dirname)
SDK_PATH="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

echo "Updating local.properties..."
cat > android/local.properties << EOF
sdk.dir=$SDK_PATH
flutter.sdk=$FLUTTER_PATH
EOF
echo "✅ local.properties updated"
echo ""

# Create external directory for llama.cpp
echo "Setting up llama.cpp..."
mkdir -p external

if [ ! -d "external/llama.cpp" ]; then
    echo "   Cloning llama.cpp..."
    git clone --depth 1 https://github.com/ggerganov/llama.cpp.git external/llama.cpp
    echo "✅ llama.cpp cloned"
else
    echo "✅ llama.cpp already exists"
fi
echo ""

# Create assets directories
echo "Creating asset directories..."
mkdir -p assets/fonts
mkdir -p assets/prompts
echo "✅ Asset directories created"
echo ""

# Get Flutter dependencies
echo "Getting Flutter dependencies..."
flutter pub get
echo "✅ Dependencies installed"
echo ""

# Run Flutter doctor
echo "Running Flutter doctor..."
flutter doctor
echo ""

echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo ""
echo "  1. Connect an Android device or start an emulator"
echo "     $ adb devices"
echo ""
echo "  2. Run the app in debug mode:"
echo "     $ flutter run"
echo ""
echo "  3. Or build a release APK:"
echo "     $ flutter build apk --release"
echo ""
echo "Note: The app will download the LLM model (~1.6GB)"
echo "      on first launch. Make sure you have WiFi."
echo ""
