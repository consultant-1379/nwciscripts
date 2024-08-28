#!/bin/bash

MEDIA_DETAILS=(${rhel6jbossimage_artifactLocation_parameters_source} ${rhelpostgresimage_artifactLocation_parameters_source} ${rhelvnflafimage_artifactLocation_parameters_source} ${enm_artifactLocation_parameters_source} ${RHEL_Media_artifactLocation_parameters_source} ${rhel6baseimage_artifactLocation_parameters_source} ${rhel7baseimage_artifactLocation_parameters_source} ${RHEL_OS_Patch_Set_artifactLocation_parameters_source} ${RHEL7_Media_artifactLocation_parameters_source} ${RHEL7_OS_Patch_Set_artifactLocation_parameters_source} ${RHEL6_10_Media_artifactLocation_parameters_source} ${rhel76lsbimage_artifactLocation_parameters_source})
CLOUD_TEMPLATE_DETAILS=(${microenmcloudtemplates_artifactLocation_parameters_source} ${enmcloudtemplates_artifactLocation_parameters_source})
DEPLOYMENT_WORKFLOW_DETAILS=(${enmdeploymentworkflows_artifactLocation_parameters_source})
CLOUD_MGMT_WORKFLOWS_DETAILS=(${enmcloudmgmtworkflows_artifactLocation_parameters_source})
CLOUD_PERFORMANCE_WORKFLOWS_DETAILS=(${enmcloudperformanceworkflows_artifactLocation_parameters_source})
VNF_CLOUD_TEMPLATE_DETAILS=(${vnflcmcloudtemplates_artifactLocation_parameters_source})
EDP_AUTODEPLOY_DETAILS=(${edp_auto_deploy_artifactLocation_parameters_source})
VNFLCM_DETAILS=(${vnflcm_details_artifactLocation_parameters_source})

download_location_mount=/var/tmp/mount
artifact_json_location="${download_location}/artifact_json_template.json"
artifact_json_location_mount="${download_location_mount}/artifact_json_template.json"
configuration_file_location="${download_location}/deployment_configuration_file.txt"
os_cert_location="${download_location}/os_cert.crt"
os_cert_location_mount="${download_location_mount}/os_cert.crt"
enm_sed_location="${download_location}/sed.txt"
CURL_INSECURE="curl --insecure"
DATE=`date '+%Y-%m-%d_%H:%M:%S'`

SSH_OPTS="-o PubkeyAuthentication=yes \
-o UserKnownHostsFile=/dev/null \
-o KbdInteractiveAuthentication=no \
-o PasswordAuthentication=no \
-o ChallengeResponseAuthentication=no \
-o LogLevel=quiet \
-o StrictHostKeyChecking=no \
-o HostbasedAuthentication=no \
-o PreferredAuthentications=publickey \
-o ConnectTimeout=120"

