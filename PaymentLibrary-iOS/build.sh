#!/bin/bash

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

# Copy dSYM from iOS archive
if [ -d "output/PaymentLibrary-iOS.xcarchive/dSYMs/PaymentLibrary.framework.dSYM" ]; then
  cp -R output/PaymentLibrary-iOS.xcarchive/dSYMs/PaymentLibrary.framework.dSYM output/dSYMs/
  echo "✅ iOS dSYM extracted to: output/dSYMs/PaymentLibrary.framework.dSYM"
  
  # Create a zip for easy Dynatrace upload
  cd output/dSYMs
  zip -r PaymentLibrary-dSYM.zip PaymentLibrary.framework.dSYM
  cd ../..
  echo "✅ dSYM zip created: output/dSYMs/PaymentLibrary-dSYM.zip"
else
  echo "⚠️  Warning: dSYM file not found in archive"
fi

echo ""
echo "🎉 Build complete!"
echo "📱 Framework: output/PaymentLibrary.xcframework"
echo "🔍 dSYM files: output/dSYMs/"
echo ""
echo "To upload to Dynatrace:"
echo "  Use file: output/dSYMs/PaymentLibrary-dSYM.zip"
