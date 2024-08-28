import getopt
import json
import os
import re
import sys
import urllib
import urllib2
from distutils.version import LooseVersion

def main_get_info_from_args(argv):
    """
    Function to parse the parameters
    """
    try:
        opts, args = getopt.getopt(argv,
                                   "hp:o:",
                                   ["productSetDrop=", "enmDeployerVersion="])
    except getopt.GetoptError:
        print('enm_product_bde_generator.py -p <Product Set Drop> -o '
              '<ENM Deployer version>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print('enm_product_bde_generator.py -p <Product Set Drop> -o '
                  '<ENM Deployer version>')
            sys.exit()
        elif opt in ("-p", "--productSetDrop"):
            if "::" not in arg:
                product_set_drop = arg
                url_parameters = {"drop": product_set_drop,
                                  "productSet": "ENM"}
                url = urllib.urlencode(url_parameters)
                dmt_url = ("https://cifwk-oss.lmera.ericsson.se/"
                           "getLastGoodProductSetVersion/?" + url)
                product_set_version = return_url_response(dmt_url)
            else:
                product_set_version = arg.split('::')[1]
        elif opt in ("-o", "--enmDeployerVersion"):
            openstackdeploy_version = arg

    openstackdeploy_version_lower = openstackdeploy_version.lower()
    if openstackdeploy_version_lower == "none":
        # Get the Version of the Openstack Deployer Attached to the Product Set
        dmt_url = ("https://cifwk-oss.lmera.ericsson.se/api/deployment/"
                   "deploymentutilities/productSet/ENM/version/" +
                   str(product_set_version) + "/")
        deploymentUtilities = return_url_response(dmt_url)
        deploymentUtilitiesJson = return_json_object(deploymentUtilities)
        for key in deploymentUtilitiesJson:
            if key == "deployerVersion":
                openstackdeploy_version = deploymentUtilitiesJson[key]
                break
    start_functions(product_set_version, openstackdeploy_version)


def main_get_product_set_from_triggger():
    """
    Function to calculate the productSet and openstack deploy version from
    Trigger
    """
    ####### Section only used for trouble shooting ####################
    #json_data=open("/home/bucinwci/enmBde/TRIGGER_MESSAGE.txt").read()
    #data = json.loads(json_data)
    ##################################################################
    data = json.loads(os.environ['TRIGGER_MESSAGES'])
    product_set_version = data[0]['eventData']['gav']['version']
    s = data[0]['eventData']['optionalParameters']['deploymentUtilities']
    openstackdeploy_value = re.search(
        'deployerVersion::(.*)::ERICopenstackdeploy Version', s)
    openstackdeploy_version = openstackdeploy_value.group(1)
    start_functions(product_set_version, openstackdeploy_version)


