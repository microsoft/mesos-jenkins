#!/usr/bin/env python
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import json
import os
import sys
import uuid
import time

sys.path.append(os.getcwd())

from common import GearmanClient # noqa

DEFAULT_GEARMAN_PORT = 4730


def parse_parameters():
    parser = argparse.ArgumentParser(
        description="Trigger a Gearman job on multiple Gearman Servers")
    parser.add_argument("-s", "--servers", type=str, required=False,
                        default="127.0.0.1",
                        help="The gearman servers' addresses")
    parser.add_argument("-j", "--job", type=str, required=True,
                        help="The Jenkins build job name")
    parser.add_argument("--params", type=str, required=False, default=None,
                        help="Extra parameters to pass to every build "
                             "(must be given as JSON encoded string)")

    return parser.parse_args()


def main():
    """Main function to verify the submitted reviews."""
    parameters = parse_parameters()
    print "\n%s - Running %s" % (time.strftime('%m-%d-%y_%T'),
                                 os.path.abspath(__file__))
    servers = []
    for server in parameters.servers.split(","):
        server = server.strip()
        s_split = server.split(":")
        address = s_split[0]
        if len(s_split) == 2:
            port = s_split[1]
        else:
            port = DEFAULT_GEARMAN_PORT
        servers.append("%s:%s" % (address, port))
    job_params = {
        "OFFLINE_NODE_WHEN_COMPLETE": "false"
    }
    if parameters.params is not None:
        job_params.update(json.loads(parameters.params))
    print "Triggering %s" % (parameters.job)
    task_name = "build:%s" % parameters.job
    jobs = [dict(unique=uuid.uuid4().hex,
                 task=task_name,
                 data=json.dumps(job_params))]
    client = GearmanClient(servers=servers, jobs=jobs)
    client.trigger_gearman_jobs()


if __name__ == '__main__':
    main()
