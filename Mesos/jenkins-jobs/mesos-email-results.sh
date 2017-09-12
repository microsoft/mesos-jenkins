#!/usr/bin/env bash
set -e

if [[ -z $STATUS ]]; then echo "ERROR: No STATUS received from the upstream job"; exit 1; fi
if [[ -z $MESSAGE ]]; then echo "ERROR: No MESSAGE received from the upstream job"; exit 1; fi
if [[ -z $BRANCH ]]; then echo "ERROR: No BRANCH received from the upstream job"; exit 1; fi
if [[ -z $BUILD_OUTPUTS_URL ]]; then echo "ERROR: No BUILD_OUTPUTS_URL received from the upstream job"; exit 1; fi
if [[ -z $PARAMETERS_FILE_PATH ]]; then echo "ERROR: Environment variable PARAMETERS_FILE_PATH was not set"; exit 1; fi

LOG_TAIL_LIMIT=30

TEMP_DIR=$(mktemp -d)
HTML_LOGS="$TEMP_DIR/html_logs"
touch $HTML_LOGS
if [[ ! -z $LOGS_URLS ]]; then
    for URL in $(echo $LOGS_URLS | tr '|' '\n'); do
        LOG_NAME=$(basename $URL)
        LOG_FILE="$TEMP_DIR/$LOG_NAME"
        wget $URL -O $LOG_FILE
        if [[ "$(cat $LOG_FILE)" = "" ]]; then
            rm -rf $LOG_FILE
            continue
        fi
        HTML_LOG="$TEMP_DIR/html_log"
        touch $HTML_LOG
        tail -n $LOG_TAIL_LIMIT $LOG_FILE | while read LINE; do
            SANITIZED_LINE=$(echo -n $LINE | tr -d '\r\n') # Remove '\r' and '\n' characters
            echo -n "${SANITIZED_LINE}<br/>" >> $HTML_LOG
        done
        echo -n "<li><a href=\"$URL\">$LOG_NAME</a>:</li><br/>" >> $HTML_LOGS
        echo -n "<pre>$(cat $HTML_LOG)</pre>" >> $HTML_LOGS
        rm -rf $HTML_LOG
        rm -rf $LOG_FILE
    done
fi

HTML_CONTENT="Nightly build status: $STATUS<br/><br/>$MESSAGE<br/><br/>"
if [[ "$FAILED_COMMAND" != "" ]]; then
    FAILED_COMMAND=$(echo -n "$FAILED_COMMAND" | sed 's|\\|\\\\|g') # Escape any single black-slashes
    HTML_CONTENT="${HTML_CONTENT}Failed command: <code>$FAILED_COMMAND</code><br/><br/>"
fi
HTML_CONTENT="${HTML_CONTENT}All the Jenkins build artifacts available at: <a href=\"$BUILD_OUTPUTS_URL\">$BUILD_OUTPUTS_URL</a><br/><br/>"
if [[ "$(cat $HTML_LOGS)" != "" ]]; then
    HTML_CONTENT="${HTML_CONTENT}Relevant logs:<br/><ul>$(cat $HTML_LOGS)</ul>"
fi

rm -rf $TEMP_DIR

echo "EMAIL_HTML_CONTENT=$HTML_CONTENT" > $PARAMETERS_FILE_PATH
echo "EMAIL_TITLE=[mesos-nightly-build] ${STATUS}: mesos ${BRANCH} branch" >> $PARAMETERS_FILE_PATH
