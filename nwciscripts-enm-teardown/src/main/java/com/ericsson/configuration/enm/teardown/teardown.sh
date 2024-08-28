#!/bin/bash
##########################################
#source ~/env.ini
###########################################

_BASEDIR=`dirname "$0"`
download_location="$( mktemp -d )"

source ${_BASEDIR}/common.sh

function execute_main_enm_deployment_script() {
    # Function to delete the stacks in the deployment
    os_cert=$1
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

    # os_cert is only used for CEE
    if [ ! -z "${os_cert}" ]; then
        enmExtraDetails="--os-cacert ${os_cert} ${enmExtraDetails}"
    fi
    # What type of install to execute
    if [[ "${enm_deployment_type}" == "micro" ]]; then
        enmExtraDetails="ci microenm stacks delete ${enmExtraDetails}"
    else
        enmExtraDetails="nwci enm stacks delete ${enmExtraDetails}"
    fi

    if [ ! -z ${lcm_sed_file_location} ]; then
        enmExtraDetails="--vnf-lcm-sed-file-url ${lcm_sed_file_location} ${enmExtraDetails}"
    fi

    echo "docker run --rm ${dockerExtraDetails} -v ${download_location}:${download_location_mount} armdocker.rnd.ericsson.se/proj_nwci/enmdeployer:${openstackdeploy_gav_version} ${enmExtraDetails} --os-username ${username} --os-password "${password}" --os-auth-url ${os_auth_url} --os-project-name ${os_project_name} --deployment-name ${deployment_name} --debug"
    docker run --rm ${dockerExtraDetails} -v ${download_location}:${download_location_mount} armdocker.rnd.ericsson.se/proj_nwci/enmdeployer:${openstackdeploy_gav_version} ${enmExtraDetails} --os-username ${username} --os-password "${password}" --os-auth-url ${os_auth_url} --os-project-name ${os_project_name} --deployment-name ${deployment_name} --debug
    command_code=$( echo $? )
    check_exit_code ${command_code}
}


# Main Calls
if [ ! -z ${env_configuration_file_artifactLocation_parameters_source} ]; then
    echo "Download Configuration File"
    download_configuration_file ${env_configuration_file_artifactLocation_parameters_source} ${configuration_file_location}
    . ${configuration_file_location}
fi
if [ ! -z "${os_cacert}" ]; then
    echo "Download os certification"
    download_os_cert_file ${os_cacert} ${os_cert_location}
fi
echo "Check and delete the stacks"
execute_main_enm_deployment_script ${os_cert_location_mount}
echo "DELETION CHECKS COMPLETED......"
clean_up ${download_location}
