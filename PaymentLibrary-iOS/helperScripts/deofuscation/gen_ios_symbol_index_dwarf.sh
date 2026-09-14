#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./gen_ios_symbol_index_dwarf.sh <dSYM_DIR> <IMAGE_NAME> <ARCH> <OUT_JSON> [mapping.json] [--no-swift-demangle] [--swift-demangle-bin BIN]
#
# Exemplo:
#   ./gen_ios_symbol_index_dwarf.sh \
#     2_step/ios-arm64/dSYMs/obfuscated_TapOnPhoneWrapper.framework.dSYM \
#     TapOnPhoneWrapper arm64 out/ios_symbol_index.json mapping.json
#
# Requisitos:
#   - Xcode CLT instalado para xcrun/dwarfdump e swift-demangle. (xcode-select --install)
#   - dsym_to_index_ranges.py atualizado (com suporte a --swift-demangle/--swift-demangle-bin).

DSYM="${1:?dSYM dir required}"
IMAGE="${2:?image name required}"
ARCH="${3:?arch required}"
OUT="${4:?output json required}"
MAPPING="${5-}"

# Flags opcionais
DO_SWIFT_DEMANGLE="1"
SWIFT_BIN_PREFIX="xcrun"   # chamaremos: xcrun swift-demangle --compact <sym>

shift 4 || true
# se o 5º argumento não é uma flag, é o mapping
if [[ "${1-}" != "" && "${1-}" != --* ]]; then
  shift 1 || true
fi

while [[ "${1-}" == --* ]]; do
  case "$1" in
    --no-swift-demangle)
      DO_SWIFT_DEMANGLE="0"; shift ;;
    --swift-demangle-bin)
      SWIFT_BIN_PREFIX="${2:?missing bin after --swift-demangle-bin}"; shift 2 ;;
    *)
      echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Helpers
fail() { echo "❌ $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -d "$DSYM" ] || fail "dSYM not found: $DSYM"

# Preferir xcrun dwarfdump (Xcode) se existir
DWARFDUMP="dwarfdump"
if have xcrun && xcrun -f dwarfdump >/dev/null 2>&1; then
  DWARFDUMP="xcrun dwarfdump"
fi

# Conferir swift-demangle somente se ativado
if [[ "$DO_SWIFT_DEMANGLE" == "1" ]]; then
  if ! have "$SWIFT_BIN_PREFIX"; then
    echo "⚠️  $SWIFT_BIN_PREFIX não encontrado; desativando swift-demangle." >&2
    DO_SWIFT_DEMANGLE="0"
  else
    # teste leve
    if ! "$SWIFT_BIN_PREFIX" swift-demangle -help >/dev/null 2>&1; then
      echo "⚠️  $SWIFT_BIN_PREFIX swift-demangle indisponível; desativando swift-demangle." >&2
      DO_SWIFT_DEMANGLE="0"
    fi
  fi
fi

# UUID
# Normaliza ARCH para facilitar matching (ex.: ARM64 -> arm64)
ARCH_NORM="$(echo "$ARCH" | tr '[:upper:]' '[:lower:]')"

# Colete todas as linhas de UUID e filtre pela arch entre parênteses
UUID_LINE="$($DWARFDUMP --uuid "$DSYM" | awk -v want="($ARCH_NORM)" 'index(tolower($0), want) { print; exit }' || true)"

# Se não achou, tenta variações comuns (arm64e cai em arm64, x86_64 idem)
if [[ -z "$UUID_LINE" && "$ARCH_NORM" == "arm64e" ]]; then
  UUID_LINE="$($DWARFDUMP --uuid "$DSYM" | awk 'tolower($0) ~ /\(arm64\)/ { print; exit }' || true)"
fi

if [[ -z "$UUID_LINE" ]]; then
  echo "❌ Não encontrei UUID para ARCH='$ARCH'. Saída do dwarfdump:"
  $DWARFDUMP --uuid "$DSYM" || true
  fail "UUID para a arquitetura solicitada não encontrado"
fi

UUID="$(echo "$UUID_LINE" | awk '{print $2}')"
echo "ℹ️  UUID selecionado: $UUID para ARCH=$ARCH (linha: $UUID_LINE)"

# Arquivos temporários
DI="$(mktemp)"; DR="$(mktemp)"
cleanup() { rm -f "$DI" "$DR"; }
trap cleanup EXIT

# Dumps DWARF
$DWARFDUMP --debug-info "$DSYM" > "$DI"

# Nem todo dwarfdump tem --debug-ranges (varia por versão) → fallback em --all
if $DWARFDUMP --help 2>&1 | grep -qi -- "--debug-ranges"; then
  $DWARFDUMP --debug-ranges "$DSYM" > "$DR"
else
  $DWARFDUMP --all "$DSYM" > "$DR"
fi

# mapping opcional
declare -a MAP_ARG=()
if [[ -n "${MAPPING}" && -f "${MAPPING}" ]]; then
  MAP_ARG=(--mapping "${MAPPING}")
fi

# Flags python (demangle Swift)
declare -a SWIFT_ARGS=()
if [[ "$DO_SWIFT_DEMANGLE" == "1" ]]; then
  SWIFT_ARGS+=(--swift-demangle --swift-demangle-bin "$SWIFT_BIN_PREFIX")
else
  SWIFT_ARGS+=(--no-swift-demangle)
fi

# Local do script Python
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Gera índice (com demangle Swift se habilitado)
python3 "$SCRIPT_DIR/dsym_to_index_ranges.py" \
  --di "$DI" \
  --dr "$DR" \
  --uuid "$UUID" \
  --image "$IMAGE" \
  --arch "$ARCH" \
  "${SWIFT_ARGS[@]}" \
  > "$OUT"

echo "✅ Index written: $OUT"
