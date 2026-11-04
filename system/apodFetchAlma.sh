#!/usr/bin/env bash

# apodFetch - NASA Astronomy Picture of the Day
# AlmaLinux compatible
# ImageMagick 6 and 7 compatible

set -o pipefail

##################
# Static options #
##################

defaultScaleMode="fill"

# Effects applied to the lock-screen background
effectOpt="-paint 2 -noise 10"

# Show description as notification on wallpaper change
descAsNotification="disabled"

# Show apodFetch messages as notifications
messagesAsNotification="enabled"

# Show description on lock-screen
lockscreenDesc="enabled"

######################################################

hashNameExt=".apodcache"
wpPath="$HOME/yed/apod"
cachePath="$HOME"

apiPrefix="https://science.nasa.gov/wp-json/wp/v2/apod-basic"

targetDate=""
scaleMode="$defaultScaleMode"
description=""
title=""
mediaType=""
fileFullPath=""

#############################
# ImageMagick compatibility #
#############################

if command -v magick >/dev/null 2>&1; then
    IM_VERSION=7
    IM=(magick)

elif command -v convert >/dev/null 2>&1 &&
     command -v identify >/dev/null 2>&1; then
    IM_VERSION=6
    IM=(convert)

else
    echo "Error: ImageMagick is not installed."
    exit 1
fi

IdentifyImage()
{
    if [[ "$IM_VERSION" -eq 7 ]]; then
        magick identify "$@"
    else
        identify "$@"
    fi
}

##################
# Notifications  #
##################

ShowMessage()
{
    if [[ "$messagesAsNotification" == "enabled" ]] &&
       command -v notify-send >/dev/null 2>&1; then

        notify-send "$1" "$2" 2>/dev/null || echo "$1: $2"
    else
        echo "$1: $2"
    fi
}

##################
# Dependencies   #
##################

CheckDependencies()
{
    local missing=0
    local dep

    for dep in curl python3 feh xrandr; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Missing dependency: $dep" >&2
            missing=1
        fi
    done

    if ! command -v identify >/dev/null 2>&1; then
        echo "Missing dependency: identify" >&2
        missing=1
    fi

    if [[ "$missing" -ne 0 ]]; then
        return 1
    fi

    echo "All required dependencies are installed."
    echo "ImageMagick version: $IM_VERSION"

    return 0
}

##################
# Directory setup #
##################

EnsurePathExists()
{
    if ! mkdir -p "$1"; then
        ShowMessage "apodFetch: error" \
            "Cannot create directory: $1"
        exit 1
    fi
}

##################
# Parameters     #
##################

GetParameters()
{
    scaleMode="$defaultScaleMode"

    case "${1:-}" in

        "")
            targetDate="$(date +%Y%m%d)"
            ;;

        "-d")
            CheckDependencies
            exit $?
            ;;

        "-r")
            local randomDay

            randomDay="$(( (RANDOM % 365) + 1 ))"

            targetDate="$(date --date="-$randomDay days" +%Y%m%d)"
            ;;

        "-c")
            if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                targetDate="$(date --date="-${2} days" +%Y%m%d)"

            elif [[ "${2:-}" == "today" ]]; then
                targetDate="$(date +%Y%m%d)"

            else
                ShowMessage "apodFetch: error" \
                    "Invalid parameter for -c: ${2:-}"
                exit 1
            fi

            case "${3:-}" in
                "")
                    scaleMode="$defaultScaleMode"
                    ;;

                "fill" | "fitall" | "center")
                    scaleMode="$3"
                    ;;

                *)
                    ShowMessage "apodFetch: error" \
                        "Unknown scale mode: $3"
                    exit 1
                    ;;
            esac
            ;;

        *)
            ShowMessage "apodFetch: error" \
                "Unknown option: $1"
            exit 1
            ;;
    esac
}

##################
# Description    #
##################

ShowDescriptionAsNotification()
{
    if [[ "$descAsNotification" == "enabled" ]]; then
        ShowMessage "NASA APOD: $targetDate" "$description"
    fi
}

##################
# Download APOD  #
##################