function version_gt() {
    # Function compares version numbers using unix sort
    # Snippet from man(1) sort:
    #       -V, --version-sort
    #          natural sort of (version) numbers within text
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

function populate_json_artifact_string() {
    # Function used to populate the ${artifact_json_template} parameter from the
    # artifact_json_template.json file with the appropriate media
    MEDIA_TYPE=$1
    artifact_json_template=$2
    declare -a MEDIA=("${!3}")

    MEDIA_lEN=${#MEDIA[@]}
    MEDIA_lEN_MINUS1=$((${MEDIA_lEN}-1))
    media_items=""
    for (( i=0; i<${MEDIA_lEN}; i++ )); do
        if [[ ${MEDIA[$i]} == *"vnflcm-cloudtemplates"* ]]; then
            CXP_NO="vnflcm-cloudtemplates"
        else
            CXP_NO=$( echo ${MEDIA[$i]} | sed -e 's/.*_CXP//' -e 's/.*-CXP//' -e 's/-.*//' -e 's/^/CXP/' )
        fi
        if (("$i" < "${MEDIA_lEN_MINUS1}")); then
            media_item="\"${CXP_NO}\": \"${MEDIA[$i]}\","
        else
            media_item="\"${CXP_NO}\": \"${MEDIA[$i]}\""
        fi
        media_items="$media_items $media_item"
    done
    artifact_json_template=$( echo ${artifact_json_template} | sed 's|'"${MEDIA_TYPE}"'|'"${media_items}"'|' )
}

function generate_artifact_json_file() {
    # Function to write the artifact json file out to a flat file
    artifact_json_location=$1
    artifact_json_template=$2
    echo ${artifact_json_template} > ${artifact_json_location}
    command_code=$( echo $? )
    check_exit_code ${command_code}
}


function download_pkg() {
    # Function to download the given pkg
    download_package=$1
    download_location=$2
    package_name=$( basename $download_package )
    ${CURL_INSECURE} -o ${download_location}/${package_name} ${download_package}
    command_code=$( echo $? )
    check_exit_code ${command_code}
}

function unzip_pkg() {
    # Function used to unzip an artifact
    teardown_package=$1
    download_location=$2
    teardown_name=$( basename $teardown_package )
    cd ${download_location}; unzip ${teardown_name}
    command_code=$( echo $? )
    check_exit_code ${command_code}
}

function execute_enm_deploy_delete_script() {
    # Function to execute the enm clean down
    teardown_download_location=$1
    teardown_script=${teardown_download_location}/automationScripts/teardown.sh
    ${teardown_script}
    command_code=$( echo $? )
    check_exit_code ${command_code}
}


function download_configuration_file() {
    # Function used to download the configuration file that should be
    # used for the deployment to execute on
    download_configuration=$1
    config_download_location=$2
    ${CURL_INSECURE} -o ${config_download_location} ${download_configuration}
    command_code=$( echo $? )
    check_exit_code ${command_code}
}


function download_os_cert_file() {
    # Function used to download the os cert file that should be
    # used for the deployment to execute on
    os_cacert=$1
    cert_download_location=$2
    ${CURL_INSECURE} -o ${cert_download_location} ${os_cacert}
    command_code=$( echo $? )
    check_exit_code ${command_code}
}

function check_exit_code(){
    # function used to check the exit code from an executed command if an error exit
    command_code=$1
    if [[ "$command_code" != "0" ]]; then
        echo "Temporary files in: ${download_location}"
        echo "Issue executing a command Exiting"
        exit 1
    fi
}

function wait_loop()
{
    # Function used to loop a given number of times
    enm_ip=$1
    loop=$2
    wait=$3
    while [[ $wait -lt ${loop} ]]; do
        ${CURL_INSECURE} -L -s https://${enm_ip}/ | grep ENM >/dev/null
        output=$( echo $? )
        if [[ "${output}" != "0" ]]; then
            echo "Waiting 30 seconds before checking is the ENM Login Prompt available"
            sleep 30
            wait=$((wait+1))
        else
            wait=0
            break
        fi
    done
    return ${wait}
}

function execute_check_on_enm_login_prompt()
{
    # Function used to check to see has the ENM Login prompt come up
    wait=0
    enm_sed_file_location=$1
    download_location=$2
    enm_deployment_type=$3
    ${CURL_INSECURE} -o ${download_location} ${enm_sed_file_location}
    command_code=$( echo $? )
    check_exit_code ${command_code}
    if [[ "${enm_deployment_type}" == "micro" ]]; then
        if ( echo ${enm_sed_file_location} | grep "json" ); then
            enm_ip=$( cat ${download_location} | grep haproxy_external_ip_list | sed -e 's/ //g' -e 's/.*platform_external_ip_address":"//' -e 's/",.*//' -e 's/"}.*//' )
            enm_hostname=$( cat ${download_location} | grep httpd_fqdn | sed -e 's/ //g' -e 's/.*httpd_fqdn":"//' -e 's/",.*//' -e 's/"}.*//' )
        else
            enm_ip=$( cat ${download_location} | grep "platform_external_ip_address" | sed 's/.*\://g' | awk '{$1=$1}1' | sed 's/\r//' )
            enm_hostname=$( cat ${download_location} | grep "httpd_fqdn" | sed 's/.*\://g' | awk '{$1=$1}1' | sed 's/\r//' )
        fi
    else
        if ( echo ${enm_sed_file_location} | grep "json" ); then
            enm_ip=$( cat ${download_location} | grep haproxy_external_ip_list | sed -e 's/ //g' -e 's/.*haproxy_external_ip_list":"//' -e 's/",.*//' -e 's/"}.*//' )
            enm_hostname=$( cat ${download_location} | grep httpd_fqdn | sed -e 's/ //g' -e 's/.*httpd_fqdn":"//' -e 's/",.*//' -e 's/"}.*//' )
        else
            enm_ip=$( cat ${download_location} | grep "haproxy_external_ip_list" | sed 's/.*\://g' | awk '{$1=$1}1' | sed 's/\r//' )
            enm_hostname=$( cat ${download_location} | grep "httpd_fqdn" | sed 's/.*\://g' | awk '{$1=$1}1' | sed 's/\r//' )
        fi
    fi
    if [ ! -z ${add_enm_gui_to_host} ]; then
        if [[ "${add_enm_gui_to_host}" == "YES" ]]; then
            if ! grep -q ${enm_ip} "/etc/hosts"; then
                sudo cp /etc/hosts /etc/hosts_${DATE}
                sudo -- sh -c -e "echo '${enm_ip}   ${enm_hostname}' >> /etc/hosts";
            fi
        fi
    fi
    wait_loop ${enm_ip} 140 ${wait}
    wait=$?
    # Execute workaround for slow cloud deployments i.e. PC Cloud (Gothenburg)
    if [ $wait -ne 0 ]; then
        if [[ "${enm_deployment_type}" == "micro" ]]; then
            echo "The ENM Login Prompt https://${enm_ip}/ doesn't seem to be available within the allotted time"
            echo "This deployment has been noted as a Gothenburg deployment so going to redeploy the ui_stack"
            echo "to see will it fix the issue"
            wait=0
            echo "${_BASEDIR}/stack_redeploy_wd.sh ${download_location} ui_stack"
            ${_BASEDIR}/stack_redeploy_wd.sh ${download_location} ui_stack
            command_code=$( echo $? )
            check_exit_code ${command_code}
            echo "Execute check on ENM Login GUI Again (Maximum Wait time 20 mins)"
            wait_loop ${enm_ip} 40 ${wait}
            wait=$?
        fi
    fi
    if [ $wait -ne 0 ]; then
        echo "The ENM Login Prompt https://${enm_ip}/ doesn't seem to be available within the allotted time"
        check_exit_code 1
    fi
}


function clean_up() {
    # Function to clean up after the deployment
    download_location=$1
    cd /tmp; rm -rf $download_location
}

function get_vnflcm_external_ip () {
    ############################################################################
    # Function to gather vnflcm_external_ip
    # Arguments:
    #    $1 -- VNFLCM SED file
    # Returns:
    #    external_ipv4_for_services_vm -- string
    ############################################################################
    # ENM <= 18.16
    # services_vm_count not defined in SED, use external_ipv4_for_services_vm
    #
    # ENM >= 19.01
    # If value for services_vm_count is 1: Replace the value of <VNF-LCM Services VM
    #                                      External IP> with the Ip address assigned to
    #                                      variable external_ipv4_for_services_vm
    # If value for services_vm_count is 2: Replace the value of <VNF-LCM Services VM
    #                                      External IP> with the Ip address assigned to
    #                                      variable external_ipv4_vip_for_services_vm
    ############################################################################
    vnflcm_sed=$1
    services_vm_count=$(grep "services_vm_count" "${vnflcm_sed}" | sed 's/:/ /;s/"//g;s/,/ /g' | awk '{print $2}')
    if [[ $services_vm_count == 0 || $services_vm_count == 1 ]]
    then
        external_ipv4_for_services_vm=$(grep "external_ipv4_for_services_vm" "${vnflcm_sed}" | sed 's/:/ /;s/"//g;s/,/ /g' | awk '{print $2}')
    elif [[ $services_vm_count == 2 ]]
    then
        external_ipv4_for_services_vm=$(grep "external_ipv4_vip_for_services" "${vnflcm_sed}" | sed 's/:/ /;s/"//g;s/,/ /g' | awk '{print $2}')
    fi
    echo "${external_ipv4_for_services_vm}"
}


function execute_verbose() {
    # Function to execute a single bash command
    #
    # It reports to stdout:
    #     - executed command,
    #     - in case of failure, the output of stdout and stderr
    #
    # Arguments:
    #     cmd -- command to execute
    #
    # Returns:
    #     rcode -- $? of the executed command
    #
    # Attention:
    #     execute_verbose will not execute multiple commands:
    #
    #     Examples:
    #
    #     OK
    #     execute_verbose "ls -l"
    #
    #     Not OK:
    #     execute_verbose "sleep 1; ls -l"

    if [ "$#" -ne 1 ]; then
        echo "execute_verbose(): Invalid number of parameters."
        echo "Usage:"
        echo "    execute_verbose \"CMD\""
        return 1
    fi

    local cmd
    local out
    local rcode

    cmd=$1

    echo "Executing:"
    echo "$cmd"
    out=$($cmd 2>&1)
    rcode=$?

    if [ "$rcode" -ne 0 ]; then
        echo "Error executing command"
    fi
    echo "$out"
    return "$rcode"
}
