#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/FormatTests .build/Frameworks
ln -sfn ../Dependencies/VLCKit.framework .build/Frameworks/VLCKit.framework
swiftc -swift-version 6 -parse-as-library -F .build/Dependencies -framework VLCKit MoriPlayer/App/Language.swift MoriPlayer/Features/Player/PlayerModel.swift MoriPlayer/Features/Player/Subtitles.swift MoriPlayer/Features/Player/SRTScaling.swift Tests/VLCFormatProbe.swift -o .build/FormatTests/probe
for media in "$@"; do
 .build/FormatTests/probe "$media"
done
