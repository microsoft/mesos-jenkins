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

import json
import urllib
import urllib2

from datetime import datetime

REVIEWBOARD_URL = "https://reviews.apache.org"


class ReviewError(Exception):
    """Custom exception raised when a review is bad"""
    pass


class ReviewBoardHandler(object):

    def __init__(self, user=None, password=None):
        self.user = user
        self.password = password

    def api(self, url, data=None):
        """Call the ReviewBoard API."""
        try:
            auth_handler = urllib2.HTTPBasicAuthHandler()
            auth_handler.add_password(
                realm="Web API",
                uri="reviews.apache.org",
                user=self.user,
                passwd=self.password)
            opener = urllib2.build_opener(auth_handler)
            urllib2.install_opener(opener)
            return json.loads(urllib2.urlopen(url, data=data).read())
        except urllib2.HTTPError as err:
            print "Error handling URL %s: %s (%s)" % (url,
                                                      err.reason,
                                                      err.read())
            exit(1)
        except urllib2.URLError as err:
            print "Error handling URL %s: %s" % (url, err.reason)
            exit(1)

    def get_review_ids(self, review_request):
        """Returns the review requests' ids (together with any potential
           dependent review requests' ids) that need to be applied for the
           current review request. Their order is ascending with respect to
           how they should be applied. This function raises a ReviewError
           exception if a cyclic dependency is found."""
        review_ids = []
        for review in review_request["depends_on"]:
            review_url = review["href"]
            print "Dependent review: %s " % review_url
            dependent_review = self.api(review_url)["review_request"]
            review_ids += self.get_review_ids(dependent_review)
        if review_request["id"] in review_ids:
            raise ReviewError("Circular dependency detected for "
                              "review %s. Please fix the "
                              "'depends_on' field." % review_request["id"])
        if review_request["status"] != "submitted":
            review_ids.append(review_request["id"])
        else:
            print ("The review request %s is already "
                   "submitted" % (review_request["id"]))
        return review_ids

    def post_review(self, review_request, message, text_type='markdown'):
        """Post a review on the review board."""
        valid_text_types = ['markdown', 'plain']
        if text_type not in valid_text_types:
            raise Exception("Invalid %s text type when trying "
                            "to post review. Valid text "
                            "types are: %s" % (text_type, valid_text_types))
        review_request_url = "%s/r/%s" % (REVIEWBOARD_URL,
                                          review_request['id'])
        print "Posting to review request: %s\n%s" % (review_request_url,
                                                     message)
        review_url = review_request["links"]["reviews"]["href"]
        data = urllib.urlencode({'body_top': message,
                                 'body_top_text_type': text_type,
                                 'public': 'true'})
        self.api(review_url, data)

    def needs_verification(self, review_request):
        """Return True if this review request needs to be verified."""
        print "Checking if review: %s needs verification" % (
            review_request["id"])

        # Now apply this review if not yet submitted.
        if review_request["status"] == "submitted":
            print "The review is already already submitted"
            return False

        # Skip if the review blocks another review.
        if review_request["blocks"]:
            print "Skipping blocking review %s" % review_request["id"]
            return False

        diffs_url = review_request["links"]["diffs"]["href"]
        diffs = self.api(diffs_url)
        if len(diffs["diffs"]) == 0:  # No diffs attached!
            print "Skipping review %s as it has no diffs" % (
                review_request["id"])
            return False

        # Get the timestamp of the latest diff.
        timestamp = diffs["diffs"][-1]["timestamp"]
        rb_date_format = "%Y-%m-%dT%H:%M:%SZ"
        diff_time = datetime.strptime(timestamp, rb_date_format)
        print "Latest diff timestamp: %s" % diff_time

        # Get the timestamp of the latest review from this script.
        reviews_url = review_request["links"]["reviews"]["href"]
        reviews = self.api(reviews_url + "?max-results=200")
        review_time = None
        for review in reversed(reviews["reviews"]):
            if review["links"]["user"]["title"] == self.user:
                timestamp = review["timestamp"]
                review_time = datetime.strptime(timestamp, rb_date_format)
                print "Latest review timestamp: %s" % review_time
                break

        # TODO: Apply this check recursively up the dependency chain.
        changes_url = review_request["links"]["changes"]["href"]
        changes = self.api(changes_url)
        dependency_time = None
        for change in changes["changes"]:
            if "depends_on" in change["fields_changed"]:
                timestamp = change["timestamp"]
                dependency_time = datetime.strptime(timestamp, rb_date_format)
                print "Latest dependency change timestamp: %s" % (
                    dependency_time)
                break

        # Needs verification if there is a new diff, or if the
        # dependencies changed, after the last time it was verified.
        return (not review_time or review_time < diff_time or
                (dependency_time and review_time < dependency_time))


class GearmanClient(object):

    def __init__(self, servers, jobs):
        self.servers = servers
        self.jobs = jobs

    def check_gearman_request_status(self, job_request):
        import gearman
        if job_request.complete:
            print "Job %s finished!\n%s" % (job_request.job.unique,
                                            job_request.result)
        elif job_request.timed_out:
            print "Job %s timed out!" % job_request.job.unique
        elif job_request.state == gearman.JOB_UNKNOWN:
            print "Job %s connection failed!" % job_request.unique

    def trigger_gearman_jobs(self):
        import gearman
        if len(self.servers) == 0:
            raise Exception("No gearman servers to trigger the jobs")
        print "Using the following Gearman servers: %s" % self.servers
        client = gearman.GearmanClient(self.servers)
        print "Triggered all the jobs and waiting them to finish"
        completed_job_requests = client.submit_multiple_jobs(
            jobs_to_submit=self.jobs, wait_until_complete=True,
            max_retries=0, poll_timeout=None)
        for job_request in completed_job_requests:
            self.check_gearman_request_status(job_request)
