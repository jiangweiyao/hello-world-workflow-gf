#!/bin/bash

## Helper Functions
usage () {
    echo "Usage: $(basename $0) [-h,--help] -t type [-c,--clean] workflow-path"
    echo "  -h,--help       Display this help message"
    echo "  -c,--clean      If type=build-package, providing the clean option will delete any old build directories before re-building"
    echo "  -t,--type       Package type (build-package, package, singularity)"
    echo "  workflow-path   Workflow path"
}

#### Parse Command-Line Arguments ####

getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
    echo "`getopt --test` failed in this environment."
    exit 1
fi

OPTIONS=t:ch
LONGOPTIONS=type:,clean,help

# -temporarily store output to be able to check for errors
# -e.g. use "--options" parameter by name to activate quoting/enhanced mode
# -pass arguments only via   -- "$@"   to separate them correctly
PARSED=$(\
    getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@"\
)
if [[ $? -ne 0 ]]; then
    # e.g. $? == 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi

# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -t|--type)
            TYPE=$2
            shift 2
            ;;
        -c|--clean)
            CLEAN=yes
            shift 1
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Invalid option"
            usage
            exit 3
            ;;
    esac
done

# handle non-option arguments
if [[ $# -ne 1 ]]; then
    echo "$0: Please specify a single path to the GeneFlow workflow."
    usage
    exit 4
fi

GF_PATH=$1

# get absolute path
GF_DIR=$(readlink -f ${GF_PATH})

# remove old apps directory if it exists, and recreate
rm -rf "${GF_DIR}/workflow/apps"
mkdir -p "${GF_DIR}/workflow/apps"

# download app packages from repos
APP_LIST=$(cat ${GF_DIR}/workflow/apps-repo.yaml | shyaml get-values apps)

for app in ${APP_LIST[@]}; do
    # clone repo
    repo_folder=$(echo $app | awk -F/ '{print $2}')
    repo_path="${GF_DIR}/workflow/apps/${repo_folder}"
    mkdir -p "${repo_path}"
    repo_cmd="git clone ${app} ${repo_path}"
    echo "${repo_cmd}"
    ${repo_cmd}

    # move repo to versioned folder
    app_version=$(cat ${repo_path}/version.yaml | shyaml get-value version)
    repo_mv="mv ${repo_path} ${repo_path}-${app_version}"
    echo "${repo_mv}"
    ${repo_mv}
done

# compile app packages
if [ ${TYPE} = "build-package" ]; then
    if [ "${CLEAN}" = "yes" ]; then
        make -C $(dirname $(readlink -f $0))/apps-build-package $(basename ${GF_DIR})-clean
    fi
    make -C $(dirname $(readlink -f $0))/apps-build-package $(basename ${GF_DIR})
fi

# install assets into app folders

# use this for more robust processing of assets file:
# for val in $(cat ./assets.yaml | yq -r 'select(."build-package" != null) | ."build-package"[]'); do echo $val; done

APP_LIST=$(ls ${GF_DIR}/workflow/apps)
for app in ${APP_LIST[@]}; do
    # assets.yaml file exists
    if [ -f ${GF_DIR}/workflow/apps/${app}/assets.yaml ]; then
        case "${TYPE}" in
            build-package|package)
                PKG_PATHS=$(cat ${GF_DIR}/workflow/apps/${app}/assets.yaml | shyaml get-values ${TYPE})
                for pkg in ${PKG_PATHS[@]}; do
                    src=$(echo $pkg | awk -F: '{print $1}')
                    dst=$(echo $pkg | awk -F: '{print $2}')
                    if [ -z "${src}" ]; then
                        echo "Invalid assets.yaml file"
                        exit 1
                    fi
                    if [ -z "${dst}" ]; then
                        echo "Invalid assets.yaml file"
                        exit 1
                    fi
                    rm -rf ${GF_DIR}/workflow/apps/${app}/${dst}
                    mkdir -p ${GF_DIR}/workflow/apps/${app}/${dst}
                    CMD="tar -czf ${GF_DIR}/workflow/apps/${app}/${dst}/${dst}.tar.gz --directory=${src} ."
                    echo "$CMD"
                    $CMD
                done
                ;;
            singularity)
                # nothing yet
                ;;
            *)
        esac
    fi
done

