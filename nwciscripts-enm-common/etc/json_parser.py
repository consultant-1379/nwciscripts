import sys
import json
import argparse

def get_keypair(vnflcm_sed_file):
    """Function to return 'keypair' property from provided VNF-LCM SED file
    It contains the name of the stack with PEM keys of cloud-user.

    Arguments:
        vnflcm_sed_file -- filename of VNF-LCM SED

    Returns:
        keypair -- (str) 'keypair' stack name

    Raises:
        ValueError -- invalid SED file
    """
    with open(vnflcm_sed_file) as data:
        sed = json.load(data)
        if 'parameter_defaults' in sed:
            parameters = 'parameter_defaults'
        elif 'parameters' in sed:
            parameters = 'parameters'
        else:
            raise ValueError("{} does not contain neither 'parameter_defaults'"
                             " nor 'parameters'".format(vnflcm_sed_file))

        return sed[parameters]['keypair']


def get_cloud_user_private_key(stack):
    """
    Function to return cloud-user's private key from output of
    openstack stack show <stack name> -f json

    Arguments:
        stack -- openstack stack description (JSON)

    Returns:
        cloud_user_private_key -- private key (str)
    """
    return [key['output_value'] for key in stack['outputs']
            if key.get('output_key') == 'cloud_user_private_key'][0]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--vnflcm-sed-file', help='VNF-LCM SED file')
    parser.add_argument('--stack', help='openstack stack (as json)')
    parser.add_argument(
        '-p', '--property',
        help='available options: cloud_user_private_key, keypair')
    args = parser.parse_args()

    if args.property == 'cloud_user_private_key' and args.stack:
        print(get_cloud_user_private_key(json.loads(args.stack)))
        sys.exit(0)

    if args.property == 'keypair' and args.vnflcm_sed_file:
        print(get_keypair(args.vnflcm_sed_file))
        sys.exit(0)

    sys.exit(1)