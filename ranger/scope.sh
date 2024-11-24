#!/usr/bin/env bash

# ranger preview script
# Updated: 2024
# Maintainer: Aditya Shakya <adi1090x@gmail.com>

set -o noclobber -o noglob -o nounset -o pipefail
IFS=$'\n'

# Script arguments
FILE_PATH="${1}"         # Full path of the highlighted file
PV_WIDTH="${2}"          # Width of the preview pane (number of fitting characters)
PV_HEIGHT="${3}"         # Height of the preview pane (number of fitting characters)
IMAGE_CACHE_PATH="${4}"  # Full path to cache image previews
PV_IMAGE_ENABLED="${5}"  # 'True' if image previews are enabled, 'False' otherwise.

# Settings
HIGHLIGHT_SIZE_MAX=262144 # 256KiB
HIGHLIGHT_TABWIDTH=8
HIGHLIGHT_STYLE='pablo'
PYGMENTIZE_STYLE='autumn'

# Extract file extension and MIME type
FILE_EXTENSION="${FILE_PATH##*.}"
FILE_EXTENSION_LOWER=$(echo "${FILE_EXTENSION}" | tr '[:upper:]' '[:lower:]')
MIMETYPE=$(file --dereference --brief --mime-type -- "${FILE_PATH}")

# Check for required commands
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: Required command '$1' not found. Install it to enable previews." >&2
        exit 1
    fi
}

# Ensure necessary tools are available
for cmd in file stat highlight; do
    check_command "${cmd}"
done

# Handlers
handle_extension() {
    case "${FILE_EXTENSION_LOWER}" in
        # Archives
        a|ace|alz|arc|arj|bz|bz2|cab|cpio|deb|gz|jar|lha|lz|lzh|lzma|lzo|rpm|rz|t7z|tar|tbz|tbz2|tgz|tlz|txz|tZ|tzo|war|xpi|xz|Z|zip)
            if command -v atool &> /dev/null; then
                atool --list -- "${FILE_PATH}" && exit 5
            fi
            if command -v bsdtar &> /dev/null; then
                bsdtar --list --file "${FILE_PATH}" && exit 5
            fi
            exit 1;;
        rar)
            unrar lt -p- -- "${FILE_PATH}" && exit 5 || exit 1;;
        7z)
            7z l -p -- "${FILE_PATH}" && exit 5 || exit 1;;
        pdf)
            if command -v pdftotext &> /dev/null; then
                pdftotext -l 10 -nopgbrk -q -- "${FILE_PATH}" - && exit 5
            fi
            exiftool "${FILE_PATH}" && exit 5 || exit 1;;
        torrent)
            transmission-show -- "${FILE_PATH}" && exit 5 || exit 1;;
        odt|ods|odp|sxw)
            odt2txt "${FILE_PATH}" && exit 5 || exit 1;;
        htm|html|xhtml)
            for cmd in w3m lynx elinks; do
                if command -v "${cmd}" &> /dev/null; then
                    "${cmd}" -dump "${FILE_PATH}" && exit 5
                fi
            done
            exit 1;;
    esac
}

handle_image() {
    local mimetype="${1}"
    case "${mimetype}" in
        image/svg+xml)
            convert "${FILE_PATH}" "${IMAGE_CACHE_PATH}" && exit 6 || exit 1;;
        image/*)
            local orientation
            orientation=$(identify -format '%[EXIF:Orientation]\n' -- "${FILE_PATH}" 2>/dev/null || echo "")
            if [[ -n "$orientation" && "$orientation" != 1 ]]; then
                convert -- "${FILE_PATH}" -auto-orient "${IMAGE_CACHE_PATH}" && exit 6 || exit 1
            fi
            exit 7;;
        video/*)
            ffmpegthumbnailer -i "${FILE_PATH}" -o "${IMAGE_CACHE_PATH}" -s 0 && exit 6 || exit 1;;
        application/pdf)
            pdftoppm -f 1 -l 1 -scale-to-x 1920 -scale-to-y -1 -singlefile -jpeg -tiffcompression jpeg -- "${FILE_PATH}" "${IMAGE_CACHE_PATH%.*}" && exit 6 || exit 1;;
    esac
}

handle_mime() {
    local mimetype="${1}"
    case "${mimetype}" in
        text/*|*/xml)
            if [[ $(stat --printf='%s' -- "${FILE_PATH}") -gt ${HIGHLIGHT_SIZE_MAX} ]]; then
                exit 2
            fi
            local format="ansi"
            [[ "$(tput colors)" -ge 256 ]] && format="xterm256"
            highlight --replace-tabs="${HIGHLIGHT_TABWIDTH}" --out-format="${format}" --style="${HIGHLIGHT_STYLE}" --force -- "${FILE_PATH}" && exit 5 || exit 2;;
        image/*)
            exiftool "${FILE_PATH}" && exit 5 || exit 1;;
        video/*|audio/*)
            mediainfo "${FILE_PATH}" && exit 5 || exiftool "${FILE_PATH}" && exit 5 || exit 1;;
    esac
}

handle_fallback() {
    echo '----- File Type Classification -----'
    file --dereference --brief -- "${FILE_PATH}" && exit 5 || exit 1
}

# Main logic
if [[ "${PV_IMAGE_ENABLED}" == "True" ]]; then
    handle_image "${MIMETYPE}"
fi
handle_extension
handle_mime "${MIMETYPE}"
handle_fallback

exit 1

