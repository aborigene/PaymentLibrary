#!/bin/bash

# Clean previous build artifacts to avoid nested dSYM issues
echo "🧹 Cleaning previous build artifacts..."
rm -rf output/

xcodebuild archive \
  -scheme PaymentLibrary -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath output/PaymentLibrary-iOS \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  STRIP_INSTALLED_PRODUCT=YES \
  DEPLOYMENT_POSTPROCESSING=YES \
  STRIP_STYLE=non-global \
  COPY_PHASE_STRIP=NO \
  STRIP_SWIFT_SYMBOLS=YES

xcodebuild archive \
  -scheme PaymentLibrary -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -archivePath output/PaymentLibrary-iOSSim \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  STRIP_INSTALLED_PRODUCT=YES \
  DEPLOYMENT_POSTPROCESSING=YES \
  STRIP_STYLE=non-global \
  COPY_PHASE_STRIP=NO \
  STRIP_SWIFT_SYMBOLS=YES

rm -rf output/PaymentLibrary.xcframework

xcodebuild -create-xcframework \
  -framework output/PaymentLibrary-iOS.xcarchive/Products/Library/Frameworks/PaymentLibrary.framework \
  -framework output/PaymentLibrary-iOSSim.xcarchive/Products/Library/Frameworks/PaymentLibrary.framework \
  -output output/PaymentLibrary.xcframework

echo "📦 Extracting dSYM files for Dynatrace upload..."
mkdir -p output/dSYMs

# Copy dSYM from iOS (device) archive
if [ -d "output/PaymentLibrary-iOS.xcarchive/dSYMs/PaymentLibrary.framework.dSYM" ]; then
  cp -R output/PaymentLibrary-iOS.xcarchive/dSYMs/PaymentLibrary.framework.dSYM output/dSYMs/PaymentLibrary-device.framework.dSYM
  echo "✅ iOS device dSYM extracted to: output/dSYMs/PaymentLibrary-device.framework.dSYM"
  
  # Create a zip for device dSYM
  cd output/dSYMs
  zip -r PaymentLibrary-device-dSYM.zip PaymentLibrary-device.framework.dSYM
  cd ../..
  echo "✅ Device dSYM zip created: output/dSYMs/PaymentLibrary-device-dSYM.zip"
else
  echo "⚠️  Warning: iOS device dSYM file not found in archive"
fi

# Copy dSYM from iOS Simulator archive
if [ -d "output/PaymentLibrary-iOSSim.xcarchive/dSYMs/PaymentLibrary.framework.dSYM" ]; then
  cp -R output/PaymentLibrary-iOSSim.xcarchive/dSYMs/PaymentLibrary.framework.dSYM output/dSYMs/PaymentLibrary-simulator.framework.dSYM
  echo "✅ iOS simulator dSYM extracted to: output/dSYMs/PaymentLibrary-simulator.framework.dSYM"
  
  # Create a zip for simulator dSYM
  cd output/dSYMs
  zip -r PaymentLibrary-simulator-dSYM.zip PaymentLibrary-simulator.framework.dSYM
  cd ../..
  echo "✅ Simulator dSYM zip created: output/dSYMs/PaymentLibrary-simulator-dSYM.zip"
else
  echo "⚠️  Warning: iOS simulator dSYM file not found in archive"
fi

echo ""
echo "🎉 Build complete!"
echo "📱 Framework: output/PaymentLibrary.xcframework"
echo "🔍 dSYM files: output/dSYMs/"
echo ""
echo "To upload to Dynatrace:"
echo "  Device dSYM:    output/dSYMs/PaymentLibrary-device-dSYM.zip"
echo "  Simulator dSYM: output/dSYMs/PaymentLibrary-simulator-dSYM.zip"
