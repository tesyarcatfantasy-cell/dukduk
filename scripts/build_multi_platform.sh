#!/usr/bin/env bash
set -euo pipefail

# Multi-platform build script for fincent-api
# Builds for Linux amd64, Ubuntu 22.04 amd64, and macOS arm64
# Usage: ./scripts/build_multi_platform.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
OS_NAME=$(uname -s)
DUCKDB_VERSION="v1.4.0"

echo "Building fincent-api for multiple platforms..."
echo "Root directory: ${ROOT_DIR}"
echo "Artifacts will be output to: ${ARTIFACTS_DIR}"

mkdir -p "${ARTIFACTS_DIR}"

package_static_libs_zip() {
  local platform="$1"
  local source_dir="$2"
  local package_dir="${ARTIFACTS_DIR}/duckdb-static-libs-${platform}"
  local zip_path="${ARTIFACTS_DIR}/duckdb-static-libs-${platform}.zip"
  local lib_count
  local extension_count
  local extension_name

  if ! command -v zip >/dev/null 2>&1; then
    echo "Error: zip not installed. Required to package static libraries." >&2
    return 1
  fi

  if [[ ! -d "${source_dir}" ]]; then
    echo "Error: static library source directory not found: ${source_dir}" >&2
    return 1
  fi

  rm -rf "${package_dir}" "${zip_path}"
  mkdir -p "${package_dir}/duckdblib"

  find "${source_dir}" -type f -name "*.a" -exec cp {} "${package_dir}/duckdblib/" \;
  if [[ -d "${source_dir}/extension" ]]; then
    while IFS= read -r extension_file; do
      extension_name="$(basename "${extension_file}" .duckdb_extension)"
      mkdir -p "${package_dir}/duckdblib/extension/${extension_name}"
      cp "${extension_file}" "${package_dir}/duckdblib/extension/${extension_name}/"
    done < <(find "${source_dir}/extension" -mindepth 2 -maxdepth 2 -type f -name "*.duckdb_extension" | sort)
  fi

  lib_count="$(find "${package_dir}/duckdblib" -type f -name "*.a" | wc -l | tr -d ' ')"
  if [[ -d "${package_dir}/duckdblib/extension" ]]; then
    extension_count="$(find "${package_dir}/duckdblib/extension" -type f -name "*.duckdb_extension" | wc -l | tr -d ' ')"
  else
    extension_count="0"
  fi

  if [[ "${lib_count}" == "0" ]]; then
    echo "Error: no static libraries found in ${source_dir}" >&2
    return 1
  fi

  {
    echo "platform=${platform}"
    echo "duckdb_version=${DUCKDB_VERSION}"
    echo "library_count=${lib_count}"
    echo "extension_count=${extension_count}"
    echo "layout=duckdblib/*.a, duckdblib/extension/*/*.duckdb_extension"
  } > "${package_dir}/build-info.txt"

  (cd "${package_dir}" && zip -qr "${zip_path}" .)
  rm -rf "${package_dir}"

  echo "✓ Static libraries zip: ${zip_path} (${lib_count} libraries, ${extension_count} extensions)"
}

build_linux_docker_artifact() {
  local platform="$1"
  local dockerfile="$2"
  local image_name="fincent-api-builder:${platform}"
  local container_name="extract-${platform}"
  local binary_path="${ARTIFACTS_DIR}/fincent-api-${platform}"
  local tmp_libs="${ARTIFACTS_DIR}/.duckdblib-${platform}"

  echo ""
  echo "=== Building for ${platform} ==="

  if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker not installed. Required for Linux builds." >&2
    return 1
  fi

  docker build \
    --target appbuilder \
    --build-arg TARGETARCH=amd64 \
    -f "${dockerfile}" \
    -t "${image_name}" \
    "${ROOT_DIR}"

  echo "Extracting binary from Docker image..."
  docker rm -f "${container_name}" 2>/dev/null || true
  docker create --name "${container_name}" "${image_name}"
  docker cp "${container_name}:/app/main" "${binary_path}" || true

  echo "Extracting static libraries from Docker image..."
  rm -rf "${tmp_libs}"
  docker cp "${container_name}:/app/duckdblib" "${tmp_libs}"
  docker rm "${container_name}"

  if [ -f "${binary_path}" ]; then
    chmod +x "${binary_path}"
    echo "✓ ${platform} binary: ${binary_path}"
  else
    echo "Error: Failed to extract ${platform} binary from Docker" >&2
    return 1
  fi

  package_static_libs_zip "${platform}" "${tmp_libs}"
  rm -rf "${tmp_libs}"
}

build_linux_amd64() {
  build_linux_docker_artifact "linux-amd64" "${ROOT_DIR}/Dockerfile"
}

build_ubuntu_2204_amd64() {
  build_linux_docker_artifact "ubuntu-22.04-amd64" "${ROOT_DIR}/Dockerfile.ubuntu2204"
}

