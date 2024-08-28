#!/bin/bash
#set -xv
##########################################
#source ~/env.ini
###########################################

_BASEDIR=`dirname "$0"`
download_location_sed="$1"
stack="$2"
download_location=$( dirname ${download_location_sed} )
download_location_pkg=${download_location}/pkg
download_location_mount=/var/tmp/mount
configuration_file_location="${download_location}/deployment_configuration_file.txt"
CURL_INSECURE="curl --insecure"

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
    package=$1
    download_location=$2
    package_name=$( basename $package )
    cd ${download_location}; unzip ${package_name}
    command_code=$( echo $? )
    check_exit_code ${command_code}
}


function rename_file(){
    # function used to rename a file in a given location to another file name within the same location
    file=$1
    newFile=$2
    basedir=$( dirname ${file} )
    cp ${file} ${basedir}/${newFile}
}


function update_file(){
    # function used to update a file with a given parameter
    file=$1
    key=$2
    value=$3
    echo "  ${key}: ${value}" >> $file
    command_code=$( echo $? )
    check_exit_code ${command_code}
}


function build_command(){
    # Function used to build up the command to be used to destroy and redeploy the ui stack
    stack_name=$1
    enmcloudtemplates_location=$2
    download_location_pkg=$3
    download_location_mount=$4
    download_location=$( dirname ${download_location_pkg} )
    packageName=$( basename ${microenmcloudtemplates_artifactLocation_parameters_source} )
    packageNameNoPrefix=$( echo ${packageName} | sed 's/\.[^.]*$//' )
    username=$( echo ${os_username} | base64 --decode )
    password=$( echo ${os_password} | base64 --decode )

    file=${download_location}/destroy_deploy.sh
cat << EOF > ${file}
    #!/usr/bin/bash
    export OS_AUTH_URL="${os_auth_url}"
    export OS_USERNAME=${username}
    export OS_TENANT_NAME=${os_project_name}
    export OS_PASSWORD=${password}
    export OS_CACERT=${download_location_mount}/os_cert.crt
    export OS_IDENTITY_API_VERSION=${os_identity_api_version}

    stack_name=${deployment_name}_${stack_name}

    function wait_loop()
    {
	command=\$1
	errorCode=\$2
    	loop=20
    	wait=0
        echo "Executing Command, \${command}"
    	while [ \$wait -lt \${loop} ]; do
	    
	    \${command} > /dev/null 2>&1
            output=\$( echo \$? )
	    if [[ "\${output}" != \${errorCode} ]]; then
	       echo "Waiting 30 seconds before checking is the \${stack_name} command completed"
	       sleep 30
	       wait=\$((wait+1))
	    else
	       wait=0
	       break
	    fi
    	done
   	return \${wait}
    }

    function check_exit_code(){
        # function used to check the exit code from a executed command if an error exit
        command_code=\$1
        if [[ "\$command_code" != "0" ]]; then
            echo "Issue executing a command Exiting"
            exit 1
        fi
    }
    # Main function
    echo "Destroying the \${stack_name} stack"
    echo "Executing, openstack stack delete \${stack_name} --yes"
    openstack stack delete \${stack_name} --yes > /dev/null 2>&1
    code=\$?
    check_exit_code \${code}

    echo "Ensuring the stack is deleted before continuing"
    wait_loop "openstack stack show \${stack_name} -f json" 1
    wait=\$?
    if [ \$wait -ne 0 ]; then
        echo "The \${stack_name} is not destroyed please investigate"
        exit 1
    fi

    echo "Recreating the \${stack_name}"
    echo "Executing, openstack stack create -t ${download_location_mount}/pkg/${packageNameNoPrefix}/stacks_ecee/${stack_name}.yaml -e ${download_location_mount}/sed.yaml \${stack_name} -f json"
    openstack stack create -t ${download_location_mount}/pkg/${packageNameNoPrefix}/stacks_ecee/${stack_name}.yaml -e ${download_location_mount}/sed.yaml \${stack_name} -f json > /dev/null 2>&1

    openstack_return_code=\$?
    if [ \$openstack_return_code -ne 0 ]; then
        echo "The \${stack_name} failed to create, please investigate"
        exit 1
    fi

    echo "Ensuring the stack is recreated before continuing"
    wait_loop "openstack stack show \${stack_name} -f json" 0
    wait=\$?
    if [ \$wait -ne 0 ]; then
        echo "The \${stack_name} is not recreated please investigate"
        exit 1
    fi
EOF
}


function execute_command() {
    # Function to kick off the deployment with the appropriate commands
    if [ ! -z "${cee_host}" ]; then
        echo "docker run --rm --entrypoint /bin/bash --add-host ${atlas_host}:${atlas_ip} --add-host ${cee_host}:${cee_ip} -v ${download_location}:${download_location_mount} armdocker.rnd.ericsson.se/proj_nwci/enmdeployer:${openstackdeploy_gav_version} ${download_location_mount}/destroy_deploy.sh"
        docker run --rm --entrypoint /bin/bash --add-host ${atlas_host}:${atlas_ip} --add-host ${cee_host}:${cee_ip} -v ${download_location}:${download_location_mount} armdocker.rnd.ericsson.se/proj_nwci/enmdeployer:${openstackdeploy_gav_version} ${download_location_mount}/destroy_deploy.sh
    else
        echo "docker run --rm --entrypoint /bin/bash --add-host ${atlas_host}:${atlas_ip} -v ${download_location}:${download_location_mount} armdocker.rnd.ericsson.se/proj_nwci/enmdeployer:${openstackdeploy_gav_version} ${download_location_mount}/destroy_deploy.sh"
        docker run --rm --entrypoint /bin/bash --add-host ${atlas_host}:${atlas_ip} -v ${download_location}:${download_location_mount} armdocker.rnd.ericsson.se/proj_nwci/enmdeployer:${openstackdeploy_gav_version} ${download_location_mount}/destroy_deploy.sh
    fi
    command_code=$( echo $? )
    check_exit_code ${command_code}
}


function check_exit_code(){
    # function used to check the exit code from a executed command if an error exit
    command_code=$1
    if [[ "$command_code" != "0" ]]; then
        exit 1
    fi
}


# Main Calls
mkdir -p ${download_location_pkg}
echo "Downloading ${microenmcloudtemplates_artifactLocation_parameters_source} to ${download_location_pkg}"
download_pkg ${microenmcloudtemplates_artifactLocation_parameters_source} ${download_location_pkg}
echo "Unzip the ENM Cloud Package"
unzip_pkg ${microenmcloudtemplates_artifactLocation_parameters_source} ${download_location_pkg}
echo "Update the SED File with RHEL 6 Base Image"
key="enm_rhel6_base_image_name"
value=$( basename ${rhel6baseimage_artifactLocation_parameters_source} | sed 's/\.qcow2/_CI.qcow2/' )
update_file ${download_location_sed} $key $value
rename_file ${download_location_sed} "sed.yaml"
if [ -f ${configuration_file_location} ]; then
    . ${configuration_file_location}
fi
echo "Build Openstack Destroy and deploy command"
build_command ${stack} ${microenmcloudtemplates_artifactLocation_parameters_source} ${download_location_pkg} ${download_location_mount}
echo "Execute Main deployment"
execute_command
