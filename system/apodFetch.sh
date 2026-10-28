bash
#!/usr/bin/env bash

# https://github.com/taurhine/apodFetch
# Updated to use NASA's current APOD endpoint.
# Compatible with ImageMagick 7.

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
wpPath="$HOME/Documents/wallpapers/apod"
cachePath="$HOME"
apiPrefix="https://science.nasa.gov/wp-json/wp/v2/apod-basic"

targetDate=""
scaleMode="$defaultScaleMode"
description=""
title=""
mediaType=""
fileFullPath=""

ShowMessage()
{
    if [[ "$messagesAsNotification" == "enabled" ]] &&
       command -v notify-send >/dev/null 2>&1; then
        notify-send "$1" "$2" || echo "$1: $2"
    else
        echo "$1: $2"
    fi
}

CheckDependencies()
{
    local missing=0
    local dep

    for dep in curl python3 magick feh xrandr; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Missing dependency: $dep" >&2
            missing=1
        fi
    done

    if [[ "$missing" -ne 0 ]]; then
        exit 1
    fi

    echo "All required dependencies are installed."
    exit 0
}

EnsurePathExists()
{
    if ! mkdir -p "$1"; then
        ShowMessage "apodFetch: error" "Cannot create directory: $1"
        exit 1
    fi
}

GetParameters()
{
    scaleMode="$defaultScaleMode"

    case "${1:-}" in
        "")
            targetDate="$(date +%Y%m%d)"
            ;;

        "-d")
            CheckDependencies
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
            ShowMessage "apodFetch: error" "Unknown option: $1"
            exit 1
            ;;
    esac
}

GetDescription()
{
    # Description is obtained from the NASA API, not JPEG comments.
    :
}

ShowDescriptionAsNotification()
{
    if [[ "$descAsNotification" == "enabled" ]]; then
        ShowMessage "NASA APOD: $targetDate" "$description"
    fi
}

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
    jsonFile="$(mktemp)"
    infoFile="$(mktemp)"

    # Download today's (or the selected date's) APOD metadata.
    if ! curl -fLsS --retry 3 --retry-delay 2 \
        --get "$apiPrefix/" \
        --data-urlencode "date=$isoDate" \
        -o "$jsonFile"; then

        ShowMessage "apodFetch: error" \
            "Could not retrieve NASA APOD metadata for $isoDate"
        rm -f "$jsonFile" "$infoFile"
        return 1
    fi

    # Extract metadata safely, including HTML-formatted descriptions.
    if ! python3 - "$jsonFile" > "$infoFile" <<'PY'
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

if isinstance(data, list):
    if not data:
        raise SystemExit("No APOD entry returned for this date")
    item = data[0]
else:
    item = data

extractor = TextExtractor()
title = item.get("title", "NASA Astronomy Picture of the Day")
description = extractor.text(item.get("explanation", ""))
media_type = item.get("media_type", "")
image_url = ""

if media_type == "image":
    for key in ("hdurl", "image_url", "url"):
        value = item.get(key)
        if isinstance(value, str) and value.startswith(("https://", "http://")):
            image_url = value
            break
elif media_type == "video":
    # Only use an explicit thumbnail/image field, never the video URL.
    for key in ("thumbnail_url", "image_url"):
        value = item.get(key)
        if isinstance(value, str) and value.startswith(("https://", "http://")):
            image_url = value
            break

for value in (title, description, media_type, image_url):
    print(value.replace("\n", " ").replace("\r", " "))
