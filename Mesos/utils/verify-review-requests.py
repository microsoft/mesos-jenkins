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
import time
import datetime
from urllib.parse import urlencode

from common import ReviewBoardHandler, ReviewError, REVIEWBOARD_URL  # noqa

MESOS_REPOSITORY_ID = 122


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
    default_hours_behind = 8
    datetime_before = (datetime.datetime.now() -
                       datetime.timedelta(hours=default_hours_behind))
    datetime_before_string = datetime_before.isoformat()
    default_query = {"status": "pending",
                     "repository": MESOS_REPOSITORY_ID}
    default_query["last-updated-from"] = datetime_before_string.split(".")[0]
    parser.add_argument("-q", "--query", type=str, required=False,
                        help="Query parameters, passed as string in JSON "
                             "format. Example: '%s'" % json.dumps(
                                 default_query),
                        default=json.dumps(default_query))

    subparsers = parser.add_subparsers(title="The script plug-in type")

    file_parser = subparsers.add_parser(
        "file", description="File plug-in just writes to a file all "
                            "the review ids that need verification")
    file_parser.add_argument("-o", "--out-file", type=str, required=True,
                             help="The out file with the reviews IDs that "
                                  "need verification")

    return parser.parse_args()


def verify_reviews(review_ids, parameters):
    nr_reviews = len(review_ids)
    print("There are %s review requests that need verification" % nr_reviews)
    # out_file parameter is mandatory to be passed
    try:
        # Using file plug-in
        with open(parameters.out_file, 'w') as f:
            f.write('\n'.join(review_ids))
    except Exception:
        print("Failed opening file '%s' for writing" % parameters.out_file)
        raise


def main():
    """Main function to verify the submitted reviews."""
    parameters = parse_parameters()
    print("\n%s - Running %s" % (time.strftime('%m-%d-%y_%T'),
                                 os.path.abspath(__file__)))
    # The colon from timestamp gets encoded and we don't want it to be encoded.
    # Replacing %3A with colon.
    query_string = urlencode(json.loads(parameters.query)).replace("%3A", ":")
    review_requests_url = "%s/api/review-requests/?%s" % (REVIEWBOARD_URL,
                                                          query_string)
    handler = ReviewBoardHandler(parameters.user, parameters.password)
    num_reviews = 0
    review_ids = []
    review_requests = handler.api(review_requests_url)
    for review_request in reversed(review_requests["review_requests"]):
        if (parameters.reviews == -1 or num_reviews < parameters.reviews):
            try:
                needs_verification = handler.needs_verification(review_request)
                if not needs_verification:
                    continue
                # An exception is raised if cyclic dependencies are found
                handler.get_review_ids(review_request)
            except ReviewError as err:
                message = ("Bad review!\n\n"
                           "Error:\n%s" % (err.args[0]))
                handler.post_review(review_request, message)
                continue
            except Exception as err:
                print("Error occured: %s" % err)
                needs_verification = False
                print("WARNING: Cannot find if review %s needs "
                      "verification" % (review_request["id"]))
            if not needs_verification:
                continue
            review_ids.append(str(review_request["id"]))
            num_reviews += 1
    verify_reviews(review_ids, parameters)


if __name__ == '__main__':
    main()
