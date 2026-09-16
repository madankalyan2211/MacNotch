#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

if [ ! -d "build/IconDock.app" ]; then
    ./Scripts/build.sh
fi

echo "🚀 Launching IconDock..."
open build/IconDock.app