PY
    then
        ShowMessage "apodFetch: error" \
            "Could not parse NASA's APOD response for $isoDate"
        rm -f "$jsonFile" "$infoFile"
        return 1
    fi

    mapfile -t apodInfo < "$infoFile"
    rm -f "$jsonFile" "$infoFile"

    title="${apodInfo[0]:-NASA APOD}"
    description="${apodInfo[1]:-}"
    mediaType="${apodInfo[2]:-}"
    imageUrl="${apodInfo[3]:-}"

    if [[ "$mediaType" != "image" && "$mediaType" != "video" ]]; then
        ShowMessage "apodFetch: error" \
            "Unsupported APOD media type: $mediaType"
        return 1
    fi

    if [[ -z "$imageUrl" ]]; then
        ShowMessage "apodFetch: info" \
            "APOD for $isoDate is a video or has no usable image/thumbnail. Wallpaper unchanged."
        return 1
    fi

    # Reuse a valid cached image. Remove empty or corrupted cache files.
    if [[ -f "$cachedImage" ]] &&
       magick identify "$cachedImage" >/dev/null 2>&1; then
        return 0
    fi

    rm -f "$cachedImage"

    tmpFile="$(mktemp "$wpPath/.apod-download-XXXXXX")"

    # Download into a temporary file so a failed download cannot leave
    # an empty or partial JPEG in the cache.
    if ! curl -fLsS --retry 3 --retry-delay 2 \
        "$imageUrl" -o "$tmpFile" ||
       [[ ! -s "$tmpFile" ]] ||
       ! magick identify "$tmpFile" >/dev/null 2>&1; then

        ShowMessage "apodFetch: error" \
            "Download failed or returned an invalid image for $isoDate"
        rm -f "$tmpFile"
        return 1
    fi

    # Normalize the downloaded image to JPEG, regardless of its source
    # extension or encoding.
    if ! magick "$tmpFile" -strip "$cachedImage"; then
        ShowMessage "apodFetch: error" \
            "Could not convert downloaded image to JPEG"
        rm -f "$tmpFile" "$cachedImage"
        return 1
    fi

    rm -f "$tmpFile"

    if [[ ! -s "$cachedImage" ]] ||
       ! magick identify "$cachedImage" >/dev/null 2>&1; then
        ShowMessage "apodFetch: error" \
            "The cached image failed validation"
        rm -f "$cachedImage"
        return 1
    fi

    return 0
}

ScaleAndSetWallpaper()
{
    local screenRes
    local screenW
    local resizeMode
    local -a effects

    if [[ ! -s "$fileFullPath" ]] ||
       ! magick identify "$fileFullPath" >/dev/null 2>&1; then
        ShowMessage "apodFetch: error" \
            "Missing or invalid image: $fileFullPath"
        return 1
    fi

    screenRes="$(xrandr --current |
        awk '/\*/ {print $1; exit}')"

    if [[ ! "$screenRes" =~ ^[0-9]+x[0-9]+$ ]]; then
        ShowMessage "apodFetch: error" \
            "Could not determine screen resolution"
        return 1
    fi

    case "$scaleMode" in
        "center")
            resizeMode=""
            ;;
        "fill")
            screenW="${screenRes%x*}"
            resizeMode="-resize ${screenW}x"
            ;;
        "fitall")
            resizeMode="-resize ${screenRes}"
            ;;
        *)
            resizeMode="-resize ${screenRes}"
            ;;
    esac

    # Resize and center the wallpaper on a black canvas.
    if [[ -n "$resizeMode" ]]; then
        # The configured resize mode is constructed from numeric resolution
        # values and is intentionally split into ImageMagick arguments.
        # shellcheck disable=SC2086
        if ! magick "$fileFullPath" $resizeMode \
            -background black -gravity center \
            -extent "$screenRes" "$wpPath/apod.png"; then
            ShowMessage "apodFetch: error" "Wallpaper scaling failed"
            return 1
        fi
    else
        if ! magick "$fileFullPath" \
            -background black -gravity center \
            -extent "$screenRes" "$wpPath/apod.png"; then
            ShowMessage "apodFetch: error" "Wallpaper scaling failed"
            return 1
        fi
    fi

    if [[ ! -s "$wpPath/apod.png" ]]; then
        ShowMessage "apodFetch: error" "Wallpaper PNG was not created"
        return 1
    fi

    if [[ -n "$effectOpt" ]]; then
        read -r -a effects <<< "$effectOpt"

        if ! magick "${effects[@]}" "$wpPath/apod.png" \
            "$wpPath/apod_lock.png"; then
            ShowMessage "apodFetch: error" \
                "Lock-screen effect failed"
            return 1
        fi
    else
        cp "$wpPath/apod.png" "$wpPath/apod_lock.png" || return 1
    fi

    # Add a description without embedding shell-sensitive text in -draw.
    if [[ "$lockscreenDesc" == "enabled" && -n "$description" ]]; then
        if ! magick "$wpPath/apod_lock.png" \
            -gravity northwest -pointsize 20 \
            -fill white -undercolor black \
            -annotate +10+20 "$description" \
            "$wpPath/apod_lock.png"; then
            ShowMessage "apodFetch: warning" \
                "Could not add description to lock-screen image"
        fi
    fi

    if ! feh --no-fehbg --bg-tile "$wpPath/apod.png"; then
        ShowMessage "apodFetch: error" "feh could not set the wallpaper"
        return 1
    fi

    return 0
}

# Main
EnsurePathExists "$cachePath"
EnsurePathExists "$wpPath"

GetParameters "${1:-}" "${2:-}" "${3:-}"

if ! DownloadPicture; then
    exit 1
fi

if ! ScaleAndSetWallpaper; then
    exit 1
fi

ShowDescriptionAsNotification
