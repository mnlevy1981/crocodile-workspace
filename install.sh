#!/usr/bin/env bash

set -euo pipefail

show_help() {
    cat << EOF
Usage: ./install.sh [OPTIONS]

Package Selection:
  --cesm            Install CESM model
  --cesm_da         Install CESM_DA DART-enabled CESM (with --notebooks, also
                    builds a CESM_DA conda env for the DART notebooks)
  --model2obs       Install model2obs diagnostics tools
  --crocodash       Install CrocoDash model components
  --cupid           Install CUPiD diagnostics framework
  --dart            Root of an existing DART installation (used by model2obs)
  --notebooks       Render CrocoGallery notebooks listed in install.d/notebooks.txt
                    into <BASK_PATH>/workspace/ (implies --crocodash)
  --all             Install all packages (includes --notebooks)
  --workshop        Install all packages except CUPiD (includes --notebooks)

Installation Options:
  -d, --default     Use default paths for all packages (default behaviour, non-interactive)
  -p, --paths       Specify paths for all packages (interactive)
  -f, --force       Remove and reinstall selected packages if they already exist
  -s, --ssh-github  Use SSH URLs instead of HTTPS for GitHub clones (requires SSH key)
  -e, --envname     Specify prefix for conda environment names (default: none)
  -h, --help        Display this help message

Examples:
  ./install.sh --workshop
  ./install.sh --crocodash --model2obs
  ./install.sh --all --paths
  ./install.sh --cesm -d -f
  ./install.sh --crocodash --notebooks
  ./install.sh --model2obs --dart /glade/work/me/DART

Notes:
  - Multiple flags can be combined
  - If a package already exists, the installer stops unless -f/--force is used
  - Edit install.d/notebooks.txt to change which gallery notebooks --notebooks renders
  - DART is not installed here: model2obs is pointed at an existing build.
    Override its location with --dart, or by exporting DART_ROOT_PATH.
EOF
}

