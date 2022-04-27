#! /usr/bin/env bash
set -e
set -o pipefail
set -x

# Usage examples:
#
# INPUT_TESTPLAN=go-v0.19 INPUT_VERSION_A=v0.19.0 INPUT_VERSION_B=master ./ping-interop/build.sh && ./ping-interop/run.sh
# INPUT_TESTPLAN_A=go-v0.19 INPUT_VERSION_A=v0.19.0 INPUT_TESTPLAN_B=rust-v0.44 INPUT_VERSION_B=0.44.0 ./ping-interop/build.sh && ./ping-interop/run.sh

# Note: this script expects to live in the test plan directory (ping-interop).
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

function build_go() {
    local INPUT_VERSION=$1;
    local INPUT_TESTPLAN=$2;
    # TODO: according to the doc this should work: `--dep github.com/libp2p/go-libp2p=${INPUT_VERSION_A}`
    #       but it doesn't, we need to pass the long form.
    testground build single --wait \
        --builder docker:go \
        --dep github.com/libp2p/go-libp2p=github.com/libp2p/go-libp2p@${INPUT_VERSION} \
        --plan libp2p/ping-interop/${INPUT_TESTPLAN} 2>&1 1>build.out
    local RESULT=$(awk -F\" '/generated build artifact/ {print $8}' <build.out)

    echo "${RESULT}"
}

function build_rust() {
    local INPUT_VERSION=$1;
    local INPUT_TESTPLAN=$2;

    pushd "${SCRIPT_DIR}/${INPUT_TESTPLAN}/" > /dev/null
    # TODO: is there a more idiomatic way to apply the replace?
    # TODO: there is a difference between a `branch = 'master'` and a `rev = 'f46fecd4d76'`, make this user friendly.
    cat <<EOF >> ./Cargo.toml


[patch.crates-io]
libp2p = { git = 'https://github.com/libp2p/rust-libp2p', rev = '${INPUT_VERSION}' }
EOF
    popd > /dev/null

    testground build single --wait \
        --builder docker:generic \
        --plan libp2p/ping-interop/${INPUT_TESTPLAN} 2>&1 1>build.out
    local RESULT=$(awk -F\" '/generated build artifact/ {print $8}' <build.out)

    echo "${RESULT}"
}



# Build every plan and store the generated artifact.
# similar to https://github.com/testground/testground/blob/master/integration_tests/01_k8s_kind_placebo_ok.sh

INPUT_TESTPLAN_A=${INPUT_TESTPLAN_A:-$INPUT_TESTPLAN}
INPUT_TESTPLAN_B=${INPUT_TESTPLAN_B:-$INPUT_TESTPLAN_A}

INPUT_VERSION_A=${INPUT_VERSION_A:-$INPUT_VERSION}
INPUT_VERSION_B=${INPUT_VERSION_B:-$INPUT_VERSION_A}

echo "testing ${SCRIPT_DIR}"
echo "instance a: ${INPUT_TESTPLAN_A} ${INPUT_VERSION_A}"
echo "instance b: ${INPUT_TESTPLAN_B} ${INPUT_VERSION_B}"

mkdir -p ${HOME}/testground/plans/libp2p # TODO: find if we can remove this, maybe create a ticket.
testground plan import --from ${SCRIPT_DIR} --name "libp2p/ping-interop"


case "${INPUT_TESTPLAN_A}" in
    *"rust"*)
        export ARTIFACT_VERSION_A="$(build_rust "${INPUT_VERSION_A}" "${INPUT_TESTPLAN_A}")"
        ;;
    *"go"*)
        export ARTIFACT_VERSION_A="$(build_go "${INPUT_VERSION_A}" "${INPUT_TESTPLAN_A}")"
        ;;
esac

case "${INPUT_TESTPLAN_B}" in
    *"rust"*)
        export ARTIFACT_VERSION_B="$(build_rust "${INPUT_VERSION_B}" "${INPUT_TESTPLAN_B}")"
        ;;
    *"go"*)
        export ARTIFACT_VERSION_B="$(build_go "${INPUT_VERSION_B}" "${INPUT_TESTPLAN_B}")"
        ;;
esac

if [ -z "${ARTIFACT_VERSION_A}" ]; then echo "Artifact A build failed"; exit 10; fi;
if [ -z "${ARTIFACT_VERSION_B}" ]; then echo "Artifact B build failed"; exit 11; fi;

echo "building the composition file with:"
echo "ARTIFACT_VERSION_A=${ARTIFACT_VERSION_A}"
echo "ARTIFACT_VERSION_B=${ARTIFACT_VERSION_B}"

envsubst < "${SCRIPT_DIR}/_compositions/2-versions.template.toml" > "${SCRIPT_DIR}/_compositions/2-versions.toml"