def start_functions(product_set_version, openstackdeploy_version):
    """
    Main function to call script functions
    """

    enm_artifact_id = "ERICenm_CXP9027091"
    vnflcm_artifact_id = "ERICvnflcm_CXP9034858"
    rhel_artifact_id = "RHEL_Media_CXP9026759"
    rhel7_artifact_id = "RHEL76-MEDIA_CXP9037123"
    patches_artifact_id = "RHEL_OS_Patch_Set_CXP9034997"
    rhel7_patches_artifact_id = "RHEL76_OS_Patch_Set_CXP9037739"
    agat_artifact_id = "ERICenmagat_CXP9036311"

    rhel6_10_artifact_id = "RHEL6.10_Media_CXP9036772"
    url_parameters = {"productSet": "ENM", "version": product_set_version}
    url = urllib.urlencode(url_parameters)
    dmt_url = ("http://cifwk-oss.lmera.ericsson.se/"
               "getProductSetVersionContents/?" + url)
    html_response = return_url_response(dmt_url)
    product_set_content_json = return_json_object(html_response)
    enm_version = search_for_iso_version(product_set_content_json,
                                         enm_artifact_id)
    enm_url = search_for_iso_url(product_set_content_json, enm_artifact_id)
    rhel_url = search_for_iso_url(product_set_content_json, rhel_artifact_id)
    rhel7_url = search_for_iso_url(product_set_content_json, rhel7_artifact_id)
    patches_url = search_for_iso_url(product_set_content_json,
                                     patches_artifact_id)
    rhel7_patches_url = search_for_iso_url(product_set_content_json,
                                           rhel7_patches_artifact_id)
    rhel_version = search_for_iso_version(product_set_content_json,
                                          rhel_artifact_id)
    rhel7_version = search_for_iso_version(product_set_content_json,
                                           rhel7_artifact_id)
    patches_version = search_for_iso_version(product_set_content_json,
                                             patches_artifact_id)
    rhel7_patches_version = search_for_iso_version(product_set_content_json,
                                                   rhel7_patches_artifact_id)
    vnflcm_url = search_for_iso_url(product_set_content_json,
                                    vnflcm_artifact_id)
    vnflcm_version = search_for_iso_version(product_set_content_json,
                                            vnflcm_artifact_id)
    agat_url = search_for_iso_url(product_set_content_json, agat_artifact_id)
    agat_version = search_for_iso_version(product_set_content_json,
                                          agat_artifact_id)
    rhel6_10_url = search_for_iso_url(product_set_content_json,
                                  rhel6_10_artifact_id)
    rhel6_10_version = search_for_iso_version(product_set_content_json,
                                          rhel6_10_artifact_id)

    iso_content_data = get_json_data(enm_artifact_id, enm_version)
    vnflcm_data = get_json_data(vnflcm_artifact_id, vnflcm_version)
    rhel6baseimage = get_url_of_rpm("ERICrhel6baseimage_CXP9031559",
                                    iso_content_data)
    rhel7baseimage = get_url_of_rpm("ERICrhel7baseimage_CXP9032719",
                                    iso_content_data)
    rhelvnflafimage = get_url_of_rpm("ERICrhelvnflafimage_CXP9032490",
                                     vnflcm_data)
    rhelpostgresimage = get_url_of_rpm("ERICrhelpostgresimage_CXP9032491",
                                       vnflcm_data)
    vnflcmcloudtemplatesimage = get_url_of_rpm("vnflcm-cloudtemplates",
                                               vnflcm_data)
    enmcloudtemplates = get_url_of_rpm("ERICenmcloudtemplates_CXP9033639",
                                       iso_content_data)
    enmdeploymentworkflows = get_url_of_rpm(
        "ERICenmdeploymentworkflows_CXP9034151", iso_content_data)
    rhel6jbossimage = get_url_of_rpm("ERICrhel6jbossimage_CXP9031560",
                                     iso_content_data)
    rhel6baseimage_version = get_version_of_rpm(
        "ERICrhel6baseimage_CXP9031559", iso_content_data)
    rhel7baseimage_version = get_version_of_rpm(
        "ERICrhel7baseimage_CXP9032719", iso_content_data)
    rhelvnflafimage_version = get_version_of_rpm(
        "ERICrhelvnflafimage_CXP9032490", vnflcm_data)
    rhelpostgresimage_version = get_version_of_rpm(
        "ERICrhelpostgresimage_CXP9032491", vnflcm_data)
    vnflcmcloudtemplates_version = get_version_of_rpm("vnflcm-cloudtemplates",
                                                      vnflcm_data)
    enmcloudtemplates_version = get_version_of_rpm(
        "ERICenmcloudtemplates_CXP9033639", iso_content_data)
    enmdeploymentworkflows_version = get_version_of_rpm(
        "ERICenmdeploymentworkflows_CXP9034151", iso_content_data)
    rhel6jbossimage_version = get_version_of_rpm(
        "ERICrhel6jbossimage_CXP9031560", iso_content_data)
    print("enm_url="+enm_url)
    print("enm_version="+enm_version)
    print("product_set_version="+product_set_version)
    print("RHEL_Media_url="+rhel_url)
    print("RHEL_Media_version="+rhel_version)
    print("RHEL6_10_Media_url="+rhel6_10_url)
    print("RHEL6_10_Media_version="+rhel6_10_version)
    print("RHEL_OS_Patch_Set_url="+patches_url)
    print("RHEL_OS_Patch_Set_version="+patches_version)
    print("RHEL7_Media_url="+rhel7_url)
    print("RHEL7_Media_version="+rhel7_version)
    print("RHEL7_OS_Patch_Set_url="+rhel7_patches_url)
    print("RHEL7_OS_Patch_Set_version="+rhel7_patches_version)
    print("AGAT_url="+agat_url)
    print("AGAT_version="+agat_version)
    print("rhel6baseimage_url="+rhel6baseimage)
    print("rhel6baseimage_version="+rhel6baseimage_version)
    print("rhel7baseimage_url="+rhel7baseimage)
    print("rhel7baseimage_version="+rhel7baseimage_version)
    print("enmcloudtemplates_url="+enmcloudtemplates)
    print("enmcloudtemplates_version="+enmcloudtemplates_version)

    # From ENM 19.12 this media is no longer required.
    if LooseVersion(product_set_version) < "19.12.100":
        microenmcloudtemplates = get_url_of_rpm(
            "ERICmicroenmcloudtemplates_CXP9033953", iso_content_data)
        microenmcloudtemplates_version = get_version_of_rpm(
            "ERICmicroenmcloudtemplates_CXP9033953", iso_content_data)
        print("microenmcloudtemplates_url="+microenmcloudtemplates)
        print("microenmcloudtemplates_version="+microenmcloudtemplates_version)

    print("enmdeploymentworkflows_url="+enmdeploymentworkflows)
    print("enmdeploymentworkflows_version="+enmdeploymentworkflows_version)
    print("openstackdeploy_url=https://arm3s11-eiffel004.eiffel.gic.ericsson.se"
          ":8443/nexus/content/repositories/nwci-repositories/com/ericsson/de"
          "/ERICopenstackdeploy_CXP9033218/" + openstackdeploy_version +
          "/ERICopenstackdeploy_CXP9033218-" + openstackdeploy_version +
          ".-py2.py3-none-any.whl")
    print("openstackdeploy_version="+openstackdeploy_version)
    print("rhelpostgresimage_url="+rhelpostgresimage)
    print("rhelpostgresimage_version="+rhelpostgresimage_version)
    print("vnflafimage_url="+vnflcm_url)
    print("vnflafimage_version="+vnflcm_version)
    print("rhelvnflafimage_url="+rhelvnflafimage)
    print("rhelvnflafimage_version="+rhelvnflafimage_version)
    print("vnflcmcloudtemplatesimage_url="+vnflcmcloudtemplatesimage)
    print("vnflcmcloudtemplates_version="+vnflcmcloudtemplates_version)
    print("rhel6jbossimage_url="+rhel6jbossimage)
    print("rhel6jbossimage_version="+rhel6jbossimage_version)


