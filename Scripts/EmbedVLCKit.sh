#!/bin/sh
set -eu
mkdir -p "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
ditto "$SRCROOT/.build/Dependencies/VLCKit.framework" "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/VLCKit.framework"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/VLCKit.framework"
