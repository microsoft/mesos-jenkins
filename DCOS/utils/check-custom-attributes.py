#!/usr/bin/env python3

import os
import sys

sys.path.append(os.getcwd())

from common import dcos_slaves # noqa


def main():
    #
    # Check if the custom attributes are set for all the slaves
    #
    slaves = dcos_slaves()
    for slave in slaves:
        if "infrastructure" not in slave["attributes"].keys():
            print("Slave %s doesn't have the 'infrastructure' custom "
                  "attribute set" % (slave['id']))
            sys.exit(1)
        if slave["attributes"]["infrastructure"] != "ci":
            print("Slave %s doesn't have the 'ci' custom attribute set" % (
                slave['id']))
            sys.exit(1)
    print("All the slaves have the custom attributes correctly set")


if __name__ == '__main__':
    main()
