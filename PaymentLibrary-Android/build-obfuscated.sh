#!/bin/bash

# Default destination if AAR_DESTINATION is not set
DEFAULT_DESTINATION="../../BankingApp/BankingApp-Android/app/libs/PaymentLibrary-release.aar"
AAR_DESTINATION="${AAR_DESTINATION:-$DEFAULT_DESTINATION}"

echo "🔨 Building obfuscated PaymentLibrary for Android..."
echo ""

# Clean previous builds
./gradlew clean

# Build release AAR with ProGuard/R8 obfuscation
./gradlew :PaymentLibrary:assembleRelease

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Build complete!"
    
    AAR_SOURCE="PaymentLibrary/build/outputs/aar/paymentlibrary-release.aar"
    MAPPING_FILE="PaymentLibrary/build/outputs/mapping/release/mapping.txt"
    
    if [ -f "$AAR_SOURCE" ]; then
        # Create organized output directory
        mkdir -p output/android-symbols
        
        # Copy mapping file if it exists
        if [ -f "$MAPPING_FILE" ]; then
            cp "$MAPPING_FILE" output/android-symbols/
            echo ""
            echo "🗺️  ProGuard Mapping file (for Dynatrace):"
            echo "   output/android-symbols/mapping.txt"
        else
            echo ""
            echo "⚠️  Mapping file not found - obfuscation may not be enabled"
        fi
        
        # Copy AAR to output directory
        cp "$AAR_SOURCE" output/PaymentLibrary-release.aar
        
        # Copy AAR to BankingApp
        echo ""
        echo "📱 Copying obfuscated AAR to: $AAR_DESTINATION"
        mkdir -p "$(dirname "$AAR_DESTINATION")"
        cp "$AAR_SOURCE" "$AAR_DESTINATION"
        
        if [ $? -eq 0 ]; then
            echo "✅ AAR file successfully copied to: $AAR_DESTINATION"
        else
            echo "✗ Failed to copy AAR file to destination"
            exit 1
        fi
        
        echo ""
        echo "✅ Files created:"
        echo "   - output/PaymentLibrary-release.aar (obfuscated library)"
        echo "   - output/android-symbols/mapping.txt (for Dynatrace)"
        echo "   - $AAR_DESTINATION (copied to BankingApp)"
        echo ""
        echo "📤 Upload to Dynatrace:"
        echo "   File: output/android-symbols/mapping.txt"
    else
        echo ""
        echo "✗ AAR file not found at: $AAR_SOURCE"
        exit 1
    fi
else
    echo ""
    echo "❌ Build failed!"
    exit 1
fi
