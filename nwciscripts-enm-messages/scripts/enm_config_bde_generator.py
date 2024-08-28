#!/usr/bin/env python

import requests
import json
import os
import io
import urllib

from requests.auth import HTTPBasicAuth

requests.packages.urllib3.disable_warnings()

sed_filename = "sed.json"

# NEXUS Details
nexus_username = "bucinwci"
nexus_password = "password"
nexus_repo = "releases"
nexus_url = "https://arm3s11-eiffel004.eiffel.gic.ericsson.se:8443/nexus/service/local/"
nexus_post = "artifact/maven/content"
nexus_link = "repo_groups/nwci-repositories/content/"

# DIT Details
dit_url = "https://atvdit.athtem.eei.ericsson.se/"
dit_doc = "api/documents"
dit_schema = "api/schemas"

# CI Portal(Axis)
ci_productSet_contents_url = "http://cifwk-oss.lmera.ericsson.se/getProductSetVersionContents/?"
ci_iso_contents_url = "http://cifwk-oss.lmera.ericsson.se/getPackagesInISO/?"


class Sed:
    def __init__(self, sed_id, schema_id):
        self.sed_id = sed_id
        self.schema_id = schema_id


def get_schema_version(prod_set_version):
    """
    Get the Schema Version for the particular product set.

    :param prod_set_version: version of the product set.
    """
    try:
        global enm_version
        enm_artifact_id = "ERICenm_CXP9027091"
        prodset_content_data = get_productset_contents(prod_set_version)
        enm_version = parse_for_iso_version(prodset_content_data, enm_artifact_id)
        iso_content_data = get_iso_contents(enm_version)
        enmcloudtemplates_version = parse_for_rpm_version("ERICenmcloudtemplates_CXP9033639", iso_content_data)
        print 'Schema Version:' + enmcloudtemplates_version
        return enmcloudtemplates_version
    except Exception as ex:
        raise Exception("Cannot get the Schema Version", ex)


def update_schema_in_sed(sed_name, schema_version):
    """
    Update the Schema Version for the specified SED.

    :param sed_name: name of the SED
    :param schema_version: version of the schema
    """
    try:
        sed = get_sed_details_from_name(sed_name)
        schema_id = get_schema_id_from_name("enm_sed", schema_version)
        if sed.schema_id == schema_id:
            print 'Sed ' + sed_name + ' is already updated with Schema Version ' + schema_version
            return
        full_url = dit_url + dit_doc + '/' + sed.sed_id
        json_data = json.dumps({"schema_id": schema_id})
        headers = {"Content-Type": "application/json"}
        response = requests.put(full_url, data=json_data, headers=headers)
        if response.status_code != 200:
            raise Exception("Schema ID cannot be updated")
        print sed_name + 'Updated with Schema Version:' + schema_version
    except Exception as ex:
        raise Exception("Cannot Update the Schema Version", ex)


def update_label_in_sed(sed_name, schema_version):
    """
    Update the Managed label Version for the specified SED.

    :param sed_name: name of the SED
    :param schema_version: version of the schema
    """
    try:
        sed = get_sed_details_from_name(sed_name)
        schema_id = get_schema_id_from_name("enm_sed", schema_version)
        full_url = dit_url + dit_doc
        json_data = json.dumps({"autopopulate":"false","labels":["NWCI_Single_Instance"],"managedconfigs":[],"managedconfig":"true","content":{"parameters":{"serviceregistry_instances":"3"}},"schema_id":schema_id,"name":"NWCI_Single_Instance_"+schema_version})
        headers = {"Content-Type": "application/json"}
        response = requests.post(full_url, data=json_data, headers=headers)
        print sed_name + ' update with Managed Config Label NWCI_Single_Instance_' + schema_version
    except Exception as ex:
        raise Exception("Cannot update sed with Managed Config Label, NWCI_Single_Instance_" + schema_version, ex)


def get_schema_id_from_name(schema_name, schema_version):
    """
    Get the schema id for the schema name

    :param schema_name: name of the schema to be fetched
    :param schema_version: version of the schema to be fetched.
    :return schema_id: id of the Schema file
    """
    try:
        amp = urllib.quote("&")
        query = '?q=name='+schema_name+amp+'version='+schema_version+'&fields=_id'
        print 'Get Schema ID from DIT:' + dit_url + dit_schema + query
        response = requests.get(dit_url + dit_schema + query)
        if response.status_code != 200:
            raise Exception("Schema ID cannot be Obtained")
        schema_content = response.json()
        print 'Schema ID for schema_version ' + schema_version + ':' + schema_content[0]['_id']
        return schema_content[0]['_id']
    except Exception as ex:
        raise Exception("Cannot get the Schema id for the schema version:" + schema_version, ex)


def get_sed_details_from_name(sed_name):
    """
    Get the sed id for the sed name

    :param sed_name: name of the sed file to be downloaded.
    :return sed_id: id of the SED file
    """
    print 'Get SED Details:' + dit_url + dit_doc + '?q=name=' + sed_name + '&fields=_id&fields=schema_id'
    try:
        response = requests.get(dit_url + dit_doc + '?q=name=' + sed_name + '&fields=_id&fields=schema_id')
        if response.status_code != 200:
            raise Exception("SED Info cannot be Obtained")
        sed_content = response.json()
        print 'SED id:' + sed_content[0]['_id']
        print 'Schema id:' + sed_content[0]['schema_id']
        return Sed(sed_content[0]['_id'], sed_content[0]['schema_id'])
    except Exception as ex:
        raise Exception("Cannot get the SED id for the sed:" + sed_name, ex)


