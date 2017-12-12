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
            print("False")
            return
        if slave["attributes"]["infrastructure"] != "ci":
            print("False")
            return
    print("True")


if __name__ == '__main__':
    main()