is_ncar_hpc_host() {
    hostname_value=$(hostname -s 2>/dev/null || hostname)
    hostname_value=$(printf '%s' "$hostname_value" | tr '[:upper:]' '[:lower:]')
    case "$hostname_value" in
        dec*|derecho*|crlogin*|crht*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

if is_ncar_hpc_host; then
    module load conda/latest
fi


# Check for help flag
SHOW_HELP="0"
if [ "$#" -eq 0 ]; then
    SHOW_HELP="1"
    echo "One or more packages need to be specified"
    echo ""
fi
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        SHOW_HELP="1"
    fi
done
if [[ "$SHOW_HELP" -eq 1 ]]; then
    show_help
    exit 0
fi

# generate environmental variables
INSTALL_DIR="$PWD/install.d"
cd $INSTALL_DIR
if ! ./generate_envpaths.sh "$@"; then # pass all flags
    echo ""
    show_help
    exit 1
fi

# clean already installed submodules
source ./envpaths.sh

# model2obs runs DART's perfect_model_obs and imports DART's CrocoLake
# converter, so check the DART root before building any conda environment.
if [[ "$INSTALL_MODEL2OBS" -eq 1 ]]; then
    DART_ERRORS=()
    if [[ ! -x "$DART_ROOT_PATH/models/MOM6/work/perfect_model_obs" ]]; then
        DART_ERRORS+=("not an executable: $DART_ROOT_PATH/models/MOM6/work/perfect_model_obs")
    fi
    if [[ ! -d "$DART_ROOT_PATH/observations/obs_converters/CrocoLake" ]]; then
        DART_ERRORS+=("not a directory:   $DART_ROOT_PATH/observations/obs_converters/CrocoLake")
    fi
    if [[ "${#DART_ERRORS[@]}" -gt 0 ]]; then
        echo "Error: $DART_ROOT_PATH does not look like a compiled DART installation." >&2
        for DART_ERROR in "${DART_ERRORS[@]}"; do
            echo "  - $DART_ERROR" >&2
        done
        echo "model2obs needs both of the above. Point the installer at your own build with" >&2
        echo "    ./install.sh <flags> --dart /path/to/DART" >&2
        echo "or by exporting DART_ROOT_PATH. Note that DART must be compiled for the" >&2
        echo "machine you are installing on." >&2
        exit 1
    fi
fi

if [[ "$FORCE" -eq 1 ]]; then
    ./clean.sh
fi

# download submodules
./init.sh

# install submodules

# Source helper function
source ./setup_conda_env.sh

NBS_PATH=$BASK_PATH"/workspace/"
mkdir -p $NBS_PATH
if [[ -n ${ENV_PREFIX:-} ]]; then
    ENV_PREFIX="${ENV_PREFIX}-"
fi
# CrocoDash
if [[ "$INSTALL_CROCODASH" -eq 1 ]]; then
    echo "Installing CrocoDash environment..."
    cd "$CROCODASH_PATH"
    CROCODASH_SHA=$(git rev-parse HEAD)
    cd "$INSTALL_DIR"
    ENV_NAME=$(awk -F ": " '/^name:/ {print $2}' "$CROCODASH_PATH/environment.yml")
    CROCODASH_ENV_NAME="${ENV_PREFIX}${ENV_NAME}"
    mamba env create -f "$CROCODASH_PATH"/environment.yml --name ${CROCODASH_ENV_NAME} --yes
    add_env_vars_to_conda "$CROCODASH_ENV_NAME"
    echo "CrocoDash environment installed."
fi

# CrocoGallery notebooks
RENDERED_NOTEBOOKS=()
if [[ "$INSTALL_NOTEBOOKS" -eq 1 ]]; then
    NOTEBOOKS_LIST="$INSTALL_DIR/notebooks.txt"
    if [[ ! -f "$NOTEBOOKS_LIST" ]]; then
        echo "WARNING: --notebooks passed but $NOTEBOOKS_LIST is missing; skipping."
    elif [[ -z "${CROCODASH_ENV_NAME:-}" ]]; then
        echo "WARNING: --notebooks requires the CrocoDash env; skipping notebook rendering."
    else
        mkdir -p "$CASES_PATH" "$INPUT_PATH"

        # The gallery's shared dataset paths (GEBCO, TPXO, ...) are GLADE
        # locations, so only ask for them when we are actually on GLADE;
        # elsewhere the notebooks keep their <KEY> placeholders for the user
        # to fill in. The three paths Bask itself owns are always injected,
        # since the installer is the only thing that knows where they landed.
        TEMPLATE_ARGS=()
        # if [[ -d /glade/campaign/cesm/cesmdata/inputdata ]]; then
        #     TEMPLATE_ARGS+=(--machine glade)
        # fi
        TEMPLATE_ARGS+=(--set "casedir=$CASES_PATH" --set "inputdir=$INPUT_PATH")
        if [[ -n "${CESM_PATH:-}" ]]; then
            TEMPLATE_ARGS+=(--set "CESM=$CESM_PATH")
        fi

        echo "Rendering CrocoGallery notebooks into $NBS_PATH..."
        echo "  cases -> $CASES_PATH"
        echo "  input -> $INPUT_PATH"
        while IFS= read -r NB || [[ -n "$NB" ]]; do
            NB="${NB%%#*}"
            NB="${NB//[[:space:]]/}"
            [[ -z "$NB" ]] && continue
            OUTPUT="${NBS_PATH}${NB}.ipynb"
            echo "  - $NB -> $OUTPUT"
            conda run -n "$CROCODASH_ENV_NAME" crocogallery template \
                "${TEMPLATE_ARGS[@]}" \
                --notebook "$NB" \
                --output "$OUTPUT"
            RENDERED_NOTEBOOKS+=("$NB")
        done < "$NOTEBOOKS_LIST"
        echo "CrocoGallery notebooks rendered."
    fi
fi

# model2obs
if [[ "$INSTALL_MODEL2OBS" -eq 1 ]]; then
    echo "Installing model2obs environment..."
    cd "$MODEL2OBS_PATH"/install
    MODEL2OBS_SHA=$(git rev-parse HEAD)
    cp envpaths_NCAR.sh envpaths.sh
    MODEL2OBS_ENV_NAME="${ENV_PREFIX}""model2obs"
    DART_ROOT_PATH=${DART_ROOT_PATH} CONDA_ENV_NAME=${MODEL2OBS_ENV_NAME} ./install_NCAR.sh --tutorial
    cd "$INSTALL_DIR"
    echo "model2obs environment installed."
    cp "$MODEL2OBS_PATH"/tutorials/tutorial_MOM6-CL-comparison-Hawaii.ipynb "$NBS_PATH"
    cp "$MODEL2OBS_PATH"/tutorials/config_tutorial_hawaii.yaml "$NBS_PATH"
    cp "$MODEL2OBS_PATH"/tutorials/tutorial_MOM6-CL-comparison-NWA-parallel.ipynb "$NBS_PATH"
    cp "$MODEL2OBS_PATH"/tutorials/config_tutorial_NWA_parallel.yaml "$NBS_PATH"
fi

# CUPiD
if [[ "$INSTALL_CUPID" -eq 1 ]]; then
    echo "Installing CUPiD environments..."

    cd "$CUPID_PATH"
    CUPID_SHA=$(git rev-parse HEAD)
    cd "$INSTALL_DIR"

    ENV_NAME=$(awk -F ": " '/^name:/ {print $2}' "$CUPID_PATH"/environments/cupid-infrastructure.yml)
    CUPID_ENV1_NAME="${ENV_PREFIX}${ENV_NAME}"
    mamba env create -f "$CUPID_PATH"/environments/cupid-infrastructure.yml --name ${CUPID_ENV1_NAME} --yes
    add_env_vars_to_conda "$CUPID_ENV1_NAME"

    ENV_NAME=$(awk -F ": " '/^name:/ {print $2}' "$CUPID_PATH"/environments/cupid-analysis.yml)
    CUPID_ENV2_NAME="${ENV_PREFIX}${ENV_NAME}"
    mamba env create -f "$CUPID_PATH"/environments/cupid-analysis.yml --name ${CUPID_ENV2_NAME} --yes
    add_env_vars_to_conda "$CUPID_ENV2_NAME"

    echo "CUPiD environments installed."
fi

# CESM
if [[ "$INSTALL_CESM" -eq 1 ]]; then
    echo "Installing CESM..."
    cd "$CESM_PATH"
    CESM_SHA=$(git rev-parse HEAD)
    ./bin/git-fleximod update --path "$CESM_PATH"
    cd "$INSTALL_DIR"
    echo "CESM installed."
fi

# CESM_DA
if [[ "$INSTALL_CESM_DA" -eq 1 ]]; then
    echo "Installing CESM_DA..."
    cd "$CESM_DA_PATH"
    CESM_DA_SHA=$(git rev-parse HEAD)
    ./bin/git-fleximod update --path "$CESM_DA_PATH"
    cd "$INSTALL_DIR"

    # The CESM_DA conda env only exists to run the DART notebooks, so only
    # build it when --notebooks is requested. It's built from CrocoDash's own
    # environment.yml (its pip -e paths resolve relative to that file's
    # directory, so the generated copy has to live alongside the real
    # CrocoDash/gallery/rm6 checkouts) plus the DART notebook packages that
    # aren't part of CrocoDash itself.
    if [[ "$INSTALL_NOTEBOOKS" -eq 1 ]]; then
        echo "Building CESM_DA conda environment..."
        CESM_DA_ENV_FILE="$CROCODASH_PATH/cesm_da_environment.yml"
        awk '
            /^  - pip:/ { print; print "    - pydartdiags"; print "    - dartobsgen"; next }
            { print }
        ' "$CROCODASH_PATH/environment.yml" > "$CESM_DA_ENV_FILE"
        CESM_DA_ENV_NAME="${ENV_PREFIX}CESM_DA"
        mamba env create -f "$CESM_DA_ENV_FILE" --name ${CESM_DA_ENV_NAME} --yes
        add_env_vars_to_conda "$CESM_DA_ENV_NAME"
        rm -f "$CESM_DA_ENV_FILE"
    fi

    echo "CESM_DA installed."
fi

cat <<'EOF'
------------------------------------------------------------------------------------

   ,-----.,------.  ,-----. ,-----. ,-----. ,------.  ,--.,--.   ,------.
  '  .--./|  .--. ''  .-.  ''  .--./'  .-.  '|  .-.  \ |  ||  |   |  .---'
  |  |    |  '--'.'|  | |  ||  |    |  | |  ||  |  \  :|  ||  |   |  `--,
  '  '--'\|  |\  \ '  '-'  ''  '--'\'  '-'  '|  '--'  /|  ||  '--.|  `---.
   `-----'`--' '--' `-----'  `-----' `-----' `-------' `--'`-----'`------'                                                                                                                                                                    
EOF
cat <<'EOF'
           ___     ___
          /   \   /   \
         |   O | |   O |
       ,-'\___/___\___/___'-._                                   ___
    ,-'                       ______________________            /  /
  ,'                                  ,--.   ,--.   '.         /  /
  |                    .    .         (##)   (##)    |        /  /
  '-.                                               ,'       /  /  
     _____________________________________________-'        /__/  
                 \/    \________,--------------------------.  
                                |__________________________| 

EOF
cat <<'EOF'
  ,--.   ,--. ,-----. ,------. ,--. ,--. ,---.  ,------.   ,---.   ,-----.,------.
  |  |   |  |'  .-.  '|  .--. '|  .'   /'   .-' |  .--. ' /  O  \ '  .--./|  .---'
  |  |.'.|  ||  | |  ||  '--'.'|  .   ' `.  `-. |  '--' ||  .-.  ||  |    |  `--,
  |   ,'.   |'  '-'  '|  |\  \ |  |\   \.-'    ||  | --' |  | |  |'  '--'\|  `---.
  '--'   '--' `-----' `--' '--'`--' '--'`-----' `--'     `--' `--' `-----'`------'

------------------------------------------------------------------------------------
EOF

echo ""
echo "Install complete."
echo "Components, environments and paths installed:"
echo ""

DATETIME=$(date "+%Y-%m-%d_%H-%M-%S")
INSTALL_RECORD="installed_${DATETIME}.txt"
touch $INSTALL_RECORD

if [[ "$INSTALL_CROCODASH" -eq 1 ]]; then
    cat <<EOF | tee -a $INSTALL_RECORD
CrocoDash:
    path:   $CROCODASH_PATH
    commit: $CROCODASH_SHA
    conda environment: $CROCODASH_ENV_NAME

EOF
fi
if [[ "$INSTALL_NOTEBOOKS" -eq 1 && "${#RENDERED_NOTEBOOKS[@]}" -gt 0 ]]; then
    {
        echo "CrocoGallery notebooks:"
        echo "    workspace: $NBS_PATH"
        echo "    case directory: $CASES_PATH"
        echo "    input directory: $INPUT_PATH"
        for NB in "${RENDERED_NOTEBOOKS[@]}"; do
            echo "    - $NB"
        done
    } | tee -a $INSTALL_RECORD
    echo ""
fi
if [[ "$INSTALL_CESM" -eq 1 ]]; then
    cat <<EOF | tee -a $INSTALL_RECORD
CESM:
    path:   $CESM_PATH
    commit: $CESM_SHA

EOF
fi
if [[ "$INSTALL_CESM_DA" -eq 1 ]]; then
    {
        echo "CESM_DA:"
        echo "    path:   $CESM_DA_PATH"
        echo "    commit: $CESM_DA_SHA"
        if [[ -n "${CESM_DA_ENV_NAME:-}" ]]; then
            echo "    conda environment: $CESM_DA_ENV_NAME"
        fi
        echo ""
    } | tee -a $INSTALL_RECORD
fi
if [[ "$INSTALL_MODEL2OBS" -eq 1 ]]; then
    cat <<EOF | tee -a $INSTALL_RECORD
MODEL2OBS:
    path:   $MODEL2OBS_PATH
    commit: $MODEL2OBS_SHA
    conda environment: $MODEL2OBS_ENV_NAME
    DART root path: $DART_ROOT_PATH

EOF
fi
if [[ "$INSTALL_CUPID" -eq 1 ]]; then
    cat <<EOF | tee -a $INSTALL_RECORD
CUPiD:
    path:   $CUPID_PATH
    commit: $CUPID_SHA
    conda environments: $CUPID_ENV1_NAME
                        $CUPID_ENV2_NAME

EOF
fi

echo "To activate an environment:"
echo "module load conda"
echo "conda activate <environment-name>"
echo "(example: conda activate CrocoDash)"
echo ""
echo "If you specified a prefix for environment names:"
echo "conda activate <prefix>-CrocoDash"