def search_for_iso_version(json_returned, artifact_id):
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
            iso_version = search_for_iso_version(json_returned[key_found],
                                                 artifact_id)
            if iso_version:
                return iso_version
    elif type(json_returned) is list:
        for item in json_returned:
            if type(item) in (list, dict):
                iso_version = search_for_iso_version(item, artifact_id)
                if iso_version:
                    return iso_version


def search_for_iso_url(json_returned, artifact_id):
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
                    # If statement can be removed once CIS-72810 is closed
                    # (leave athloneUrl)
                    if (artifact_id == "ERICvnflcm_CXP9034858" or
                            artifact_id == "ERICenmagat_CXP9036311"):
                        return json_returned["hubUrl"]
                    else:
                        return json_returned["athloneUrl"]
            iso_version = search_for_iso_url(json_returned[key_found],
                                             artifact_id)
            if iso_version:
                return iso_version
    elif type(json_returned) is list:
        for item in json_returned:
            if type(item) in (list, dict):
                iso_version = search_for_iso_url(item, artifact_id)
                if iso_version:
                    return iso_version


def get_enm_iso_version_from_product_set(json_object):
    """
    :param json_object:
    :return: ENM ISO Version from Product Set content
    """
    iso_version = common_functions.search_for_iso_version(json_object,
                                                          config.ENM_ISO)
    #if iso_version:
    #    logging.info("ENM ISO Version = " + iso_version)
    #else:
    #    sys.exit(1)

    return iso_version


def return_json_object(html_response):
    try:
        parsed_json = json.loads(html_response)
    except ValueError:
        return False
    return parsed_json


def return_url_response(url):
    try:
        response = urllib2.urlopen(url)
    except urllib2.HTTPError, e:
        return False
    except urllib2.URLError, e:
        return False
    except ValueError, response:

        return False
    except socket.error as err:
        return False
    html_response = response.read()
    return html_response


def get_json_data(artifact_id, iso_version):
    url_parameters = {"isoName": artifact_id, "isoVersion": iso_version,
                      "pretty": "true"}
    url = urllib.urlencode(url_parameters)
    iso_content_rest_call = ("http://cifwk-oss.lmera.ericsson.se/"
                             "getPackagesInISO/?" + url)
    iso_content_html_response = return_url_response(
        iso_content_rest_call)
    iso_content_data = return_json_object(
        iso_content_html_response)

    return iso_content_data


def get_version_of_rpm(rpm_name, iso_content_data):
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


def get_url_of_rpm(rpm_name, iso_content_data):
    json_object = iso_content_data
    if type(json_object) is dict:
        for key_found in json_object:
            if key_found == "PackagesInISO":
                iso_content = json_object[key_found]
                for package in iso_content:
                    if rpm_name in package['name']:
                        version = package['version']
                        pkgUrl = package['url']
                        return pkgUrl


if __name__ == "__main__":
    if len(sys.argv) > 1:
        main_get_info_from_args(sys.argv[1:])
    else:
        main_get_product_set_from_triggger()
