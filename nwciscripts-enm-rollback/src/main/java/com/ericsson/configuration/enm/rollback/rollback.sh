#!/bin/bash
##########################################
# Should be Commented out for official release
#source ~/env.ini
###########################################

_BASEDIR=`dirname "$0"`
download_location="$( mktemp -d )"
. ${_BASEDIR}/artifact_json_template.json

source ${_BASEDIR}/common.sh

function execute_main_deployment() {
    # Function to kick off the deployment with the appropriate commands
    artifact_json=$1
    os_cert=$2
    os_cert_slave_location=$3
    username=$( echo ${os_username} | base64 --decode )
    password=$( echo ${os_password} | base64 --decode )
    dockerExtraDetails=""
    enmExtraDetails=""
    if [ ! -z "${cee_host}" ]; then
        dockerExtraDetails="--add-host ${cee_host}:${cee_ip} ${dockerExtraDetails}"
    fi
    if [ ! -z "${atlas_host}" ]; then
        dockerExtraDetails="--add-host ${atlas_host}:${atlas_ip} ${dockerExtraDetails}"
    fi
    if [ ! -z "${os_cert}" ]; then
        enmExtraDetails="--os-cacert ${os_cert} ${enmExtraDetails}"
    fi

    if [ ! -z ${workflow_max_check_attempt} ]; then
        enmExtraDetails="--workflow-max-check-attempts ${workflow_max_check_attempt} ${enmExtraDetails}"
    fi

    if [ ! -z ${image_name_postfix} ]; then
        enmExtraDetails="--image-name-postfix ${image_name_postfix} ${enmExtraDetails}"
    fi

    if [ ! -z ${lcm_sed_file_location} ]; then
        enmExtraDetails="--vnf-lcm-sed-file-url ${lcm_sed_file_location} ${enmExtraDetails}"
    fi

    # Calculate the snapshot tag to rollback to according to the available volumes
    export OS_AUTH_URL=${os_auth_url}
    export OS_USERNAME=${username}
    export OS_PASSWORD="${password}"
    export OS_PROJECT_NAME=${os_project_name}
    export OS_IDENTITY_API_VERSION=${os_identity_api_version}
    if [[ ${os_cert_slave_location} != "" ]];then
        export OS_CACERT=${os_cert_slave_location}
    fi

    snapshot_tag=$( openstack volume show `openstack volume list | grep available | grep "${snapshot_tag}" | awk '{print $2}' | tail -1` -f json | grep enm_snapshot_tag | sed -e 's/.*enm_snapshot_tag=//' -e "s/', .*//" -e "s/'//" )

    enmExtraDetails="nwci enm rollback deployment ${enmExtraDetails}"
    echo "docker run --rm ${dockerExtraDetails} -v ${download_location}:${download_location_mount} -v /tmp:/tmp armdocker.rnd.ericsson.se/proj_nwci/enmdeployer:${openstackdeploy_gav_version} ${enmExtraDetails} --os-username ${username} --os-password "${password}" --os-auth-url ${os_auth_url} --os-project-name ${os_project_name} --deployment-name ${deployment_name} --sed-file-url ${enm_sed_file_location} --artifact-json-file ${artifact_json} --snapshot-tag ${snapshot_tag} --debug"

    docker run --rm ${dockerExtraDetails} -v ${download_location}:${download_location_mount} -v /tmp:/tmp armdocker.rnd.ericsson.se/proj_nwci/enmdeployer:${openstackdeploy_gav_version} ${enmExtraDetails} --os-username ${username} --os-password "${password}" --os-auth-url ${os_auth_url} --os-project-name ${os_project_name} --deployment-name ${deployment_name} --sed-file-url ${enm_sed_file_location} --artifact-json-file ${artifact_json} --snapshot-tag ${snapshot_tag} --debug
    command_code=$( echo $? )
    check_exit_code ${command_code}
}


# Main Calls
echo "Populate json artifact file with media (${artifact_json_location})"
populate_json_artifact_string "media_details_content" "${artifact_json_template}" MEDIA_DETAILS[@]
populate_json_artifact_string "cloud_templates_details_content" "${artifact_json_template}" CLOUD_TEMPLATE_DETAILS[@]
populate_json_artifact_string "deployment_workflows_details_content" "${artifact_json_template}" DEPLOYMENT_WORKFLOW_DETAILS[@]
populate_json_artifact_string "cloud_mgmt_workflows_details_content" "${artifact_json_template}" CLOUD_MGMT_WORKFLOWS_DETAILS[@]
populate_json_artifact_string "cloud_performance_workflows_details_content" "${artifact_json_template}" CLOUD_PERFORMANCE_WORKFLOWS_DETAILS[@]
populate_json_artifact_string "vnf_cloud_templates_details_content" "${artifact_json_template}" VNF_CLOUD_TEMPLATE_DETAILS[@]
populate_json_artifact_string "edp_autodeploy_details_content" "${artifact_json_template}" EDP_AUTODEPLOY_DETAILS[@]
echo "Populate VNFLCM Details Content..."
populate_json_artifact_string "vnflcm_details_content" "${artifact_json_template}" VNFLCM_DETAILS[@]
generate_artifact_json_file ${artifact_json_location} "${artifact_json_template}"
if [ ! -z ${env_configuration_file_artifactLocation_parameters_source} ]; then
    echo "Download Configuration File"
    download_configuration_file ${env_configuration_file_artifactLocation_parameters_source} ${configuration_file_location}
    . ${configuration_file_location}
fi
if [ ! -z "${os_cacert}" ]; then
    echo "Download os certification"
    download_os_cert_file ${os_cacert} ${os_cert_location}
fi
echo "Execute Main deployment"
execute_main_deployment ${artifact_json_location_mount} ${os_cert_location_mount} ${os_cert_location}
echo "Execute check on ENM Login GUI (Maximum Wait time 70 mins)"
execute_check_on_enm_login_prompt ${enm_sed_file_location} ${enm_sed_location} ${enm_deployment_type}
echo "EXECUTION COMPLETED......"
clean_up ${download_location}