build_macos_arm64() {
  echo ""
  echo "=== Building for macOS arm64 ==="
  
  if [ "$OS_NAME" != "Darwin" ]; then
    echo "Warning: Not running on macOS. Skipping native macOS build." >&2
    echo "To build for macOS arm64, run this script on a macOS machine with Apple Silicon." >&2
    return 0
  fi

  # Check dependencies
  for cmd in cmake git python3 go make cc c++ zip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: $cmd not installed. Install Xcode Command Line Tools and required packages." >&2
      echo "Run: xcode-select --install" >&2
      echo "Then: brew install cmake git python3 go" >&2
      return 1
    fi
  done

  # Build DuckDB libraries
  echo "Building DuckDB native libraries..."
  export CMAKE_POLICY_VERSION_MINIMUM=3.5
  
  BUILD_DIR="${ROOT_DIR}/.build"
  DUCKDB_DIR="${BUILD_DIR}/duckdb"
  VCPKG_DIR="${BUILD_DIR}/vcpkg"

  mkdir -p "${BUILD_DIR}"

  if [[ ! -d "${DUCKDB_DIR}/.git" ]]; then
    git clone --depth 1 --branch "${DUCKDB_VERSION}" https://github.com/duckdb/duckdb.git "${DUCKDB_DIR}"
  else
    CURRENT_DUCKDB_VERSION="$(git -C "${DUCKDB_DIR}" describe --tags --exact-match 2>/dev/null || true)"
    if [[ "${CURRENT_DUCKDB_VERSION}" != "${DUCKDB_VERSION}" ]]; then
      echo "Switching DuckDB checkout from ${CURRENT_DUCKDB_VERSION:-unknown} to ${DUCKDB_VERSION}..."
      git -C "${DUCKDB_DIR}" fetch --depth 1 origin "refs/tags/${DUCKDB_VERSION}:refs/tags/${DUCKDB_VERSION}"
      git -C "${DUCKDB_DIR}" checkout --force "${DUCKDB_VERSION}"
    fi
  fi

  if [[ ! -d "${VCPKG_DIR}/.git" ]]; then
    git clone https://github.com/Microsoft/vcpkg.git "${VCPKG_DIR}"
  else
    if [[ "$(git -C "${VCPKG_DIR}" rev-parse --is-shallow-repository 2>/dev/null || echo false)" == "true" ]]; then
      echo "Detected shallow vcpkg clone, fetching full history..."
      git -C "${VCPKG_DIR}" fetch --unshallow || git -C "${VCPKG_DIR}" fetch --all --tags --prune
    else
      git -C "${VCPKG_DIR}" fetch --all --tags --prune
    fi
  fi

  "${VCPKG_DIR}/bootstrap-vcpkg.sh"

  export VCPKG_ROOT="${VCPKG_DIR}"
  cp "${ROOT_DIR}/extension_config_local.cmake" "${DUCKDB_DIR}/extension/extension_config_local.cmake"

  pushd "${DUCKDB_DIR}" >/dev/null
  CMAKE_POLICY_VERSION_MINIMUM=3.5 make extension_configuration
  CMAKE_POLICY_VERSION_MINIMUM=3.5 \
  USE_MERGED_VCPKG_MANIFEST=1 \
  VCPKG_TOOLCHAIN_PATH=../vcpkg/scripts/buildsystems/vcpkg.cmake \
  EXTENSION_STATIC_BUILD=1 \
  make -j"$(sysctl -n hw.logicalcpu)" bundle-library
  popd >/dev/null

  # Prepare duckdblib for app build
  TMP_DUCKDBLIB="${ROOT_DIR}/appgo/.duckdblib_build"
  mkdir -p "${TMP_DUCKDBLIB}"
  find "${DUCKDB_DIR}/build/release" -type f -name "*.a" -exec cp {} "${TMP_DUCKDBLIB}/" \;
  if [ -d "${DUCKDB_DIR}/build/release/extension" ]; then
    cp -R "${DUCKDB_DIR}/build/release/extension" "${TMP_DUCKDBLIB}/"
  fi

  package_static_libs_zip "macos-arm64" "${TMP_DUCKDBLIB}"

  # Build Go application
  echo "Building Go application..."
  pushd "${ROOT_DIR}/appgo" >/dev/null
  CGO_ENABLED=1 \
  CPPFLAGS="-DDUCKDB_STATIC_BUILD" \
  CGO_LDFLAGS="-L./.duckdblib_build -lduckdb_bundle -lminizip-ng -lstdc++ -lm -ldl -lexpat -lz -lcompression -lnanoarrow -lnanoarrow_ipc -lflatccrt" \
  go build -tags=duckdb_use_static_lib -o "${ARTIFACTS_DIR}/fincent-api-macos-arm64" ./duckdb-tester/main.go
  popd >/dev/null

  chmod +x "${ARTIFACTS_DIR}/fincent-api-macos-arm64"
  echo "✓ macOS arm64 binary: ${ARTIFACTS_DIR}/fincent-api-macos-arm64"

  # Cleanup
  rm -rf "${TMP_DUCKDBLIB}"
}

# Main execution
if [ "$OS_NAME" = "Darwin" ]; then
  echo "Detected macOS runner. Building for macOS."
  build_macos_arm64
else
  echo "Detected Linux runner. Building for Linux."
  build_linux_amd64
  build_ubuntu_2204_amd64
fi

echo ""
echo "=== Build Summary ==="
echo "Artifacts directory: ${ARTIFACTS_DIR}"
ls -lh "${ARTIFACTS_DIR}" || echo "No artifacts found."