def download_sed_from_dit(sed_name):
    """
    Download the SED file from DIT

    :param sed_name: name of the sed file to be downloaded.
    """
    print "Download SED from DIT:" + dit_url + dit_doc + '?q=name=' + sed_name
    try:
        if os.path.exists(sed_filename):
            os.remove(sed_filename)
        response = requests.get(dit_url + dit_doc + '?q=name=' + sed_name)
        if response.status_code != 200:
            raise Exception("SED cannot be downloaded")
        sed_content = response.json()
        #print sed_content[0]['content']
        with open(sed_filename, 'w') as f:
            f.write(json.dumps(sed_content[0]['content']))
    except Exception as ex:
        raise Exception("Cannot Download the SED", ex)


def upload_to_nexus(group_id, artifact_id, version, filetype, file):
    """
    Uploads the Artifact to Nexus

    :param group_id: group id of the artifact
    :param artifact_id: Artifact id of the artifact
    :param version: version of the artifact
    :param filetype: filetype of the artifact
    :param file: artifact to be uploaded.
    :return: url of the uploaded artifact
    """
    try:
        files = {'file': open(file, 'rb')}
        print 'Uploading to Nexus'
        response = requests.post(nexus_url + nexus_post, auth=HTTPBasicAuth(nexus_username, nexus_password),
                                 data=dict(r=nexus_repo, g=group_id, a=artifact_id, v=version, p=filetype),
                                 files=files,
                                 verify=False)
        print response.status_code
        if response.status_code != 201:
            if "does not allow updating artifacts" not in response.content:
                raise Exception("Error in Uploading to Nexus")
            else:
                print "Artifact is already in Nexus"
        print response.content
        return nexus_url + nexus_link + group_id.replace('.',
                                                         '/') + '/' + artifact_id + '/' + version + '/' + artifact_id + '-' + version + '.' + filetype
    except Exception as ex:
        raise Exception("Artifact cannot be uploaded to Nexus", ex)


# Internal Functions
def get_productset_contents(prod_set_version):
    url_parameters = {"productSet": "ENM", "version": prod_set_version}
    url = urllib.urlencode(url_parameters)
    print 'Get ProductSet Contents: ' + ci_productSet_contents_url + url
    response = requests.get(ci_productSet_contents_url + url)
    # print response.content
    if response.status_code != 200:
        raise Exception("Product Set contents cannot be downloaded")
    return response.json()


def get_iso_contents(iso_version):
    url_parameters = {"isoName": "ERICenm_CXP9027091", "isoVersion": iso_version,
                      "pretty": "true"}
    url = urllib.urlencode(url_parameters)
    print 'Get ISO Contents: ' + ci_iso_contents_url + url
    response = requests.get(ci_iso_contents_url + url)
    # print response.content
    if response.status_code != 200:
        raise Exception("ISO contents cannot be downloaded")
    return response.json()


def parse_for_iso_version(json_returned, artifact_id):
    """
    :param json_returned:
    :param artifact_id:
    :return iso_version:
    This function loops through the parsed JSON string
    and returns the required iso_version.
    """
    if type(json_returned) is dict:
        for key_found in json_returned:
            if key_found == "artifactName":
                if json_returned[key_found] == artifact_id:
                    return json_returned["version"]
            iso_version = parse_for_iso_version(json_returned[key_found],
                                                artifact_id)
            if iso_version:
                return iso_version
    elif type(json_returned) is list:
        for item in json_returned:
            if type(item) in (list, dict):
                iso_version = parse_for_iso_version(item, artifact_id)
                if iso_version:
                    return iso_version


def parse_for_rpm_version(rpm_name, iso_content_data):
    json_object = iso_content_data
    if type(json_object) is dict:
        for key_found in json_object:
            if key_found == "PackagesInISO":
                iso_content = json_object[key_found]
                for package in iso_content:
                    if rpm_name in package['name']:
                        version = package['version']
                        pkgUrl = package['url']
                        return version


if __name__ == "__main__":
    try:
        data = json.loads(os.environ['TRIGGER_MESSAGES'])
        site = os.environ['SITE']
        if "GROUP_ID" in os.environ:
            nexus_groupID = os.environ['GROUP_ID']
        product_set_version = data[0]['eventData']['gav']['version']
        schema_version = get_schema_version(product_set_version)
        update_label_in_sed(site, schema_version)
        update_schema_in_sed(site, schema_version)
        download_sed_from_dit(site)
        enm_sed_file_location = upload_to_nexus(nexus_groupID, "sed", schema_version, "json", sed_filename)
        print "Writing info to environment file"
        with io.FileIO("env.conf", "w") as f:
            f.write("site=" + str(site) + "\n")
            f.write("group=" + str(nexus_groupID) + "\n")
            f.write("enm_sed_file_location=" + str(enm_sed_file_location) + "\n")
            f.write("product_set_version=" + str(product_set_version) + "\n")
            f.write("enm_version=" + str(enm_version))
        f.close

    except Exception as e:
        print e
        exit(1)
    exit(0)
