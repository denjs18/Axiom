#!/usr/bin/env bash
#
# Build script run by Netlify.
# Downloads the Godot headless binary + matching export templates, then
# exports the project to a web (HTML5/WebAssembly) build in build/web/.
#
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.6}"
GODOT_RELEASE="${GODOT_RELEASE:-stable}"
EXPORT_PRESET="Web"
OUTPUT_DIR="build/web"

BASE_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}"
GODOT_BIN_ZIP="Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip"
TEMPLATES_TPZ="Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz"

echo "=== Downloading Godot ${GODOT_VERSION}-${GODOT_RELEASE} (headless) ==="
curl -fL -o godot.zip "${BASE_URL}/${GODOT_BIN_ZIP}"
unzip -o -q godot.zip
GODOT_EXE="$(ls Godot_v*_linux.x86_64 | head -n1)"
chmod +x "${GODOT_EXE}"
echo "Using binary: ${GODOT_EXE}"

echo "=== Downloading export templates ==="
curl -fL -o templates.tpz "${BASE_URL}/${TEMPLATES_TPZ}"
unzip -o -q templates.tpz -d templates_extract
TEMPLATE_DIR="${HOME}/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}"
mkdir -p "${TEMPLATE_DIR}"
cp templates_extract/templates/* "${TEMPLATE_DIR}/"

echo "=== Importing project resources ==="
# A first headless run imports assets so the export has everything it needs.
timeout 600 "./${GODOT_EXE}" --headless --import . || true

echo "=== Exporting project to web ==="
mkdir -p "${OUTPUT_DIR}"
"./${GODOT_EXE}" --headless --export-release "${EXPORT_PRESET}" "${OUTPUT_DIR}/index.html"

echo "=== Build complete: ${OUTPUT_DIR} ==="
ls -la "${OUTPUT_DIR}"
