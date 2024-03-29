#!/bin/bash

# ---------------------------------------------------------------------------
# imagedate - Rewrite file and metadata dates on images to increment in the
# order of the alphabetized filenames.
#
# I had a directory of images that were alphabetized by filename, and I wanted
# to import them into a popular photo-printing service. I wanted to order them
# by filename, but this particular service only offered sorting by the date the
# photos were taken (forward or back).
#
# So I went about finding out how to create sequential creation dates for these
# photos' metadata based on their alphabetized file names. Date and time of
# first image is customizable (default 2000:01:01 00:00:00) and images are
# separated in increments of 5 minutes.
#
# This script requires exiftool to be installed: sudo apt install exiftool

# Copyright 2022, Warren Galyen <wgalyen@bellhelmets.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License at <http://www.gnu.org/licenses/> for
# more details.
# USAGE
#
# $ ./imagedate.sh <DIR>
# $ ./imagedate.sh [-q|--quiet] <DIR>
# $ ./imagedate.sh [-h|--help]

# EXAMPLES
#
# $ ./imagedate.sh .
# $ ./imagedate.sh -q ./photos
#
# HELPFUL COMMANDS
# Additional tools you can use during this process.
#
# check file dates
# $ stat <FILE>
#
# check EXIF dates
# $ exiftool <FILE> | grep "Date"
#
# check EXIF dates and get relevant field parameters
# $ exiftool -a -G0:1 -time:all <FILE>
#
# clean up exiftool "_original" files if you've generated them
# $ exiftool -delete_original <DIR>
#
# show EXIF problems for an individual file or all files in a directory
# $ exiftool -validate -error -warning -a -r <FILE/DIR>
#
# RESOURCES
#
# https://askubuntu.com/questions/62492/how-can-i-change-the-date-modified-created-of-a-file
# https://www.thegeekstuff.com/2012/11/linux-touch-command/
# https://unix.stackexchange.com/questions/180315/bash-script-ask-for-user-input-to-change-a-directory-sub-directorys-and-file
# https://photo.stackexchange.com/questions/60342/how-can-i-incrementally-date-photos
# https://exiftool.org/forum/index.php?topic=3429.0

# Standard variables
PROGNAME=${0##*/}
VERSION="1.1"

# Usage: Separate lines for mutually exclusive options.
usage() {
    printf "%s\n" \
        "Usage: ${PROGNAME} [-q|--quiet] <DIR>"
    printf "%s\n" \
        "         ${PROGNAME} [-h|--help]"
}

# Help message for --help
help_message() {
    cat <<-_EOF_
  ${PROGNAME} ${VERSION}
  Rewrite file and metadata dates on images to increment in the order of the alphabetized filenames. Useful when you have a system (Snapfish) that will only order by date, but you want images ordered by filename. Date and time of first image is customizable (default 2000:01:01 00:00:00) and images are separated in increments of 5 minutes.
  $(usage)
  Options:
  -h, --help    Display this help message and exit.
  -q, --quiet   Quiet mode. Accept all defaults.
_EOF_
}

# Error handling
error_exit() {
    local error_message="$1"

    printf "%s\n" "${PROGNAME}: ${error_message:-"Unknown Error"}" >&2
    exit 1
}

# Handle trapped signals
signal_exit() {

    local signal="$1"

    case "$signal" in
    INT)
        error_exit "Program interrupted by user"
        ;;
    TERM)
        printf "\n%s\n" "$PROGNAME: Program terminated" >&2
        # graceful_exit
        ;;
    *)
        error_exit "$PROGNAME: Terminating on unknown signal"
        ;;
    esac
}

# Parse command line
needs_arg() { if [ -z "$OPTARG" ]; then die "No arg for --$OPT option"; fi; }
while getopts :hq-: OPT; do
    # support long options: https://stackoverflow.com/a/28466267/519360
    if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
        OPT="${OPTARG%%=*}"     # extract long option name
        OPTARG="${OPTARG#$OPT}" # extract long option argument (may be empty)
        OPTARG="${OPTARG#=}"    # if long option argument, remove assigning `=`
    fi
    case "$OPT" in
    h | help)
        help_message
        # graceful_exit
        ;;
    q | quiet)
        quiet_mode=true
        ;;
    # c | charlie)
    #   needs_arg
    #   charlie="$OPTARG"
    #   ;;
    ??*) # bad long option
        usage >&2
        error_exit "Unknown option --$OPT"
        ;;
    ?) # bad short option
        usage >&2
        error_exit "Unknown option -$OPTARG"
        ;;
    esac
done
shift $((OPTIND - 1)) # remove parsed options and args from $@ list

# Sanitize directory name

dir=$1
[[ "$dir" =~ ^[./].*$ ]] || dir="./$dir"

if [ -d "${dir}" ]; then # Make sure directory exists

    if [[ ! $quiet_mode ]]; then
        echo -e "\033[1;31mWARNING:\033[0m\033[1m This script will overwrite file and metadata dates for any images it finds in the directory \033[1;31m${dir}\033[0m\033[1m -- do you want to proceed? (y/N)\e[0m"
        read -r go
    fi

    if [[ $go == *"y"* || $quiet_mode ]]; then

        if [[ ! $quiet_mode ]]; then
            echo -e "\033[1;33mOn what date do you want your images to begin incrementing (YYYY:MM:DD, default 2000:01:01)?\e[0m"
            read -r startdate
        fi

        date="${startdate:=2000:01:01}"

        if [[ ! $quiet_mode ]]; then
            echo -e "\033[1;33mAt what time do you want your images to begin incrementing (HH:MM:SS, default 00:00:00)?\e[0m"
            read -r starttime
        fi

        time="${starttime:=00:00:00)}"

        # Begin...
        echo -e "\e[0;92mSetting image dates...\e[0m"

        # Set all files to sequential (alphabetical) modified date.
        touch -a -m -- "${dir}"/* || error_exit "touch failed in line $LINENO"

        # Now space them apart to ensure crappy photo software picks up on the
        # differences.
        for i in "${dir}"/*; do
            touch -r "$i" -d '-1 hour' "$i" || error_exit "touch failed in line $LINENO"
            sleep 0.005
        done

        # Use exiftool to set "all dates" (which is only standard image
        # creation/modification/access) to an arbitrary date, (P)reserving file
        # modification date.
        exiftool -overwrite_original -P -alldates="${date} ${time}" "${dir}"/. || error_exit "exiftool failed in line $LINENO"

        # Now update those dates sequentially separated apart (timestamps will kick
        # over to the next day/month/year as necessary), going alphabetically by
        # filename, at five-minute intervals.
        exiftool -fileorder FileName -overwrite_original -P '-alldates+<0:${filesequence;$_*=5}' "${dir}"/. || error_exit "exiftool failed in line $LINENO"

        # Update nonstandard "Date/Time Digitized" field to match creation date.
        exiftool -r -overwrite_original -P "-XMP-exif:DateTimeDigitized<CreateDate" "${dir}"/. || error_exit "exiftool failed in line $LINENO"

        # Update nonstandard and stupidly vague "Metadata Date" field to match
        # creation date.
        exiftool -r -overwrite_original -P "-XMP-xmp:MetadataDate<CreateDate" "${dir}"/. || error_exit "exiftool failed in line $LINENO"

        echo -e "\e[0;92m                      ...done.\e[0m"

    else
        echo -e "\e[0;92mOperation canceled.\e[0m"
    fi

else
    echo -e "\e[0;91mError. Directory \e[0m'${dir}'\e[0;91m not found.\e[0m"
fi
