#!/bin/bash

# Exit on error
set -e
set -x
echo "Starting build script..."

# User defined variables
TARGET=${1:-"all"}
PLATFORM=${2:-"linux"}
SCONS_VERSION=${3:-"4.4.0"}
FFMPEG_RELATIVE_PATH=${4:-""}

case ${PLATFORM} in
    "android")
        FFMPEG_RELATIVE_PATH=${FFMPEG_RELATIVE_PATH:-"ffmpeg-master-latest-android-arm64-lgpl-godot"}
        ;;
    "linux")
        FFMPEG_RELATIVE_PATH=${FFMPEG_RELATIVE_PATH:-"ffmpeg-master-latest-linux64-lgpl-godot"}
        ;;
    *)
        echo "Unsupported platform: ${PLATFORM}"
        exit 1
        ;;
esac
FFMPEG_URL_OR_PATH=${5:-"https://github.com/EIRTeam/FFmpeg-Builds/releases/\
download/latest/${FFMPEG_RELATIVE_PATH}.tar.xz"}
FFMPEG_TARBALL_PATH=${6:-"ffmpeg.tar.xz"}
SKIP_FFMPEG_IMPORT=${7:-"false"}
SCONS_FLAGS=${8:-"debug_symbols=no"}

# Fixed variables
SCONS_CACHE_DIR="scons-cache"
SCONS_CACHE_LIMIT="7168"
BUILD_DIR="gdextension_build"
OUTPUT_DIR="${BUILD_DIR}/build"

can_copy() {
    if [[ ! -f $1 ]]; then
        return 0
    fi

    if [[ ! -f $2 ]]; then
        return 1
    fi

    local src_inode=$(stat -c %i $1)
    local dest_inode=$(stat -c %i $2)
    if [[ $src_inode -eq $dest_inode ]]; then
        return 1
    fi
}

download_file() {
    # Args: $1=url $2=output_path
    local url="$1"
    local out="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$out" "$url"
    elif command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$out" "$url"
    else
        echo "Error: neither wget nor curl is available to download $url" >&2
        return 1
    fi
}

setup() {
    echo "Setting up to build for ${TARGET} with SCons ${SCONS_VERSION}"

    if [ "${SKIP_FFMPEG_IMPORT}" != "true" ]; then
        echo "Setting up FFmpeg. Source: ${FFMPEG_URL_OR_PATH}"
        if [[ -f ${FFMPEG_URL_OR_PATH} ]]; then
            if \
                [[ -f ${FFMPEG_TARBALL_PATH} ]] && \
                can_copy ${FFMPEG_URL_OR_PATH} ${FFMPEG_TARBALL_PATH}
            then
                echo "Copying FFmpeg from local path..."
                cp ${FFMPEG_URL_OR_PATH} ${FFMPEG_TARBALL_PATH}
            else
                echo "Given source is the same as the target. Skipping copy."
            fi
        else
            echo "Downloading FFmpeg..."
            # Download FFmpeg
            download_file "${FFMPEG_URL_OR_PATH}" "${FFMPEG_TARBALL_PATH}"
        fi
        # Validate archive (guard against GitHub HTML error pages downloaded as .tar.xz)
        if ! tar -tf "${FFMPEG_TARBALL_PATH}" >/dev/null 2>&1; then
            echo "Error: Downloaded file '${FFMPEG_TARBALL_PATH}' is not a valid tar archive." >&2
            echo "The URL may be wrong or blocked. You can: " >&2
            echo " - Manually download the Android FFmpeg tar.xz from the Releases page and pass its local path as the 5th arg to build.sh" >&2
            echo " - Or set the FFMPEG_URL_OR_PATH env/arg to a local .tar.xz path" >&2
            echo "First 200 bytes of the file for debugging:" >&2
            head -c 200 "${FFMPEG_TARBALL_PATH}" || true
            exit 1
        fi
        # Extract FFmpeg
        tar -xf ${FFMPEG_TARBALL_PATH}
        echo "FFmpeg extracted."
    fi

    # Ensure submodules are up to date
    git submodule update --init --recursive

    echo "Setting up SCons"
    # Set up virtual environment
    python -m venv venv
    if [[ -f "venv/Scripts/activate" ]]; then # For Windows (Git Bash)
        source venv/Scripts/activate
    else # For Linux/macOS
        source venv/bin/activate
    fi
    # Upgrade pip
    pip install --upgrade pip
    # Install SCons
    pip install scons==${SCONS_VERSION}
    # Exit virtual environment, as it will be re-entered later,
    # potentially from a different instance of the script (if TARGET is "all")
    deactivate
    echo "SCons $(scons --version) installed."

    echo "Setup complete."
}

build() {
    TARGET=${1:-"editor"}
    echo "Building ${TARGET}..."
    # Setup environment variables
    export SCONS_FLAGS="${SCONS_FLAGS}"
    export SCONS_CACHE="${SCONS_CACHE_DIR}"
    export SCONS_CACHE_LIMIT="${SCONS_CACHE_LIMIT}"
    export FFMPEG_PATH="${PWD}/${FFMPEG_RELATIVE_PATH}"

    # Enter virtual environment
    if [[ -f "venv/Scripts/activate" ]]; then # For Windows (Git Bash)
        source venv/Scripts/activate
    else # For Linux/macOS
        source venv/bin/activate
    fi
    # Enter build directory
    pushd ${BUILD_DIR}
    # Build
    scons \
        --debug=explain \
        platform=${PLATFORM} target=${TARGET} \
        ffmpeg_path=${FFMPEG_PATH} \
        ${SCONS_FLAGS}
    # Show build results
    ls -R build/addons/ffmpeg || echo "Build directory not found or ls failed." 

    # Exit build directory
    popd
    # Exit virtual environment
    deactivate
}

cleanup() {
    echo "Cleaning up..."
    # Remove the ffmpeg tarball
    rm -f ffmpeg.tar.xz
    echo "Cleanup complete."
    echo "The built addons folder is located at '${OUTPUT_DIR}'."
}

setup

if [ "${TARGET}" == "all" ]; then
    for target in "editor" "template_release" "template_debug"; do
        build ${target}
    done
    echo "Builds completed."
    cleanup
    exit 0
else
    build ${TARGET}
    echo "${TARGET} build completed."
    cleanup
fi

read -p "Press [Enter] key to continue..."

