#!/bin/bash

xcodebuild archive \
  -scheme PaymentLibrary -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath output/PaymentLibrary-iOS \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild archive \
  -scheme PaymentLibrary -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -archivePath output/PaymentLibrary-iOSSim \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

rm -rf output/PaymentLibrary.xcframework

xcodebuild -create-xcframework \
  -framework output/PaymentLibrary-iOS.xcarchive/Products/Library/Frameworks/PaymentLibrary.framework \
  -framework output/PaymentLibrary-iOSSim.xcarchive/Products/Library/Frameworks/PaymentLibrary.framework \
  -output output/PaymentLibrary.xcframework
