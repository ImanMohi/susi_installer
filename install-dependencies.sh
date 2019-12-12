#!/bin/bash
# SUSI.AI Smart Assistant dependency installer script
# Copyright 2019 Norbert Preining
# 
# TODO
# - maybe add an option --try-system-install and then use apt-get etc as far as possible?
#   but how to deal with non-Debian systems
#
set -euo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

PROGS="git wget sox java vlc flac python3 pip3"

TRUSTPIP=0
CLEAN=1
BRANCH=development
RASPI=0
SUDOCMD=sudo
DISTPKGS=0
QUIET=""
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        --trust-pip)
            TRUSTPIP=1 ; shift ;;
        --no-clean)
            CLEAN=0 ; shift ;;
        --raspi)
            RASPI=1 ; shift ;;
        --use-dist-packages)
            DISTPKGS=1 ; shift ;;
        --sudo-cmd)
            SUDOCMD="$2" ; shift ; shift ;;
        --branch)
            BRANCH="$2" ; shift ; shift ;;
        --quiet)
            QUIET="-q" ; shift ;;
        --help)
            cat <<'EOF'
SUSI.AI Dependency Installer

Possible options:
  --trust-pip      Don't do version checks on pip3, trust it to be new enough
  --branch BRANCH  Use branch BRANCH to get requirement files (default: development)
  --raspi          Do additional installation tasks for the SUSI.AI Smart Speaker
  --sudo-cmd CMD   Use CMD instead of the default sudo
  --no-clean       Don't remove temp directory and don't use --no-cache-dir with pip3
  --quiet          Silence pip on installation
  --use-dist-packages (only with --raspi) Try to use distribution packages (apt-get on Debian etc)

EOF
            exit 0
            ;;
        *)
            echo "Unknown option or argument: $key" >&2
            exit 1
    esac
done


#
# On Raspberry susibian, install what is necessary
#
RASPIDEPS="
  git openssl wget python3-pip sox libsox-fmt-all flac libasound2-plugins
  libportaudio2 libatlas3-base libpulse0 libasound2 vlc-bin vlc-plugin-base
  vlc-plugin-video-splitter flite default-jdk-headless pixz udisks2 ca-certificates
  hostapd dnsmasq usbmount python3-setuptools python3-pyaudio
"
# TODO
# remove python3-pyaudio from the above when fury is updated with binary builds
# for Py3.7/arm

#
# TODO
# is python3-cairo really necessary????
# removed for now

RASPIPYTHONDEPS="
  python3-flask python3-requests python3-requests-futures python3-service-identity
  python3-pyaudio python3-levenshtein python3-pafy python3-colorlog python3-psutil
  python3-watson-developer-cloud python3-aiohttp python3-bs4 python3-mutagen
  python3-alsaaudio
"

if [ $RASPI = 1 ] ; then
    $SUDOCMD apt-get update
    $SUDOCMD apt-get install --no-install-recommends -y $RASPIDEPS
    if [ $DISTPKGS = 1 ] ; then
        $SUDOCMD apt-get install --no-install-recommends -y $RASPIPYTHONDEPS
    fi
    if [ $CLEAN = 1 ] ; then
        apt-get clean
    fi
fi

#
# Check necessary programs are available
#
prog_available() {
    if ! [ -x "$(command -v $1)" ]; then
        return 1
    fi
}
MISSINGPROGS=""
for i in $PROGS ; do
    if ! prog_available $i ; then
        MISSINGPROGS="$i $MISSINGPROGS"
    fi
done
if [ -n "$MISSINGPROGS" ] ; then
    echo "Required programs are not available, please install them first:" >&2
    echo "$MISSINGPROGS" >&2
    exit 1
fi
# check whether setuptools is installed
{
    ret=`pip3 show setuptools || true`
    if [ -z "$ret" ] ; then
        echo "Missing dependency: python3-setuptools, please install that first!" >&2
        exit 1
    fi
}

#
# check that pip3 is at least at version 18
#
UPDATEPIP=0
if [ $TRUSTPIP = 0 ] ; then
    pipversion=$(pip3 --version)
    pipversion=${pipversion#pip }
    pipversion=${pipversion%%.*}
    pipversion=${pipversion%% *}
    UNKNOWN=0
    case "$pipversion" in
        ''|*[!0-9]*) UNKNOWN=1 ;;
    esac
    if [ $UNKNOWN = 1 ] ; then
        echo "Cannot determine pip version number. Got \`$pipversion\' from \`pip3 --version\'" >&2
        echo "Please use \`--trust-pip\' to disable these checks if you are sure that pip is" >&2
        echo "at least at version 19!" >&2
        exit 1
    fi
    if [ "$pipversion" -lt 19 ] ; then
        echo "pip3 version \`$pipversion\' is less than the required version number 19" >&2
        echo "Will update pip3 using itself."
        UPDATEPIP=1
    fi
fi

PIP="pip3 $QUIET"
if [ $CLEAN = 1 ] ; then
    PIP="$PIP --no-cache-dir"
fi

if [ $UPDATEPIP = 1 ] ; then
    $SUDOCMD $PIP install -U pip
fi


reqs="
    susi_installer:requirements.txt
    susi_python:requirements.txt
    susi_linux:requirements.txt
    susi_installer:requirements-optional.txt
"
reqspi="
    susi_linux:requirements-rpi.txt
"

if [ $RASPI = 1 ] ; then
    reqs="$reqs $reqspi"
fi

# Create temp dir
tmpdir=$(mktemp -d)

# Download requirement files
for i in $reqs ; do
    p=$(echo $i | sed -e s+:+/$BRANCH/+)
    wget -q -O $tmpdir/$i https://raw.githubusercontent.com/fossasia/$p
done

# Install pips
for i in $reqs ; do
    $SUDOCMD $PIP install --extra-index-url https://repo.fury.io/fossasia/ -r $tmpdir/$i
done

# cleanup
if [ $CLEAN = 1 ] ; then
    for i in $reqs ; do
        rm $tmpdir/$i
    done
    rmdir $tmpdir
fi

echo "Finished."


# vim: set expandtab shiftwidth=4 softtabstop=4 smarttab:
