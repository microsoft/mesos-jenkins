#!/usr/bin/env python3

import json

from dcos import mesos
from urllib.request import urlopen


def dcos_slaves():
    client = mesos.DCOSClient()
    slaves = client.get_state_summary()["slaves"]
    return slaves


def dcos_version():
    client = mesos.DCOSClient()
    dcos_url = client.get_dcos_url(path="")
    f = urlopen("%s/dcos-metadata/dcos-version.json" % dcos_url)
    json_response = f.read()
    f.close()
    response = json.loads(json_response)
    return response["version"]


def public_windows_slaves_addresses():
    slaves = dcos_slaves()
    addresses = []
    for slave in slaves:
        if("public_ip" in slave["attributes"].keys() and
           "os" in slave["attributes"].keys() and
           slave["attributes"]["os"] == "Windows"):
            addresses.append(mesos.parse_pid(slave["pid"])[1])
    return addresses


def private_windows_slaves_addresses():
    slaves = dcos_slaves()
    addresses = []
    for slave in slaves:
        if("public_ip" not in slave["attributes"].keys() and
           "os" in slave["attributes"].keys() and
           slave["attributes"]["os"] == "Windows"):
            addresses.append(mesos.parse_pid(slave["pid"])[1])
    return addresses


def public_linux_slaves_addresses():
    slaves = dcos_slaves()
    addresses = []
    for slave in slaves:
        if("public_ip" in slave["attributes"].keys() and
           "os" in slave["attributes"].keys() and
           slave["attributes"]["os"] == "Linux"):
            addresses.append(mesos.parse_pid(slave["pid"])[1])
    return addresses


def private_linux_slaves_addresses():
    slaves = dcos_slaves()
    addresses = []
    for slave in slaves:
        if("public_ip" not in slave["attributes"].keys() and
           "os" in slave["attributes"].keys() and
           slave["attributes"]["os"] == "Linux"):
            addresses.append(mesos.parse_pid(slave["pid"])[1])
    return addresses
