#!/bin/bash


## Helper Functions
usage () {
    echo "Usage: $(basename $0) [-h,--help] [-v,--variables varfile] workflow-path"
    echo "  -h,--help       Display this help message"
    echo "  -v,--variables  Variables file"
    echo "  workflow-path   Workflow path"
}

#### Parse Command-Line Arguments ####

getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
    echo "`getopt --test` failed in this environment."
    exit 1
fi

OPTIONS=v:h
LONGOPTIONS=variables:,help

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
        -v|--variables)
            VAR_FILE=$2
            shift 2
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

# workflow name
GF_NAME=$(basename ${GF_DIR})


echo 
echo "##### Compiling App Templates"

# find each '.j2' file and compile
APP_LIST=$(ls ${GF_DIR}/workflow/apps)
for app in ${APP_LIST[@]}; do
    JSON_LIST=$(ls ${GF_DIR}/workflow/apps/${app} | grep '.j2')
    VERSION_FILE=${GF_DIR}/workflow/apps/${app}/version.yaml
    for json in ${JSON_LIST[@]}; do
        JSON_PATH=${GF_DIR}/workflow/apps/${app}/${json}
        CMD="yasha -v ${VAR_FILE} -v ${VERSION_FILE} ${JSON_PATH}"
        echo "$CMD"
        $CMD
    done
done

# get agave params
AGAVE_APPS_PREFIX=$(cat ${VAR_FILE} | shyaml get-value agave.appsPrefix)
AGAVE_EXECUTION_SYSTEM=$(cat ${VAR_FILE} | shyaml get-value agave.executionSystem)
AGAVE_DEPLOYMENT_SYSTEM=$(cat ${VAR_FILE} | shyaml get-value agave.deploymentSystem)
AGAVE_APPS_DIR=$(cat ${VAR_FILE} | shyaml get-value agave.appsDir)
AGAVE_TEST_DATA_DIR=$(cat ${VAR_FILE} | shyaml get-value agave.testDataDir)

if [ -z "${AGAVE_APPS_PREFIX}" ]; then
    echo "Invalid agave params, missing appsPrefix"
    exit 1
fi
if [ -z "${AGAVE_APPS_DIR}" ]; then
    echo "Invalid agave params, missing appsDir"
    exit 1
fi

echo 
echo "##### Uploading Apps"

# create apps directory
CMD="files-mkdir -S ${AGAVE_DEPLOYMENT_SYSTEM} -N $(basename ${AGAVE_APPS_DIR}) $(dirname ${AGAVE_APPS_DIR})"
echo "$CMD"
$CMD

# upload apps
for app in ${APP_LIST[@]}; do
    CMD="files-delete -S ${AGAVE_DEPLOYMENT_SYSTEM} ${AGAVE_APPS_DIR}/${app}"
    echo "$CMD"
    $CMD
    CMD="files-upload -S ${AGAVE_DEPLOYMENT_SYSTEM} -F ${GF_DIR}/workflow/apps/${app} ${AGAVE_APPS_DIR}/"
    echo "$CMD"
    $CMD
done


echo 
echo "##### Uploading Test Data"

# create test data directory
CMD="files-mkdir -S ${AGAVE_DEPLOYMENT_SYSTEM} -N $(basename ${AGAVE_TEST_DATA_DIR}) $(dirname ${AGAVE_TEST_DATA_DIR})"
echo "$CMD"
$CMD

# upload test data
CMD="files-upload -S ${AGAVE_DEPLOYMENT_SYSTEM} -F ${GF_DIR}/data -N ${GF_NAME} ${AGAVE_TEST_DATA_DIR}/"
echo "$CMD"
$CMD


echo
echo "##### Registering/Updating Apps"

for app in ${APP_LIST[@]}; do
    # update existing, or add if not already there
    CMD="apps-addupdate -F ${GF_DIR}/workflow/apps/${app}/agave-app-def.json"
    echo "$CMD"
    $CMD
done





