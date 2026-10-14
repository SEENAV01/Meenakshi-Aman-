#!/usr/bin/env bash
export FLUTTER_ROOT="${HOME}/.local/share/gyanify/flutter"
export ANDROID_HOME="${HOME}/.local/share/gyanify/android-sdk"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export PATH="${FLUTTER_ROOT}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"