DownloadPicture()
{
    local isoDate
    local jsonFile
    local infoFile
    local tmpFile
    local imageUrl
    local cachedImage="$wpPath/$targetDate.jpg"

    fileFullPath="$cachedImage"

    isoDate="${targetDate:0:4}-${targetDate:4:2}-${targetDate:6:2}"

    jsonFile="$(mktemp)" || return 1
    infoFile="$(mktemp)" || {
        rm -f "$jsonFile"
        return 1
    }

    # Retrieve NASA APOD metadata.

    echo "Retrieving NASA APOD metadata for $isoDate..."

    if ! curl -fLsS \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 20 \
        --max-time 60 \
        "$apiPrefix/?date=$isoDate" \
        -o "$jsonFile"; then

        ShowMessage "apodFetch: error" \
            "Could not retrieve NASA APOD metadata for $isoDate"

        rm -f "$jsonFile" "$infoFile"
        return 1
    fi

    # Parse API response.
    # NASA can return an array containing multiple APOD entries.
    # Select the exact requested date.

    if ! python3 - "$jsonFile" "$isoDate" > "$infoFile" <<'PY'
import json
import sys
from html.parser import HTMLParser

class TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def text(self, html):
        self.parts = []
        self.feed(html or "")
        self.close()
        return " ".join(" ".join(self.parts).split())

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

requested_date = sys.argv[2]

if isinstance(data, list):
    item = next(
        (entry for entry in data
         if entry.get("date") == requested_date),
        None
    )
else:
    item = data if data.get("date") == requested_date else None

if item is None:
    raise SystemExit(
        f"No APOD entry found for {requested_date}"
    )

extractor = TextExtractor()

title = item.get("title") or "NASA Astronomy Picture of the Day"
description = extractor.text(item.get("explanation", ""))
media_type = item.get("media_type", "")

image_url = ""

if media_type == "image":
    for key in ("hdurl", "image_url"):
        value = item.get(key)

        if isinstance(value, str) and value.startswith("https://"):
            image_url = value
            break

elif media_type in ("video", "iframe"):
    for key in ("hdurl", "thumbnail_url", "image_url"):
        value = item.get(key)

        if isinstance(value, str) and value.startswith("https://"):
            image_url = value
            break

for value in (title, description, media_type, image_url):
    print(value.replace("\n", " ").replace("\r", " "))
PY
    then
        ShowMessage "apodFetch: error" \
            "Could not parse NASA APOD response for $isoDate"

        rm -f "$jsonFile" "$infoFile"
        return 1
    fi

    mapfile -t apodInfo < "$infoFile"

    rm -f "$jsonFile" "$infoFile"

    title="${apodInfo[0]:-NASA APOD}"
    description="${apodInfo[1]:-}"
    mediaType="${apodInfo[2]:-}"
    imageUrl="${apodInfo[3]:-}"

    echo "APOD title: $title"
    echo "Media type: $mediaType"

    if [[ "$mediaType" != "image" &&
          "$mediaType" != "video" &&
          "$mediaType" != "iframe" ]]; then

        ShowMessage "apodFetch: error" \
            "Unsupported APOD media type: $mediaType"

        return 1
    fi

    if [[ -z "$imageUrl" ]]; then
        ShowMessage "apodFetch: info" \
            "No usable image or thumbnail available. Wallpaper unchanged."

        return 1
    fi

    # Reuse valid cached image.

    if [[ -f "$cachedImage" ]] &&
       IdentifyImage "$cachedImage" >/dev/null 2>&1; then

        echo "Using cached APOD image."
        return 0
    fi

    rm -f "$cachedImage"

    # Download to temporary file.

    tmpFile="$(mktemp "$wpPath/.apod-download-XXXXXX")" || {
        ShowMessage "apodFetch: error" \
            "Could not create temporary download file"
        return 1
    }

    echo "Downloading APOD image..."

    if ! curl -fLsS \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 20 \
        --max-time 180 \
        -A 'Mozilla/5.0 apodFetch/1.0' \
        "$imageUrl" \
        -o "$tmpFile"; then

        ShowMessage "apodFetch: error" \
            "NASA image download failed for $isoDate"

        rm -f "$tmpFile"
        return 1
    fi

    # Validate downloaded image.

    if [[ ! -s "$tmpFile" ]] ||
       ! IdentifyImage "$tmpFile" >/dev/null 2>&1; then

        echo "Downloaded file is invalid:"
        file "$tmpFile"

        ShowMessage "apodFetch: error" \
            "Download returned an invalid image for $isoDate"

        rm -f "$tmpFile"
        return 1
    fi

    # Convert source image to JPEG.

    echo "Converting APOD image to JPEG..."

    if ! "${IM[@]}" "$tmpFile" \
        -strip "$cachedImage"; then

        ShowMessage "apodFetch: error" \
            "Could not convert downloaded image to JPEG"

        rm -f "$tmpFile" "$cachedImage"
        return 1
    fi

    rm -f "$tmpFile"

    # Validate cached JPEG.

    if [[ ! -s "$cachedImage" ]] ||
       ! IdentifyImage "$cachedImage" >/dev/null 2>&1; then

        ShowMessage "apodFetch: error" \
            "Cached image failed validation"

        rm -f "$cachedImage"
        return 1
    fi

    echo "APOD image downloaded successfully."

    return 0
}

