#!/usr/bin/env bash

if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    echo -e "Script to deploy OSD cluster \n"
    echo "Usage:"
    echo -e "\t ./deploy-with-ocm.sh \n"
    echo "Mandatory arguments:"
    echo -e "\t First argument should be OCM Token"
    echo -e "\t Second argument should be your Kerberos ID \n"
    echo "Optional environment variables for customized cluster:"
    echo -e "\t CLUSTER_NAME: To specify name of the cluster"
    echo -e "\t\t default: new"
    echo -e "\t\t NOTE: Cluster name will be prefixed by Kerberos ID"
    echo -e "\t NO_OF_NODES: Number of nodes for the cluster"
    echo -e "\t\t NO_OF_NODES can be between 4 to 16"
    echo -e "\t\t default: 6"
    echo -e "\t MACHINE_TYPE: To specify machine type of the cluster"
    echo -e "\t\t MACHINE_TYPE can be m5.xlarge or m5.2xlarge or m5.4xlarge"
    echo -e "\t\t default: m5.2xlarge \n"
    echo "Cluster quota information:"
    echo "$(ocm account quota)"
    exit
fi


function exit_on_err() {
    "$@"
    EXIT_CODE=$?
    if [ ${EXIT_CODE} -ne 0 ]; then
        >&2 echo "\"${@}\" command failed with exit code ${EXIT_CODE}."
        exit ${EXIT_CODE}
    fi
}

exit_on_err ocm whoami  > /dev/null 2>&1
if [ $? -eq 1 ]; then
    OCM_TOKEN=${OCM_TOKEN:-${1}}
    if [[ -z ${OCM_TOKEN} ]]; then
        echo "Error: the OCM_TOKEN environment variable is not specified"
        exit 1
    fi
    exit_on_err ocm login --token=$OCM_TOKEN --url=staging
else
    echo "Info: Using Username: $(ocm whoami | jq -r .username) for deploying cluster"
fi

KERBEROS_ID=${KERBEROS_ID:-${2}}
if [[ -z ${KERBEROS_ID} ]]; then
        echo "Error: the KERBEROS_ID environment variable is not specified"
        exit 1
fi

CLUSTER_NAME=${CLUSTER_NAME:-new}
NO_OF_NODES=${NO_OF_NODES:-6}
MACHINE_TYPE=${MACHINE_TYPE:-m5.2xlarge}

CREATE_CLUSTER='{
    "name": "'"${KERBEROS_ID}-${CLUSTER_NAME}"'",
    "region": {
        "id": "us-east-1"
    },
    "nodes": {
        "compute_machine_type": {
            "id": "'"${MACHINE_TYPE}"'"
        },
        "compute": '${NO_OF_NODES}'
    },
    "managed": true,
    "cloud_provider": {
        "id": "aws"
    },
    "multi_az": false,
    "node_drain_grace_period": {
        "value": 60,
        "unit": "minutes"
    },
    "billing_model": "standard",
    "product": {
        "id": "osd"
    },
    "load_balancer_quota": 0,
    "storage_quota": {
        "unit": "B",
        "value": 107374182400
    }
}'

echo $CREATE_CLUSTER > create_cluster1.json

exit_on_err ocm post /api/clusters_mgmt/v1/clusters < create_cluster1.json
rm create_cluster1.json

CLUSTER_STATE=$(ocm get /api/clusters_mgmt/v1/clusters --parameter search="name like '${KERBEROS_ID}-${CLUSTER_NAME}'" | jq -r .items[].status.state)

until [[ "$CLUSTER_STATE" == "ready" || "$CLUSTER_NAME" == "uninstalling" ]]
do
    echo "Info: Waiting for cluster to be in ready state"
    sleep 60
    CLUSTER_STATE=$(ocm get /api/clusters_mgmt/v1/clusters --parameter search="name like '${KERBEROS_ID}-${CLUSTER_NAME}'" | jq -r .items[].status.state)
done

if [[ "$CLUSTER_STATE" == "uninstalling" ]]; then
    echo "Cluster was uninstalled manually"
    exit 1
fi

echo "Cluster has successfully deployed"
