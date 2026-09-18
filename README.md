# CROCODILEworkspace

A template repository for regional ocean modeling workflows using tools developed in the NSF-funded [CROCODILE](https://github.com/CROCODILE-CESM?view_as=public) project.

## Usage

This repository is a GitHub template. Click **Use this template** to create your own repository (e.g., `MyRegionalCase`), then run the installation script to set up the packages, and you can commit and track your work. CROCODILEworkspace itself remains lightweight by not committing the installed packages (they are cloned and gitignored); each run records the exact commit of every installed package in `install.d/installed_<timestamp>.txt`.

## Installation

> **Note:** for the time being, CROCODILEworkspace installation works out of the box on NCAR infrastructure (Derecho, Casper) only. We expect minimal adjustments to be required to port it to other machines and we are happy to assist you.

Requires `conda` >= 23.10 and `mamba`. On Derecho and Casper the installer runs `module load conda/latest` for you.

From the repository root, run:

```bash
./install.sh [flags]
```

### Available Flags

#### Package Selection
- `--crocodash`: Install CrocoDash model components
- `--model2obs`: Install model2obs diagnostics tools
- `--cupid`: Install CUPiD diagnostics framework
- `--cesm`: Install CESM model
- `--cesm_da`: Install CESM_DA, a DART-enabled version of CESM. Combined with `--notebooks`, also builds a `CESM_DA` conda environment (from CrocoDash's `environment.yml` plus `pydartdiags` and `dartobsgen`, which implies `--crocodash`) for the DART notebooks in CrocoGallery
- `--dart`: Root path of an existing DART installation, used by model2obs (see [DART](#dart) below)
- `--all`: Install all packages (includes `--notebooks`)
- `--workshop`: Install all and only the packages used during the CROCODILE workshop (includes `--notebooks`)
- `--notebooks`: Render the CrocoGallery notebooks listed in `install.d/notebooks.txt` into `workspace/` (implies `--crocodash`)

#### Installation Options
- `-d, --default`: Use default paths for all packages (default behaviour, non-interactive)
- `-p, --paths`: Prompt for each package path (interactive; mutually exclusive with `-d`)
- `-f, --force`: Remove and reinstall selected packages if they already exist
- `-s, --ssh-github`: Use SSH URLs instead of HTTPS for GitHub clones (requires SSH key setup)
- `-e, --envname`: Specify prefix for conda environment names (default: no prefix, e.g. the CrocoDash environment is named `CrocoDash`; with `--envname bask` it becomes `bask-CrocoDash`)
- `-h, --help`: Display usage information and exit

You can combine multiple flags. Default paths are used unless you pass `-p`/`--paths`, which prompts for each package path and requires an interactive terminal.

If a package already exists at the target path, the script stops with an error before installing anything. Use the `-f` or `--force` flag to remove and reinstall existing packages.

### DART

DART is **not** installed by CROCODILEworkspace. It is an external dependency that model2obs is pointed at: model2obs runs DART's `perfect_model_obs` executable and imports DART's CrocoLake observation converter. DART has to be compiled separately; on NCAR infrastructure pre-compiled builds are available and are automatically set up with the `--workshop` flag.

The installer resolves the DART root in this order:

1. `--dart /path/to/DART`
2. the interactive prompt shown by `-p`/`--paths`
3. `DART_ROOT_PATH` exported in your environment before running `./install.sh`
4. the pre-compiled default in `install.d/generate_envpaths.sh`

### Examples

```bash
# Install packages for CROCODILE workshop with default paths
./install.sh --workshop

# Install CrocoDash and model2obs with default paths
./install.sh --crocodash --model2obs

# Install all packages with default paths
./install.sh --all

# Install all packages with default paths and custom environment prefix
./install.sh --all --envname myBask

# Reinstall CESM (force reinstall if already exists)
./install.sh --cesm -f

# Install using SSH URLs (requires GitHub SSH key)
./install.sh --crocodash --cupid -s

# Choose each package path interactively
./install.sh --all --paths

# Install model2obs against your own DART build
./install.sh --model2obs --dart /glade/work/me/DART
```

## Subpackages

- **CrocoDash**: CESM-MOM6 regional cases set up management
- **model2obs**: Diagnostics and analysis tools for MOM6 (and soon ROMS) model output
- **CUPiD**: NCAR's unified framework for running analysis and diagnostics on climate model output
- **CESM**: Community Earth System Model for climate simulations
- **DART**: path to DART (Data Assimilation Research Testbed), used by model2obs not installed here
- **CESM_DA**: DART-enabled Community Earth System Model

## Workspace

The installer creates a `workspace/` folder at the repository root. Some packages copy their tutorial notebooks and configurations there.

With `--notebooks` (included in `--all` and `--workshop`), the installer also renders the CrocoGallery notebooks listed in `install.d/notebooks.txt` into `workspace/`. Edit that file to change which notebooks are rendered; list the available IDs with `crocogallery template --list-notebooks`.

Rendering fills in the paths the installer knows about: the CESM checkout, plus a case directory and an input directory (`croc_cases/` and `croc_input/`, placed under `/glade/derecho/scratch/$USER` when installing on GLADE and under the CROCODILEworkspace root otherwise). Export `CASES_PATH` or `INPUT_PATH` before running the installer to put them somewhere else. Shared dataset paths (GEBCO, TPXO, ...) are filled in only when installing on GLADE; elsewhere the notebooks keep their `<KEY>` placeholders for you to edit by hand.
