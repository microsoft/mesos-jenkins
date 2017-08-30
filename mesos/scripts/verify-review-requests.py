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

sys.path.append(os.getcwd())

from common import ReviewBoardHandler, ReviewError, REVIEWBOARD_URL # noqa

DEFAULT_GEARMAN_PORT = 4730


def parse_parameters():
    parser = argparse.ArgumentParser(
        description="Verify reviews from the Review Board")
    parser.add_argument("-u", "--user", type=str, required=True,
                        help="Review Board user name")
    parser.add_argument("-p", "--password", type=str, required=True,
                        help="Review Board user password")
    parser.add_argument("-r", "--reviews", type=int, required=False,
                        default=-1, help="The number of reviews to fetch, "              
                                         "that will need verification")
    parser.add_argument("-q", "--query", type=str, required=False,
                        help="Query parameters",
                        default="?to-groups=mesos&status=pending&"
                                "last-updated-from=2017-01-01T00:00:00")

    subparsers = parser.add_subparsers(title="The script plug-in type")

    file_parser = subparsers.add_parser(
        "file", description="File plug-in just writes to a file all "
                            "the review ids that need verification")
    file_parser.add_argument("-o", "--out-file", type=str, required=True,
                             help="The out file with the reviews IDs that "
                                  "need verification")

    gearman_parser = subparsers.add_parser(
        "gearman", description="Gearman plug-in is used to connect to "
                               "a gearman server to trigger jobs to "
                               "registered Jenkins servers")
    gearman_parser.add_argument("-s", "--servers", type=str, required=False,
                                default="127.0.0.1",
                                help="The gearman servers' addresses")
    gearman_parser.add_argument("-j", "--job", type=str, required=True,
                                help="The Jenkins build job name")
    gearman_parser.add_argument("--params",
                                type=str, required=False, default=None,
                                help="Extra parameters to pass to every build "
                                     "(must be given as JSON encoded string)")

    return parser.parse_args()


def check_gearman_request_status(job_request):
    import gearman
    if job_request.complete:
        print "Job %s finished!\n%s" % (job_request.job.unique,
                                        job_request.result)
    elif job_request.timed_out:
        print "Job %s timed out!" % job_request.job.unique
    elif job_request.state == gearman.JOB_UNKNOWN:
        print "Job %s connection failed!" % job_request.unique


def trigger_gearman_jobs(review_ids, job_name, german_servers, params=None):
    import gearman
    if len(review_ids) == 0:
        # We don't need to trigger any jobs
        return
    if len(german_servers) == 0:
        raise Exception("No gearman servers to trigger the jobs")
    task_name = "build:%s" % job_name
    jobs = []
    for review_id in review_ids:
        print "Preparing build job with review id: %s" % review_id
        job_id = uuid.uuid4().hex
        job_params = {
            "commitid": review_id,
            "OFFLINE_NODE_WHEN_COMPLETE": "false"
        }
        if params is not None:
            job_params.update(json.loads(params))
        jobs.append(dict(
            unique=job_id,
            task=task_name,
            data=json.dumps(job_params)
        ))
    print "Using the following Gearman servers: %s" % german_servers
    client = gearman.GearmanClient(german_servers)
    print "Triggered all the jobs and waiting them to finish"
    completed_job_requests = client.submit_multiple_jobs(
        jobs_to_submit=jobs, wait_until_complete=True,
        max_retries=0, poll_timeout=None)
    for job_request in completed_job_requests:
        check_gearman_request_status(job_request)


def verify_reviews(review_ids, parameters):
    nr_reviews = len(review_ids)
    print "There are %s review requests that need verification" % nr_reviews

    if hasattr(parameters, 'out_file'):
        # Using file plug-in
        with open(parameters.out_file, 'w') as f:
            f.write('\n'.join(review_ids))
        return

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

    # Using Gearman plug-in
    trigger_gearman_jobs(review_ids=review_ids, job_name=parameters.job,
                         german_servers=servers, params=parameters.params)


def main():
    """Main function to verify the submitted reviews."""
    parameters = parse_parameters()
    review_requests_url = "%s/api/review-requests/%s" % (REVIEWBOARD_URL,
                                                         parameters.query)
    handler = ReviewBoardHandler(parameters.user, parameters.password)
    num_reviews = 0
    review_ids = []
    review_requests = handler.api(review_requests_url)
    for review_request in reversed(review_requests["review_requests"]):
        if ((parameters.reviews == -1 or num_reviews < parameters.reviews) and
           handler.needs_verification(review_request)):
            try:
                # If there are no reviewers specified throw an error.
                if not review_request["target_people"]:
                    raise ReviewError("No reviewers specified. Please find "
                                      "a reviewer by asking on JIRA or the "
                                      "mailing list.")
                # An exception is raised if cyclic dependencies are found
                handler.get_review_ids(review_request)
            except ReviewError as err:
                message = ("Bad review!\n\n"
                           "Error:\n%s" % (err.args[0]))
                handler.post_review(review_request, message)
                continue
            review_ids.append(str(review_request["id"]))
            num_reviews += 1
    verify_reviews(review_ids, parameters)


if __name__ == '__main__':
    main()
