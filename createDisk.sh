#!/usr/bin/env bash

set -e

# set bash-commons
commons="ops-gcp-kubernetes/ops-bash-commons"

# script dependencies
source ${commons}/functions/checks.sh
source ${commons}/gcloud/functions/debug.sh

# gcloud verbosity
debug=false
gcloudDebug

# requirements
checkProgs gcloud

# gcloud work
${gcloud} compute disks create --size=50GB godata
