#!/bin/bash
##########################################
# Should be Commented out for official release
#source ~/env.ini
###########################################

_BASEDIR=`dirname "$0"`
download_location="$( mktemp -d )"

source ${_BASEDIR}/common.sh

function execute_main_deployment() {
    # Function to kick off the deployment with the appropriate commands
    os_cert=$1
    username=$( echo ${os_username} | base64 --decode )
    password=$( echo ${os_password} | base64 --decode )
    export OS_AUTH_URL=${os_auth_url}
    export OS_USERNAME=${username}
    export OS_PASSWORD="${password}"
    export OS_PROJECT_NAME=${os_project_name}
    export OS_IDENTITY_API_VERSION=${os_identity_api_version}
    if [[ ${os_cert} != "" ]];then
        export OS_CACERT=${os_cert}
    fi

    ${CURL_INSECURE} -o "${download_location}"/vnflcm_sed.json "${lcm_sed_file_location}"
    check_exit_code $?
    vnflcm_external_ip=$(get_vnflcm_external_ip "${download_location}"/vnflcm_sed.json)

    key_stack_name=$(python "${_BASEDIR}"/json_parser.py --vnflcm-sed-file "${download_location}"/vnflcm_sed.json -p keypair)
    check_exit_code $?

    key_stack=$(openstack --insecure stack show "$key_stack_name" -c outputs -f json)
    check_exit_code $?

    python "${_BASEDIR}"/json_parser.py --stack "$key_stack" -p cloud_user_private_key > "${download_location}"/private_key.pem
    check_exit_code $?
    chmod 0600 "${download_location}"/private_key.pem
    consul_output=$(ssh -o StrictHostKeyChecking=no -i "${download_location}"/private_key.pem cloud-user@"${vnflcm_external_ip}" consul kv get enm/deployment/enm_version)
    check_exit_code $?

    enm_version_consul=$(echo "$consul_output" | awk '{print $2}')
    iso_version_consul=$(echo "$consul_output" | awk '{ gsub(")", ""); print ($5)}')

    if [[ "$enm_version_consul" != $(echo "$productSetVersion" | sed 's/.[0-9]*$//') ]]
    then
        echo "ENM version from consul don't match version from productSetVersion"
        echo "enm_version_consul=$enm_version_consul"
        echo "productSetVersion=$productSetVersion"
        check_exit_code 1
    fi

    if [[ "$iso_version_consul" != "$enm_gav_version" ]]; then
        echo "ISO version from consul don't match version from enm_gav_version"
        echo "iso_version_consul=$iso_version_consul"
        echo "enm_gav_version=$enm_gav_version"
        check_exit_code 1
    fi

    mainVolumeList=$( openstack volume list | grep available | awk '{print $2 "__" $4}' )
    snapshotVolumeList=$( openstack volume snapshot list | grep available | awk '{print $2 "__" $4}' )
    echo "Main Volume List:: "
    echo ${mainVolumeList}
    echo ""
    echo "Snapshot list:: "
    echo ${snapshotVolumeList}

    ${CURL_INSECURE} -o ${download_location}/sed.json ${enm_sed_file_location}
    command_code=$( echo $? )
    check_exit_code ${command_code}
    if ( echo ${enm_sed_file_location} | grep "json" ); then
        deploymentId=$( cat ${download_location}/sed.json | grep deployment_id | sed -e 's/ //g' -e 's/.*deployment_id":"//' -e 's/",.*//' -e 's/"}.*//' )
    fi
    echo "Deployment ID :: ${deploymentId}"
    echo "Snapshot TAG :: ${snapshot_tag}"
    for volumeListFull in "${mainVolumeList}___main" "${snapshotVolumeList}___snapshot"; do
        volumeList=$( echo $volumeListFull | sed 's/___.*//' )
        volumeType=$( echo $volumeListFull | sed 's/.*___//' )
        if [[ ${volumeType} == "main" ]]; then
            searchString=${deploymentId}
            volumeCommand="volume"
        elif [[ ${volumeType} == "snapshot" ]]; then
            searchString=${snapshot_tag}
            volumeCommand="volume snapshot"
        else
            echo "Error there was an issue setting the volume type info"
            echo "Exiting!!!"
            check_exit_code 1
        fi

        # First loop through list to ensure you have the correct volumes according to Deployment ID within SED
        for item in ${volumeList}; do
            volumeId=$( echo $item | sed 's/__/ /' | awk '{print $1}' )
            volumeName=$( echo $item | sed 's/__/ /' | awk '{print $2}' )
            if [[ $item != *"${searchString}"* ]];then
                echo "Volume ${volumeName} with id of ${volumeId} doesn't contain the search string, ${searchString}"
                echo "Exiting!!!"
                check_exit_code 1
            fi
        done
        for item in ${volumeList}; do
            volumeId=$( echo $item | sed 's/__/ /' | awk '{print $1}' )
            volumeName=$( echo $item | sed 's/__/ /' | awk '{print $2}' )
            echo "Removing Volume, ${volumeName} with ID ${volumeId}"
            echo "Executing, openstack ${volumeCommand} delete ${volumeId}"
            openstack ${volumeCommand} delete ${volumeId}
            sleep 5
        done
        echo "Sleeping for 60 seconds for all to be deleted"
        sleep 60
        for item in ${volumeList}; do
            volumeId=$( echo $item | sed 's/__/ /' | awk '{print $1}' )
            volumeName=$( echo $item | sed 's/__/ /' | awk '{print $2}' )
            echo "Checking have the volume, ${volumeName} with ID ${volumeId} has been deleted"
            loop=1
            while [ $loop -le 60 ]; do
                echo "Executing, openstack ${volumeCommand} show ${volumeId} -f json"
                volumeStatus=$( openstack ${volumeCommand} show ${volumeId} -f json | grep -e '"status"' -e "No volume with a name" -e "No snapshot with a name" | awk '{print $2}' | sed -e 's/"//g' -e 's/,//' | tr '[:lower:]' '[:upper:]' )
                if [[ ${volumeStatus} == "DELETING" ]];then
                    echo "Volume Not Deleted Waiting 10 seconds before retry..."
                    sleep 10
                    loop=$((loop + 1))
                elif [[ ${volumeStatus} == "DELETE_FAILED" ]] || [[ ${volumeStatus} == "AVAILABLE" ]]; then
                    echo "Error there was an issue deleting the volume, ${volumeName} with ID ${volumeId}, its status is ${volumeStatus}"
                    echo "Exiting!!!"
                    check_exit_code 1
                elif [[ ${volumeStatus} = *"NO SNAPSHOT"* ]] || [[ ${volumeStatus} = *"NO VOLUME"* ]];then
                    echo "Volume Deleted"
                    break
                elif [[ ${volumeStatus} == "" ]]; then
                    echo "Volume Deleted"
                    break
                else
                    echo "Error there was an issue unable to determin the status, \"${volumeStatus}\". Please investigate."
                    echo "Exiting!!!"
                    check_exit_code 1
                fi
            done
        done
    done

    # On the VNF-LCM services VM, restart the consul agent
    execute_verbose "ssh ${SSH_OPTS} -i ${download_location}/private_key.pem cloud-user@${vnflcm_external_ip} sudo service consul restart"
    check_exit_code $?
}

# Main Calls
if [ ! -z "${os_cacert}" ]; then
    echo "Download os certification"
    download_os_cert_file ${os_cacert} ${os_cert_location}
fi
echo "Execute Main deployment"
execute_main_deployment ${os_cert_location}
echo "Execute check on ENM Login GUI (Maximum Wait time 70 mins)"
execute_check_on_enm_login_prompt ${enm_sed_file_location} ${enm_sed_location} ${enm_deployment_type}
echo "EXECUTION COMPLETED......"
clean_up ${download_location}
