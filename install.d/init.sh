#!/usr/bin/env bash

set -euo pipefail

source ./envpaths.sh

# Set GitHub URLs based on SSH_GITHUB flag
if [[ "$SSH_GITHUB" -eq 1 ]]; then
    CROCODASH_GITHUB="git@github.com:CROCODILE-CESM/CrocoDash.git"
    MODEL2OBS_GITHUB="git@github.com:CROCODILE-CESM/model2obs.git"
    CUPID_GITHUB="git@github.com:NCAR/CUPiD.git"
    CESM_GITHUB="git@github.com:CROCODILE-CESM/CESM"
    CESM_DA_GITHUB="git@github.com:CROCODILE-CESM/CESM"
else
    CROCODASH_GITHUB="https://github.com/CROCODILE-CESM/CrocoDash.git"
    MODEL2OBS_GITHUB="https://github.com/CROCODILE-CESM/model2obs.git"
    CUPID_GITHUB="https://github.com/NCAR/CUPiD.git"
    CESM_GITHUB="https://github.com/CROCODILE-CESM/CESM"
    CESM_DA_GITHUB="https://github.com/CROCODILE-CESM/CESM"
fi

#### Existence check
# Interrrupt install if any package is already at path

EXISTING_PACKAGES=()

check_existing() {
    if [ -d "$2" ]; then
        EXISTING_PACKAGES+=("$1 at $2")
    fi
}

if [[ "$INSTALL_CROCODASH" -eq 1 ]]; then
    check_existing "CrocoDash" "$CROCODASH_PATH"
fi
if [[ "$INSTALL_MODEL2OBS" -eq 1 ]]; then
    check_existing "model2obs" "$MODEL2OBS_PATH"
fi
if [[ "$INSTALL_CUPID" -eq 1 ]]; then
    check_existing "CUPiD" "$CUPID_PATH"
fi
if [[ "$INSTALL_CESM" -eq 1 ]]; then
    check_existing "CESM" "$CESM_PATH"
fi
if [[ "$INSTALL_CESM_DA" -eq 1 ]]; then
    check_existing "CESM_DA" "$CESM_DA_PATH"
fi

if [[ "${#EXISTING_PACKAGES[@]}" -gt 0 ]]; then
    echo "Error: the following selected packages are already installed:" >&2
    for PKG in "${EXISTING_PACKAGES[@]}"; do
        echo "  - $PKG" >&2
    done
    echo "Use -f or --force to remove and reinstall them, or deselect them." >&2
    exit 1
fi

#### CrocoDash

if [[ "$INSTALL_CROCODASH" -eq 1 ]]; then
    echo "Downloading CrocoDash..."
    git clone "$CROCODASH_GITHUB" "$CROCODASH_PATH"
    cd "$CROCODASH_PATH"
    git fetch --tags
    cd "$BASK_PATH"
    cd "$CROCODASH_PATH"
    git submodule update --init --recursive
    cd "gallery"
    git checkout main
    git pull
    cd "$BASK_PATH"
    echo "CrocoDash downloaded."
fi

#### model2obs

if [[ "$INSTALL_MODEL2OBS" -eq 1 ]]; then
    echo "Downloading model2obs..."
    git clone "$MODEL2OBS_GITHUB" "$MODEL2OBS_PATH"
    cd "$MODEL2OBS_PATH"
    git fetch --tags
    cd "$BASK_PATH"
    echo "model2obs downloaded."
fi

#### CUPiD

if [[ "$INSTALL_CUPID" -eq 1 ]]; then
    echo "Downloading CUPiD..."
    git clone "$CUPID_GITHUB" "$CUPID_PATH"
    cd "$CUPID_PATH"
    git fetch --tags
    git checkout v0.3.1
    cd "$BASK_PATH"
    cd "$CUPID_PATH"
    git submodule update --init --recursive
    cd "$BASK_PATH"
    echo "CUPiD downloaded."
fi

#### CESM

if [[ "$INSTALL_CESM" -eq 1 ]]; then
    echo "Downloading CESM..."
    git clone -b full_regional_cesm "$CESM_GITHUB" "$CESM_PATH"
    cd "$CESM_PATH"
    git pull
    echo "CESM downloaded."
fi

#### CESM_DA

if [[ "$INSTALL_CESM_DA" -eq 1 ]]; then
    echo "Downloading CESM_DA..."
    git clone -b full_regional_cesm_dart "$CESM_DA_GITHUB" "$CESM_DA_PATH"
    cd "$CESM_DA_PATH"
    git pull
    echo "CESM_DA downloaded."
fi
