# iOS dSYM Symbolication Helper Scripts

This folder contains scripts to generate symbol index files from iOS dSYM files for crash deobfuscation and symbolication in Dynatrace.

## Scripts Overview

### 1. `deofuscation/gen_ios_symbol_index_dwarf.sh`
Main shell script that orchestrates the symbol extraction process from dSYM files.

**Purpose:** Extracts debug symbols from iOS dSYM files and generates a JSON index mapping memory addresses to function names.

**Requirements:**
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3
- `dwarfdump` (included with Xcode CLT)
- `swift-demangle` (included with Xcode CLT, optional for Swift symbol demangling)

**Usage:**
```bash
./gen_ios_symbol_index_dwarf.sh <dSYM_DIR> <IMAGE_NAME> <ARCH> <OUT_JSON> [mapping.json] [--no-swift-demangle] [--swift-demangle-bin BIN]
```

**Parameters:**
- `<dSYM_DIR>`: Path to the dSYM bundle (e.g., `PaymentLibrary.framework.dSYM`)
- `<IMAGE_NAME>`: Framework/binary name (e.g., `PaymentLibrary`)
- `<ARCH>`: Target architecture (e.g., `arm64`, `x86_64`, `arm64e`)
- `<OUT_JSON>`: Output JSON file path
- `[mapping.json]`: Optional obfuscation mapping file
- `[--no-swift-demangle]`: Disable Swift symbol demangling
- `[--swift-demangle-bin BIN]`: Custom path to swift-demangle tool

**Example:**
```bash
cd helperScripts/deofuscation
./gen_ios_symbol_index_dwarf.sh \
  ../../output/dSYMs/PaymentLibrary-device.framework.dSYM \
  PaymentLibrary \
  arm64 \
  out/ios_symbol_index.json
```

### 2. `deofuscation/dsym_to_index_ranges.py`
Python script that parses DWARF debug information and generates the symbol index JSON.

**Purpose:** Processes DWARF debug info and debug ranges to create a comprehensive function address-to-name mapping.

**Features:**
- Parses DWARF `.debug_info` and `.debug_ranges` sections
- Resolves abstract origins and specifications for inlined functions
- Optional Swift symbol demangling via `xcrun swift-demangle`
- Optional obfuscation mapping support
- LRU caching for performance (up to 100,000 symbols)

**Direct Usage (advanced):**
```bash
python3 dsym_to_index_ranges.py \
  --di debug_info.txt \
  --dr debug_ranges.txt \
  --uuid <UUID> \
  --image <IMAGE_NAME> \
  --arch <ARCH> \
  [--mapping mapping.json] \
  [--swift-demangle] \
  [--no-swift-demangle] \
  [--swift-demangle-bin xcrun] \
  [--verbose]
```

**Output Format:**
```json
{
  "image": "PaymentLibrary",
  "uuid": "12345678-1234-1234-1234-123456789ABC",
  "arch": "arm64",
  "functions": [
    {"start": 4096, "end": 4224, "name": "PaymentClient.initialize()"},
    {"start": 4224, "end": 4352, "name": "BusinessEventsClient.sendEvent(_:)"}
  ]
}
```

## Integration into Build Pipeline

### Manual Build Script Integration

Add to your `build.sh` after creating the xcframework:

```bash
echo "📊 Generating symbol index for crash symbolication..."

# For device build
if [ -d "output/dSYMs/PaymentLibrary-device.framework.dSYM" ]; then
  helperScripts/deofuscation/gen_ios_symbol_index_dwarf.sh \
    output/dSYMs/PaymentLibrary-device.framework.dSYM \
    PaymentLibrary \
    arm64 \
    output/ios_symbol_index_device.json
  
  echo "✅ Device symbol index: output/ios_symbol_index_device.json"
fi

# For simulator build
if [ -d "output/dSYMs/PaymentLibrary-simulator.framework.dSYM" ]; then
  helperScripts/deofuscation/gen_ios_symbol_index_dwarf.sh \
    output/dSYMs/PaymentLibrary-simulator.framework.dSYM \
    PaymentLibrary \
    arm64 \
    output/ios_symbol_index_simulator.json
  
  echo "✅ Simulator symbol index: output/ios_symbol_index_simulator.json"
fi
```

### CI/CD Pipeline Integration

#### GitHub Actions Example:
```yaml
- name: Build iOS Framework
  run: ./build.sh

- name: Generate Symbol Index
  run: |
    cd helperScripts/deofuscation
    ./gen_ios_symbol_index_dwarf.sh \
      ../../output/dSYMs/PaymentLibrary-device.framework.dSYM \
      PaymentLibrary \
      arm64 \
      ../../output/ios_symbol_index.json

- name: Upload Symbol Index to Dynatrace
  run: |
    curl -X POST \
      "https://${DT_ENVIRONMENT}.live.dynatrace.com/api/v2/symbols" \
      -H "Authorization: Api-Token ${DT_API_TOKEN}" \
      -F "file=@output/ios_symbol_index.json"
```

#### GitLab CI Example:
```yaml
build-ios:
  script:
    - ./build.sh
    - cd helperScripts/deofuscation
    - ./gen_ios_symbol_index_dwarf.sh 
        ../../output/dSYMs/PaymentLibrary-device.framework.dSYM 
        PaymentLibrary 
        arm64 
        ../../output/ios_symbol_index.json
  artifacts:
    paths:
      - output/ios_symbol_index.json
      - output/dSYMs/*.zip
```

#### Jenkins Pipeline Example:
```groovy
stage('Generate Symbol Index') {
    steps {
        sh '''
            cd helperScripts/deofuscation
            ./gen_ios_symbol_index_dwarf.sh \
                ../../output/dSYMs/PaymentLibrary-device.framework.dSYM \
                PaymentLibrary \
                arm64 \
                ../../output/ios_symbol_index.json
        '''
    }
}
```

### Xcode Build Phase Integration

Add a "Run Script" build phase to your Xcode project:

```bash
# Only for archive builds
if [ "${CONFIGURATION}" = "Release" ]; then
  SCRIPT_DIR="${PROJECT_DIR}/helperScripts/deofuscation"
  
  "${SCRIPT_DIR}/gen_ios_symbol_index_dwarf.sh" \
    "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}" \
    "${PRODUCT_NAME}" \
    "${CURRENT_ARCH}" \
    "${BUILD_DIR}/ios_symbol_index.json"
fi
```

## Troubleshooting

### UUID Not Found Error
```bash
❌ Não encontrei UUID para ARCH='arm64'
```
**Solution:** Check available architectures in your dSYM:
```bash
dwarfdump --uuid PaymentLibrary.framework.dSYM
```

### Swift Demangle Warning
```
⚠️  xcrun não encontrado; desativando swift-demangle.
```
**Solution:** Install Xcode Command Line Tools:
```bash
xcode-select --install
```

### Multiple UUIDs / Nested dSYM
If you see different UUIDs, ensure your dSYM isn't nested:
```bash
find PaymentLibrary.framework.dSYM -name "*.dSYM"
```
Should return nothing. If it finds nested dSYMs, clean your build output and rebuild.

## Output Usage

The generated JSON file can be:
1. **Uploaded to Dynatrace** for crash symbolication
2. **Stored in artifact repository** alongside dSYM files
3. **Used with offline symbolication tools**
4. **Integrated with crash reporting services**

## Notes

- Symbol index generation adds ~5-30 seconds to build time depending on binary size
- The generated JSON file is typically 100KB-5MB depending on symbol count
- For obfuscated builds, provide a `mapping.json` file to reverse obfuscation
- Swift demangling is enabled by default and recommended for Swift frameworks
- Both device (arm64) and simulator (arm64/x86_64) architectures can be processed separately