##################
# Wallpaper setup #
##################

ScaleAndSetWallpaper()
{
    local screenRes
    local screenW
    local lockTmp
    local -a resizeArgs=()
    local -a effects=()

    if [[ ! -s "$fileFullPath" ]] ||
       ! IdentifyImage "$fileFullPath" >/dev/null 2>&1; then

        ShowMessage "apodFetch: error" \
            "Missing or invalid image: $fileFullPath"

        return 1
    fi

    # Get screen resolution.

    screenRes="$(xrandr --current |
        awk '/\*/ {print $1; exit}')"

    if [[ ! "$screenRes" =~ ^[0-9]+x[0-9]+$ ]]; then
        ShowMessage "apodFetch: error" \
            "Could not determine screen resolution"

        return 1
    fi

    # Determine scaling mode.

    case "$scaleMode" in

        "center")
            resizeArgs=()
            ;;

        "fill")
            screenW="${screenRes%x*}"
            resizeArgs=(-resize "${screenW}x")
            ;;

        "fitall")
            resizeArgs=(-resize "$screenRes")
            ;;

        *)
            resizeArgs=(-resize "$screenRes")
            ;;
    esac

    echo "Screen resolution: $screenRes"
    echo "Scaling mode: $scaleMode"

    # Create wallpaper PNG.

    if ! "${IM[@]}" "$fileFullPath" \
        "${resizeArgs[@]}" \
        -background black \
        -gravity center \
        -extent "$screenRes" \
        "$wpPath/apod.png"; then

        ShowMessage "apodFetch: error" \
            "Wallpaper scaling failed"

        return 1
    fi

    if [[ ! -s "$wpPath/apod.png" ]]; then
        ShowMessage "apodFetch: error" \
            "Wallpaper PNG was not created"

        return 1
    fi

    # Apply lock-screen effects.

    if [[ -n "$effectOpt" ]]; then

        read -r -a effects <<< "$effectOpt"

        if ! "${IM[@]}" "${effects[@]}" \
            "$wpPath/apod.png" \
            "$wpPath/apod_lock.png"; then

            ShowMessage "apodFetch: error" \
                "Lock-screen effect failed"

            return 1
        fi

    else
        cp "$wpPath/apod.png" \
            "$wpPath/apod_lock.png" || return 1
    fi

    # Add APOD description to lock-screen image.

    if [[ "$lockscreenDesc" == "enabled" &&
          -n "$description" ]]; then

        lockTmp="$wpPath/.apod-lock-$$.png"

        if "${IM[@]}" "$wpPath/apod_lock.png" \
            -gravity northwest \
            -pointsize 20 \
            -fill white \
            -undercolor black \
            -annotate +10+20 "$description" \
            "$lockTmp"; then

            mv -f "$lockTmp" "$wpPath/apod_lock.png"

        else
            rm -f "$lockTmp"

            ShowMessage "apodFetch: warning" \
                "Could not add description to lock-screen image"
        fi
    fi

    # Set desktop wallpaper.

    if ! feh --no-fehbg --bg-tile "$wpPath/apod.png"; then

        ShowMessage "apodFetch: error" \
            "feh could not set the wallpaper"

        return 1
    fi

    echo "Wallpaper successfully updated."

    return 0
}


##################
# Main           #
##################

echo "--------------------------------"
echo " NASA APOD Downloader"
echo "--------------------------------"

echo "ImageMagick version: $IM_VERSION"

EnsurePathExists "$cachePath"
EnsurePathExists "$wpPath"

GetParameters "${1:-}" "${2:-}" "${3:-}"

if ! DownloadPicture; then
    exit 1
fi

# Save APOD description
if [[ -n "$description" ]]; then
    printf '%s\n' "$description" > "$wpPath/apod.txt"
fi

# Headless server: no display available
if [[ -z "${DISPLAY:-}" &&
      -z "${WAYLAND_DISPLAY:-}" ]]; then

    echo "No graphical session detected."
    echo "Skipping wallpaper operations."

    cp -f "$fileFullPath" "$wpPath/apod.jpg" || exit 1

    echo "APOD image: $wpPath/apod.jpg"
    echo "APOD description: $wpPath/apod.txt"
    echo "Download completed successfully."

    exit 0
fi

# Graphical session
if ! ScaleAndSetWallpaper; then
    exit 1
fi

ShowDescriptionAsNotification

echo "Done."


