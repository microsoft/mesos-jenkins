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

"""
This script is used to verify reviews that are posted to ReviewBoard.
The script is intended for use by automated "ReviewBots".

The script performs the following sequence:
* A query grabs review IDs from Reviewboard.
* In reverse order (most recent first), the script determines if the
  review needs verification (if the review has been updated or changed
  since the last run through this script).
* An output list of review IDs that need verification is written to the
  '--out-file'.
"""

import argparse
import json
import urllib
import urllib2

from datetime import datetime

parser = argparse.ArgumentParser(
    description="Verify reviews from the Review Board")
parser.add_argument("-u", "--user", type=str, required=True,
                    help="Review Board user name")
parser.add_argument("-p", "--password", type=str, required=True,
                    help="Review Board user password")
parser.add_argument("-o", "--out-file", type=str, required=True,
                    help="The out file with the reviews IDs that "
                         "need verification")
parser.add_argument("-r", "--reviews", type=int, required=False, default=-1,
                    help="The number of reviews to fetch, that need "
                         "verification")
parser.add_argument("-q", "--query", type=str, required=False,
                    help="Query parameters",
                    default="?to-groups=mesos&status=pending&"
                            "last-updated-from=2017-01-01T00:00:00")
parameters = parser.parse_args()


REVIEWBOARD_URL = "https://reviews.apache.org"


class ReviewError(Exception):
    """Custom exception raised when a review is bad"""
    pass


def api(url, data=None):
    """Call the ReviewBoard API."""
    try:
        auth_handler = urllib2.HTTPBasicAuthHandler()
        auth_handler.add_password(
            realm="Web API",
            uri="reviews.apache.org",
            user=parameters.user,
            passwd=parameters.password)

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
    dependent reviews. The function raises an exception if a cyclic dependency
    is found"""

    reviews_id = [review_request["id"]]
    for review in review_request["depends_on"]:
        review_url = review["href"]
        print "Dependent review: %s " % review_url
        dependent_review = api(review_url)["review_request"]
        # First recursively all the dependent reviews.
        if dependent_review["id"] in reviews_id:
            raise ReviewError("Circular dependency detected for review %s."
                              "Please fix the 'depends_on' field."
                              % review_request["id"])
        reviews_id += get_review_ids(dependent_review)

    return reviews_id


def post_review(review_request, message):
    """Post a review on the review board."""
    review_request_url = "%s/r/%s" % (REVIEWBOARD_URL, review_request['id'])
    print "Posting to review request: %s\n%s" % (review_request_url, message)

    review_url = review_request["links"]["reviews"]["href"]
    data = urllib.urlencode({'body_top': message, 'public': 'true'})
    api(review_url, data)


def needs_verification(review_request):
    """Return True if this review request needs to be verified."""
    print "Checking if review: %s needs verification" % review_request["id"]

    # Now apply this review if not yet submitted.
    if review_request["status"] == "submitted":
        print "The review is already already submitted"
        return False

    # Skip if the review blocks another review.
    if review_request["blocks"]:
        print "Skipping blocking review %s" % review_request["id"]
        return False

    diffs_url = review_request["links"]["diffs"]["href"]
    diffs = api(diffs_url)
    if len(diffs["diffs"]) == 0:  # No diffs attached!
        print "Skipping review %s as it has no diffs" % review_request["id"]
        return False

    # Get the timestamp of the latest diff.
    timestamp = diffs["diffs"][-1]["timestamp"]
    rb_date_format = "%Y-%m-%dT%H:%M:%SZ"
    diff_time = datetime.strptime(timestamp, rb_date_format)
    print "Latest diff timestamp: %s" % diff_time

    # Get the timestamp of the latest review from this script.
    reviews_url = review_request["links"]["reviews"]["href"]
    reviews = api(reviews_url + "?max-results=200")
    review_time = None
    for review in reversed(reviews["reviews"]):
        if review["links"]["user"]["title"] == parameters.user:
            timestamp = review["timestamp"]
            review_time = datetime.strptime(timestamp, rb_date_format)
            print "Latest review timestamp: %s" % review_time
            break

    # TODO: Apply this check recursively up the dependency chain.
    changes_url = review_request["links"]["changes"]["href"]
    changes = api(changes_url)
    dependency_time = None
    for change in changes["changes"]:
        if "depends_on" in change["fields_changed"]:
            timestamp = change["timestamp"]
            dependency_time = datetime.strptime(timestamp, rb_date_format)
            print "Latest dependency change timestamp: %s" % dependency_time
            break

    # Needs verification if there is a new diff, or if the
    # dependencies changed, after the last time it was verified.
    return (not review_time or review_time < diff_time or
            (dependency_time and review_time < dependency_time))


def main():
    """Main function to verify the submitted reviews."""
    review_requests_url = "%s/api/review-requests/%s" % (REVIEWBOARD_URL,
                                                         parameters.query)

    review_requests = api(review_requests_url)
    num_reviews = 0
    review_ids = []
    for review_request in reversed(review_requests["review_requests"]):
        if ((parameters.reviews == -1 or num_reviews < parameters.reviews) and
           needs_verification(review_request)):
            try:
                # If there are no reviewers specified throw an error.
                if not review_request["target_people"]:
                    raise ReviewError("No reviewers specified. Please find "
                                      "a reviewer by asking on JIRA or the "
                                      "mailing list.")
                # An exception is raised if cyclic dependencies are found
                get_review_ids(review_request)
            except ReviewError as err:
                message = ("Bad review!\n\n"
                           "Error:\n%s" % (err.args[0]))
                post_review(review_request, message)
                continue
            review_ids.append(str(review_request["id"]))
            num_reviews += 1

    with open(parameters.out_file, 'w') as f:
        f.write('\n'.join(review_ids))


if __name__ == '__main__':
    main()
