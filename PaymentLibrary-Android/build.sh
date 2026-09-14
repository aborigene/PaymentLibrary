#!/bin/bash

# Default destination if AAR_DESTINATION is not set
DEFAULT_DESTINATION="../../BankingApp/BankingApp-Android/app/libs/PaymentLibrary-release.aar"
AAR_DESTINATION="${AAR_DESTINATION:-$DEFAULT_DESTINATION}"

./gradlew :PaymentLibrary:test :PaymentLibrary:assembleRelease
if [ $? -ne 0 ]; then
    echo "Build or tests failed"
    exit 1
else
    echo "Build and tests succeeded! Files created to PaymentLibrary-Android/build/outputs/aar/"
    
    AAR_SOURCE="PaymentLibrary/build/outputs/aar/paymentlibrary-release.aar"
    
    if [ -f "$AAR_SOURCE" ]; then
        echo "Copying AAR to: $AAR_DESTINATION"
        
        # Create destination directory if it doesn't exist
        mkdir -p "$(dirname "$AAR_DESTINATION")"
        
        # Copy the AAR file
        cp "$AAR_SOURCE" "$AAR_DESTINATION"
        
        if [ $? -eq 0 ]; then
            echo "✓ AAR file successfully copied to: $AAR_DESTINATION"
        else
            echo "✗ Failed to copy AAR file to destination"
            exit 1
        fi
    else
        echo "✗ AAR file not found at: $AAR_SOURCE"
        exit 1
    fi
fi