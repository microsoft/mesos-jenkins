#!/usr/bin/env python3

import argparse
import os
import sys

sys.path.append(os.getcwd())

from common import (
    public_windows_slaves_addresses,
    private_windows_slaves_addresses,
    public_linux_slaves_addresses,
    private_linux_slaves_addresses
) # noqa


def parse_parameters():
    parser = argparse.ArgumentParser(
        description="Get the DCOS slave nodes' addresses")
    parser.add_argument("-o", "--operating-system", type=str, required=True,
                        choices=['linux', 'windows'],
                        help="The operating system of DCOS slaves")
    parser.add_argument("-r", "--role", type=str, required=True,
                        choices=['private', 'public'],
                        help="The role of the DCOS slaves")
    return parser.parse_args()


def main():
    params = parse_parameters()
    if params.operating_system == 'windows' and params.role == 'public':
        addresses = public_windows_slaves_addresses()
    elif params.operating_system == 'windows' and params.role == 'private':
        addresses = private_windows_slaves_addresses()
    elif params.operating_system == 'linux' and params.role == 'public':
        addresses = public_linux_slaves_addresses()
    elif params.operating_system == 'linux' and params.role == 'private':
        addresses = private_linux_slaves_addresses()
    if len(addresses) == 0:
        return
    print('\n'.join(addresses))


if __name__ == '__main__':
    main()
