#!/usr/bin/env bash

# set bash-commons
commons=ops-gcp-kubernetes/ops-bash-commons

# script dependencies
source ${commons}/functions/colors.sh
source ${commons}/functions/testing.sh
source ${commons}/gcloud/functions/setConfig.sh
source ${commons}/gcloud/functions/debug.sh

# test script setup
testName=gocd-test
project=ops-iac-sb
zone=us-east1-b
clusterName=${testName}-cluster
domainName=${testName}.ois.lzy.sh
cleanup=true

# depends
cmd="setConfig -p ${project} -z ${zone}"
echoBlue "Running dependency: ${cmd}"
${cmd} 2>&1

cmd="ops-gcp-kubernetes/gcloud/createK8sCluster.sh -c ${clusterName}"
echoBlue "Running dependency: ${cmd}"
${cmd} 2>&1

# test createDisk.sh
cmd="./createDisk.sh"
echoCyan "Running test on: ${cmd}"
${cmd} 2>&1
results

# test apply.sh
cmd="ops-gcp-kubernetes/kubectl/apply.sh -d ${domainName}"
echoCyan "Running test on: ${cmd}"
${cmd} 2>&1
results

# cleanup
if [ "${cleanup}" = true ]; then
	# gcloud verbosity
	debug=false
	gcloudDebug

        cmd="kubectl delete ns gocd"
        echoBlue "Running cleanup command: ${cmd}"
        ${cmd} 2>&1

	# wait for ingress to cleanup
        sleep 180
        
        cmd="${gcloud} container clusters delete ${clusterName}"
        echoBlue "Running cleanup command: ${cmd}"
        ${cmd} 2>&1
        
        cmd="${gcloud} compute disks delete godata"
        echoBlue "Running cleanup command: ${cmd}"
        ${cmd} 2>&1
fi

# fail overall script if any of the individual results fail
if [ "${fail}" = true ]; then
        exit 1
fi
