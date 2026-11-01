#!/bin/sh
set -eu
mkdir -p "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
ditto "$SRCROOT/.build/Dependencies/VLCKit.framework" "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/VLCKit.framework"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ "$identity" = "-" ]; then
 codesign --force --sign "$identity" "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/VLCKit.framework"
else
 codesign --force --sign "$identity" --timestamp --options runtime "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/VLCKit.framework"
fi
