#!/bin/sh

# HushBeam-Ollama macOS Build Script
# Based on Ollama build script, customized for HushBeam integration
#
# Note:
#  While testing, if you double-click on the HushBeam-Ollama.app
#  some state is left on MacOS and subsequent attempts
#  to build again will fail with:
#
#    hdiutil: create failed - Operation not permitted
#
#  To work around, specify another volume name with:
#
#    VOL_NAME="$(date)" ./scripts/build_darwin.sh
#
VOL_NAME=${VOL_NAME:-"HushBeam-Ollama"}
export VERSION=${VERSION:-$(git describe --tags --first-parent --abbrev=7 --long --dirty --always | sed -e "s/^v//g")}
export GOFLAGS="'-ldflags=-w -s \"-X=github.com/ollama/ollama/version.Version=${VERSION#v}\" \"-X=github.com/ollama/ollama/server.mode=release\"'"
export CGO_CFLAGS="-mmacosx-version-min=14.0"
export CGO_CXXFLAGS="-mmacosx-version-min=14.0"
export CGO_LDFLAGS="-mmacosx-version-min=14.0"

set -e

status() { echo >&2 ">>> $@"; }
usage() {
    echo "usage: $(basename $0) [build app [sign]]"
    exit 1
}

mkdir -p dist


ARCHS="arm64 amd64"
while getopts "a:h" OPTION; do
    case $OPTION in
        a) ARCHS=$OPTARG ;;
        h) usage ;;
    esac
done

shift $(( $OPTIND - 1 ))

_build_darwin() {
    for ARCH in $ARCHS; do
        status "Building darwin $ARCH"
        INSTALL_PREFIX=dist/darwin-$ARCH/
        # Output binary as hushbeam-ollama
        GOOS=darwin GOARCH=$ARCH CGO_ENABLED=1 go build -o ${INSTALL_PREFIX}hushbeam-ollama .

        if [ "$ARCH" = "amd64" ]; then
            status "Building darwin $ARCH dynamic backends"
            cmake -B build/darwin-$ARCH \
                -DCMAKE_OSX_ARCHITECTURES=x86_64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=11.3 \
                -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX
            cmake --build build/darwin-$ARCH --target ggml-cpu -j
            cmake --install build/darwin-$ARCH --component CPU
        fi
    done
}

