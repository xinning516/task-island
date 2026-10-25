#!/bin/zsh
set -eu
cd "$(dirname "$0")"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required. On Mac, installing Xcode Command Line Tools provides it."
  echo "Run: xcode-select --install"
  read -k 1 "?Press any key to exit..."
  exit 1
fi
python3 integrations/install.py
echo ''
read -k 1 "?Press any key to close..."
