#!/usr/bin/env bash
# Builds dist/Jumbla.zip containing a "Jumbla" folder ready to drop into
# World of Warcraft/_<flavor>_/Interface/AddOns/.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf dist && mkdir -p dist/Jumbla
cp -r Jumbla.toc Core.lua Data Engine UI README.md dist/Jumbla/
(cd dist && python3 -c "import shutil; shutil.make_archive('Jumbla', 'zip', '.', 'Jumbla')")
rm -rf dist/Jumbla
echo "Built dist/Jumbla.zip"
