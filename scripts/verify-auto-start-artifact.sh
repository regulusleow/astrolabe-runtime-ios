#!/usr/bin/env bash

set -euo pipefail

configuration="${ASTROLABE_ARTIFACT_CONFIGURATION:-Debug}"
case "$configuration" in
  Debug|Release)
    ;;
  *)
    printf 'Unsupported artifact configuration: %s\n' "$configuration" >&2
    exit 1
    ;;
esac

derived_data="$(mktemp -d "${TMPDIR:-/tmp}/astrolabe-runtime-artifact.XXXXXX")"
trap 'rm -rf "$derived_data"' EXIT

xcodebuild \
  -scheme astrolabe-runtime-ios \
  -configuration "$configuration" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  -quiet \
  build

binary="$(
  find "$derived_data/Build/Products" \
    -path '*/AstrolabeRuntime.framework/AstrolabeRuntime' \
    -type f \
    -print \
    -quit
)"

if [[ -z "$binary" ]]; then
  printf 'AstrolabeRuntime framework binary was not produced.\n' >&2
  exit 1
fi

file_output="$(file "$binary")"
if ! grep -q 'dynamically linked shared library' <<< "$file_output"; then
  printf 'Framework is not a dynamic library: %s\n' "$file_output" >&2
  exit 1
fi

otool_output="$(otool -hv "$binary")"
if ! grep -Eq '(^|[[:space:]])DYLIB([[:space:]]|$)' <<< "$otool_output"; then
  printf 'Framework Mach-O header is not MH_DYLIB.\n' >&2
  exit 1
fi

symbols="$(nm -gjU "$binary")"
if ! grep -Fqx '_OBJC_CLASS_$_ASTRuntimeBootstrap' <<< "$symbols"; then
  printf 'Automatic Runtime Objective-C bootstrap symbol is missing.\n' >&2
  exit 1
fi
if ! grep -Fqx '_AstrolabeRuntimeInstallAutomaticBootstrap' <<< "$symbols"; then
  printf 'Automatic Runtime Swift bridge symbol is missing.\n' >&2
  exit 1
fi
if grep -Fqx '_OBJC_CLASS_$_ASTRuntime' <<< "$symbols"; then
  printf 'Legacy ASTRuntime class is still exported.\n' >&2
  exit 1
fi

printf 'Automatic Runtime framework artifact verified: %s\n' "$binary"
