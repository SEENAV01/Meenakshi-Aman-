#!/usr/bin/env bash
set -euo pipefail

readonly FLUTTER_VERSION="3.47.7"
readonly ANDROID_TOOLS_REVISION="16111833"
readonly TOOL_ROOT="${HOME}/.local/share/gyanify"
readonly FLUTTER_ROOT="${TOOL_ROOT}/flutter"
readonly ANDROID_HOME="${TOOL_ROOT}/android-sdk"

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

need_command curl
need_command tar
need_command unzip
need_command java

mkdir -p "${TOOL_ROOT}" "${ANDROID_HOME}/cmdline-tools"

if [[ ! -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
  archive="${TOOL_ROOT}/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  curl --fail --location --retry 3 \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    --output "${archive}"
  tar -xJf "${archive}" -C "${TOOL_ROOT}"
  rm "${archive}"
fi

if [[ ! -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]]; then
  archive="${TOOL_ROOT}/commandlinetools-linux-${ANDROID_TOOLS_REVISION}_latest.zip"
  temporary="${TOOL_ROOT}/cmdline-tools-extract"
  curl --fail --location --retry 3 \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_TOOLS_REVISION}_latest.zip" \
    --output "${archive}"
  rm -rf "${temporary}"
  mkdir -p "${temporary}"
  unzip -q "${archive}" -d "${temporary}"
  mv "${temporary}/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
  rm -rf "${temporary}" "${archive}"
fi

cat <<EOF
Flutter ${FLUTTER_VERSION} and Android command-line tools ${ANDROID_TOOLS_REVISION} are installed.
Before installing Android packages, review and accept Google's SDK licenses with:
  ANDROID_HOME="${ANDROID_HOME}" "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses
Then install the pinned Android packages with:
  ANDROID_HOME="${ANDROID_HOME}" "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --install "platform-tools" "platforms;android-36" "build-tools;36.0.0"
EOF