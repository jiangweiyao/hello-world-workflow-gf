#!/bin/bash


## Helper Functions
usage () {
    echo "Usage: $(basename $0) [-h,--help] [-v,--variables varfile] workflow-path"
    echo "  -h,--help       Display this help message"
    echo "  -t,--type       Workflow type"
    echo "  workflow-path   Workflow path"
}

#### Parse Command-Line Arguments ####

getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
    echo "`getopt --test` failed in this environment."
    exit 1
fi

OPTIONS=t:h
LONGOPTIONS=type:,help

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

echo 
echo "##### Generating Type-Specific Workflow Definition"

wf_def=${GF_DIR}/workflow/workflow-${TYPE}.yaml
cat ${GF_DIR}/workflow/workflow.yaml > ${wf_def}
echo >> ${wf_def}

APP_LIST=$(ls ${GF_DIR}/workflow/apps)
for app in ${APP_LIST[@]}; do
    cat ${GF_DIR}/workflow/apps/${app}/app-${TYPE}.yaml >> ${wf_def}
    echo >> ${wf_def}
done

echo "New definition: ${wf_def}"

