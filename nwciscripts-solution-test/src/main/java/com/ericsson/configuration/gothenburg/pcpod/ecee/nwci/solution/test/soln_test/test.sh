#!/bin/sh

echo "################################# TAF TESTS #################################"

#tafDockerCompose_artifactLocation_parameters_source="https://arm3s11-eiffel004.eiffel.gic.ericsson.se:8443/nexus/service/local/repositories/releases/content/com/ericsson/configuration/enm/test/docker-compose/1.0.1/docker-compose-1.0.1.yml"

export HOSTNAME=${HOSTNAME}
taf_trigger_name=$( basename ${tafTriggerJar_artifactLocation_parameters_source} )
dockercompose_file=$( basename ${tafDockerCompose_artifactLocation_parameters_source} )

CURL_INSECURE="curl --insecure"
TE_HEALTHCHECK="${CURL_INSECURE} http://${HOSTNAME}:8080/jenkins/descriptorByName/com.ericsson.cifwk.taf.executor.healthcheck.HealthCheck/healthCheck | grep scope | grep -v false"
COUNT=0

function create_containers()
{
    echo "Creating TAF TE Containers"
    get_file ${tafDockerCompose_artifactLocation_parameters_source}
    docker-compose -f ${dockercompose_file} up -d
    wait_for_it
}

function wait_for_it()
{
    echo "Waiting for TE docker to be up and running"
    eval ${TE_HEALTHCHECK} > /dev/null 2>&1
    while [ $? -ne 0 ]
    do
        COUNT=`expr $COUNT + 1`
        if [ $COUNT -gt 50 ]; then
           echo "TAF TE Docker is not fully up and running...exiting"
           exit 1
           #break
        fi
        echo "$COUNT:Waiting for TE docker to be up and running"

        sleep 1
        eval ${TE_HEALTHCHECK} > /dev/null 2>&1
    done
}

function rm_containers()
{
    echo "Removing TAF TE Containers"
    docker-compose -f ${dockercompose_file} stop
    docker-compose -f ${dockercompose_file} rm -f
}

function check_exit_code(){
    # function used to check the exit code from a executed command if an error exit
    command_code=$1
    if [[ "$command_code" != "0" ]]; then
        echo "Issue executing a command Exiting"
        exit 1
    fi
}

function get_file() {
    # Function to curl down the give file
    artifact=$1
    curl -O --insecure ${artifact}
    command_code=$( echo $? )
    check_exit_code ${command_code}
}

# Main Function
echo "Getting Taf Trigger Jar"
get_file ${tafTriggerJar_artifactLocation_parameters_source}
create_containers
echo "Executing TAF Trigger Jar"
java -jar ${taf_trigger_name} taf.te.address=${HOSTNAME} taf.test.properties=${tafProperties_artifactLocation_parameters_source} taf.host.properties=${tafHostProperties_artifactLocation_parameters_source} taf.schedule=${tafScheduler_artifactLocation_parameters_source}
tafexitstatus=$( echo $? )
rm_containers

echo "################################# NOVA TESTS #################################"
docker run --rm -i -h novaexecutor -v ${testResults}:/allure-results -v /lab:/lab:shared armdocker.rnd.ericsson.se/proj_nwci/nova/novaexecutor | tee output

testReport=$(grep "Detail test info link" output | egrep -o 'https?://[^ ]+')
grep "Summary Info" output | grep -q "Pass"
novaexitStatus=$?
echo "novaReport="${testReport} >> out.properties
rm output

echo "################################# Calculating Overall Verdict #################################"

exitStatus=`expr $tafexitstatus + $novaexitStatus`
exit ${exitStatus}
