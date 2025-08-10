#!/bin/bash

# CopyMac Fast Deploy Script
# Usage: ./deploy.sh 1.5.6

set -e  # Exit on any error

# Check if version is provided
if [ $# -eq 0 ]; then
    echo "❌ Error: Please provide a version number"
    echo "Usage: ./deploy.sh 1.5.6"
    exit 1
fi

VERSION=$1
echo "🚀 Starting deployment for CopyMac v$VERSION"

# Step 1: Commit current changes
echo "📝 Committing current changes..."
git add .
git commit -m "Release version $VERSION - Enhanced features and improvements" || echo "No changes to commit"

# Step 2: Create and push tag
echo "🏷️  Creating version tag..."
git tag v$VERSION
git push origin main
git push origin v$VERSION

# Step 3: Build the app
echo "🔨 Building CopyMac..."
swift build -c release

# Step 4: Create app bundle
echo "📦 Creating app bundle..."
rm -rf CopyMac.app
mkdir -p CopyMac.app/Contents/MacOS
mkdir -p CopyMac.app/Contents/Resources

# Copy executable
cp .build/release/copymac-clipboard CopyMac.app/Contents/MacOS/CopyMac
chmod +x CopyMac.app/Contents/MacOS/CopyMac

# Create Info.plist
cat > CopyMac.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CopyMac</string>
    <key>CFBundleIdentifier</key>
    <string>com.copyMac.clipboard</string>
    <key>CFBundleName</key>
    <string>CopyMac</string>
    <key>CFBundleDisplayName</key>
    <string>CopyMac</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Step 5: Create ZIP and get hash
echo "🗜️  Creating release ZIP..."
zip -r copymac-$VERSION.zip CopyMac.app
SHA256=$(shasum -a 256 copymac-$VERSION.zip | cut -d' ' -f1)
echo "📋 SHA256: $SHA256"

# Move to build directory
mkdir -p build
mv copymac-$VERSION.zip build/

# Step 6: Update Homebrew Cask
echo "🍺 Updating Homebrew Cask..."
cat > Casks/copymac.rb << EOF
cask "copymac" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
EOF

# Step 7: Commit and push cask
echo "📤 Pushing updated cask..."
git add Casks/copymac.rb
git commit -m "Update Homebrew cask to version $VERSION"
git push origin main

# Step 8: Instructions for GitHub release
echo ""
echo "✅ Deployment preparation complete!"
echo ""
echo "📋 Next steps (manual):"
echo "1. Go to: https://github.com/alciu10/homebrew-copymac/releases"
echo "2. Click 'Create a new release'"
echo "3. Select tag: v$VERSION"
echo "4. Title: CopyMac v$VERSION"
echo "5. Upload file: $(pwd)/build/copymac-$VERSION.zip"
echo "6. Publish release"
echo ""
echo "🧪 Test installation with:"
echo "   brew reinstall --cask alciu10/copymac/copymac"
echo ""
echo "🎉 Version $VERSION is ready for deployment!"