_sign_darwin() {
    status "Creating universal binary..."
    mkdir -p dist/darwin
    lipo -create -output dist/darwin/hushbeam-ollama dist/darwin-*/hushbeam-ollama
    chmod +x dist/darwin/hushbeam-ollama

    if [ -n "$APPLE_IDENTITY" ]; then
        for F in dist/darwin/hushbeam-ollama dist/darwin-amd64/lib/ollama/*; do
            codesign -f --timestamp -s "$APPLE_IDENTITY" --identifier app.reckr.hushbeam.ollama --options=runtime $F
        done

        # create a temporary zip for notarization
        TEMP=$(mktemp -u).zip
        ditto -c -k --keepParent dist/darwin/hushbeam-ollama "$TEMP"
        xcrun notarytool submit "$TEMP" --wait --timeout 10m --apple-id $APPLE_ID --password $APPLE_PASSWORD --team-id $APPLE_TEAM_ID
        rm -f "$TEMP"
    fi

    status "Creating universal tarball..."
    tar -cf dist/hushbeam-ollama-darwin.tar --strip-components 2 dist/darwin/hushbeam-ollama
    tar -rf dist/hushbeam-ollama-darwin.tar --strip-components 4 dist/darwin-amd64/lib/
    gzip -9vc <dist/hushbeam-ollama-darwin.tar >dist/hushbeam-ollama-darwin.tgz
}

_build_macapp() {
    if ! command -v npm &> /dev/null; then
        echo "npm is not installed. Please install Node.js and npm first:"
        echo "   Visit: https://nodejs.org/"
        exit 1
    fi

    if ! command -v tsc &> /dev/null; then
        echo "Installing TypeScript compiler..."
        npm install -g typescript
    fi

    echo "Installing required Go tools..."

    cd app/ui/app
    npm install
    npm run build
    cd ../../..

    # Build the HushBeam-Ollama.app bundle
    rm -rf dist/HushBeam-Ollama.app
    cp -a ./app/darwin/HushBeam-Ollama.app dist/HushBeam-Ollama.app

    # update the modified date of the app bundle to now
    touch dist/HushBeam-Ollama.app

    go clean -cache
    GOARCH=amd64 CGO_ENABLED=1 GOOS=darwin go build -o dist/darwin-app-amd64 -ldflags="-s -w -X=github.com/ollama/ollama/app/version.Version=${VERSION}" ./app/cmd/app
    GOARCH=arm64 CGO_ENABLED=1 GOOS=darwin go build -o dist/darwin-app-arm64 -ldflags="-s -w -X=github.com/ollama/ollama/app/version.Version=${VERSION}" ./app/cmd/app
    mkdir -p dist/HushBeam-Ollama.app/Contents/MacOS
    lipo -create -output dist/HushBeam-Ollama.app/Contents/MacOS/HushBeam-Ollama dist/darwin-app-amd64 dist/darwin-app-arm64
    rm -f dist/darwin-app-amd64 dist/darwin-app-arm64

    # Create a mock Squirrel.framework bundle
    mkdir -p dist/HushBeam-Ollama.app/Contents/Frameworks/Squirrel.framework/Versions/A/Resources/
    cp -a dist/HushBeam-Ollama.app/Contents/MacOS/HushBeam-Ollama dist/HushBeam-Ollama.app/Contents/Frameworks/Squirrel.framework/Versions/A/Squirrel
    ln -s ../Squirrel dist/HushBeam-Ollama.app/Contents/Frameworks/Squirrel.framework/Versions/A/Resources/ShipIt
    cp -a ./app/cmd/squirrel/Info.plist dist/HushBeam-Ollama.app/Contents/Frameworks/Squirrel.framework/Versions/A/Resources/Info.plist
    ln -s A dist/HushBeam-Ollama.app/Contents/Frameworks/Squirrel.framework/Versions/Current
    ln -s Versions/Current/Resources dist/HushBeam-Ollama.app/Contents/Frameworks/Squirrel.framework/Resources
    ln -s Versions/Current/Squirrel dist/HushBeam-Ollama.app/Contents/Frameworks/Squirrel.framework/Squirrel

    # Update the version in the Info.plist
    plutil -replace CFBundleShortVersionString -string "$VERSION" dist/HushBeam-Ollama.app/Contents/Info.plist
    plutil -replace CFBundleVersion -string "$VERSION" dist/HushBeam-Ollama.app/Contents/Info.plist

    # Setup the hushbeam-ollama binaries
    mkdir -p dist/HushBeam-Ollama.app/Contents/Resources
    if [ -d dist/darwin-amd64 ]; then
        lipo -create -output dist/HushBeam-Ollama.app/Contents/Resources/hushbeam-ollama dist/darwin-amd64/hushbeam-ollama dist/darwin-arm64/hushbeam-ollama
        cp dist/darwin-amd64/lib/ollama/*.so dist/darwin-amd64/lib/ollama/*.dylib dist/HushBeam-Ollama.app/Contents/Resources/ 2>/dev/null || true
    else
        cp -a dist/darwin/hushbeam-ollama dist/HushBeam-Ollama.app/Contents/Resources/hushbeam-ollama
        cp dist/darwin/*.so dist/darwin/*.dylib dist/HushBeam-Ollama.app/Contents/Resources/ 2>/dev/null || true
    fi
    chmod a+x dist/HushBeam-Ollama.app/Contents/Resources/hushbeam-ollama

    # Sign
    if [ -n "$APPLE_IDENTITY" ]; then
        codesign -f --timestamp -s "$APPLE_IDENTITY" --identifier app.reckr.hushbeam.ollama --options=runtime dist/HushBeam-Ollama.app/Contents/Resources/hushbeam-ollama
        for lib in dist/HushBeam-Ollama.app/Contents/Resources/*.so dist/HushBeam-Ollama.app/Contents/Resources/*.dylib ; do
            codesign -f --timestamp -s "$APPLE_IDENTITY" --identifier app.reckr.hushbeam.ollama --options=runtime ${lib}
        done
        codesign -f --timestamp -s "$APPLE_IDENTITY" --identifier app.reckr.hushbeam.ollama --deep --options=runtime dist/HushBeam-Ollama.app
    fi

    rm -f dist/HushBeam-Ollama-darwin.zip
    ditto -c -k --keepParent dist/HushBeam-Ollama.app dist/HushBeam-Ollama-darwin.zip
    (cd dist/HushBeam-Ollama.app/Contents/Resources/; tar -cf - hushbeam-ollama *.so *.dylib 2>/dev/null) | gzip -9vc > dist/hushbeam-ollama-darwin.tgz

    # Notarize and Staple
    if [ -n "$APPLE_IDENTITY" ]; then
        $(xcrun -f notarytool) submit dist/HushBeam-Ollama-darwin.zip --wait --timeout 10m --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID"
        rm -f dist/HushBeam-Ollama-darwin.zip
        $(xcrun -f stapler) staple dist/HushBeam-Ollama.app
        ditto -c -k --keepParent dist/HushBeam-Ollama.app dist/HushBeam-Ollama-darwin.zip

        rm -f dist/HushBeam-Ollama.dmg

        (cd dist && ../scripts/create-dmg.sh \
            --volname "${VOL_NAME}" \
            --volicon ../app/darwin/HushBeam-Ollama.app/Contents/Resources/icon.icns \
            --background ../app/assets/background.png \
            --window-pos 200 120 \
            --window-size 800 400 \
            --icon-size 128 \
            --icon "HushBeam-Ollama.app" 200 190 \
            --hide-extension "HushBeam-Ollama.app" \
            --app-drop-link 600 190 \
            --text-size 12 \
            "HushBeam-Ollama.dmg" \
            "HushBeam-Ollama.app" \
        ; )
        rm -f dist/rw*.dmg

        codesign -f --timestamp -s "$APPLE_IDENTITY" --identifier app.reckr.hushbeam.ollama --options=runtime dist/HushBeam-Ollama.dmg
        $(xcrun -f notarytool) submit dist/HushBeam-Ollama.dmg --wait --timeout 10m --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID"
        $(xcrun -f stapler) staple dist/HushBeam-Ollama.dmg
    else
        echo "WARNING: Code signing disabled, this bundle will not work for upgrade testing"
    fi
}

if [ "$#" -eq 0 ]; then
    _build_darwin
    _sign_darwin
    _build_macapp
    exit 0
fi

for CMD in "$@"; do
    case $CMD in
        build) _build_darwin ;;
        sign) _sign_darwin ;;
        app) _build_macapp ;;
        *) usage ;;
    esac
done
