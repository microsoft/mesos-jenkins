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
import os
import sys

sys.path.append(os.getcwd())

from common import ReviewBoardHandler, ReviewError, REVIEWBOARD_URL # noqa


def parse_parameters():
    parser = argparse.ArgumentParser(
        description="Post review results to Review Board")
    parser.add_argument("-u", "--user", type=str, required=True,
                        help="Review board user name")
    parser.add_argument("-p", "--password", type=str, required=True,
                        help="Review board user password")
    parser.add_argument("-r", "--review-id", type=str, required=True,
                        help="Review ID")
    parser.add_argument("-m", "--message", type=str, required=True,
                        help="The post message")
    parser.add_argument("-l", "--logs-url", type=str, required=True,
                        help="The URL with the available logs")
    return parser.parse_args()


def main():
    parameters = parse_parameters()
    review_request_url = "%s/api/review-requests/%s/" % (REVIEWBOARD_URL,
                                                         parameters.review_id)
    handler = ReviewBoardHandler(parameters.user, parameters.password)
    review_request = handler.api(review_request_url)["review_request"]
    try:
        review_ids = handler.get_review_ids(review_request)
        message = ("%s\n\n"
                   "Reviews applied: %s\n\n"
                   "Logs available here: %s") % (parameters.message,
                                                 list(reversed(review_ids)),
                                                 parameters.logs_url)
    except ReviewError as err:
        message = ("Bad review!\n\n"
                   "Error:\n%s" % (err.args[0]))
    handler.post_review(review_request, message)


if __name__ == '__main__':
    main()