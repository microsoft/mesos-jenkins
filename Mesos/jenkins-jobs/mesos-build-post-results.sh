#!/usr/bin/env bash
set -e

if [[ -z $USER ]]; then echo "ERROR: No USER parameter was given" ; exit 1 ; fi
if [[ -z $PASSWORD ]]; then echo "ERROR: No PASSWORD parameter was given" ; exit 1 ; fi
if [[ -z $REVIEW_ID ]]; then echo "ERROR: No REVIEW_ID received from the upstream job" ; exit 1 ; fi
if [[ -z $STATUS ]]; then echo "ERROR: No STATUS received from the upstream job" ; exit 1 ; fi
if [[ -z $MESSAGE ]]; then echo "ERROR: No MESSAGE received from the upstream job" ; exit 1 ; fi
if [[ -z $BUILD_OUTPUTS_URL ]]; then echo "ERROR: No BUILD_OUTPUTS_URL received from the upstream job" ; exit 1 ; fi

DIR=$(dirname $0)
$DIR/../utils/post-build-result.py -u "$USER" -p "$PASSWORD" -r "$REVIEW_ID" -m "${STATUS}: ${MESSAGE}" -o "$BUILD_OUTPUTS_URL" \
                                                             -l "$LOGS_URLS" --applied-reviews "$APPLIED_REVIEWS" --failed-command "$FAILED_COMMAND"
