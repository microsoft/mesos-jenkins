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
import urllib2

parser = argparse.ArgumentParser(description="Get all dependent review IDs")
parser.add_argument("-r", "--review-id", type=str, required=True,
                    help="Review ID")
parser.add_argument("-o", "--out-file", type=str, required=True,
                    help="The out file with the reviews IDs")
parameters = parser.parse_args()


REVIEWBOARD_URL = "https://reviews.apache.org"


class ReviewError(Exception):
    """Custom exception raised when a review is bad"""
    pass


def api(url, data=None):
    """Call the ReviewBoard API."""
    try:
        auth_handler = urllib2.HTTPBasicAuthHandler()

        opener = urllib2.build_opener(auth_handler)
        urllib2.install_opener(opener)

        return json.loads(urllib2.urlopen(url, data=data).read())
    except urllib2.HTTPError as err:
        print "Error handling URL %s: %s (%s)" % (url, err.reason, err.read())
        exit(1)
    except urllib2.URLError as err:
        print "Error handling URL %s: %s" % (url, err.reason)
        exit(1)


def get_review_ids(review_request):
    """Get the review id(s) for the current review request and any potential
    dependent reviews."""

    review_ids = [review_request["id"]]
    for review in review_request["depends_on"]:
        review_url = review["href"]
        print "Dependent review: %s " % review_url
        dependent_review = api(review_url)["review_request"]
        # First recursively all the dependent reviews.
        if dependent_review["id"] in review_ids:
            raise ReviewError("Circular dependency detected for review %s. "
                              "Please fix the 'depends_on' field."
                              % review_request["id"])
        review_ids += get_review_ids(dependent_review)

    return review_ids


def main():
    review_request_url = \
        "%s/api/review-requests/%s/" % (REVIEWBOARD_URL, parameters.review_id)

    review_request = api(review_request_url)["review_request"]
    review_ids = get_review_ids(review_request)

    with open(parameters.out_file, 'w') as f:
        for r_id in list(reversed(review_ids)):
            f.write("%s\n" % (str(r_id)))


if __name__ == '__main__':
    main()
