#!/usr/bin/env bash
set -e

if [[ $# -ne 2 ]]; then
    echo "USAGE: $0 <jenkins_username> <jenkins_password>"
    exit 1
fi

DIR=$(dirname $0)
JENKINS_URL="http://localhost:8080"

JENKINS_CLI_URL="$JENKINS_URL/jnlpJars/jenkins-cli.jar"
JENKINS_CLI="/tmp/jenkns-cli.jar"
PLUGINS_GROOVY="/tmp/plugins.groovy"

wget $JENKINS_CLI_URL -O $JENKINS_CLI

cat > $PLUGINS_GROOVY << EOF
def plugins = jenkins.model.Jenkins.instance.getPluginManager().getPlugins()
plugins.each {println "\${it.getShortName()}:\${it.getVersion()}"}
EOF

java -jar $JENKINS_CLI -http -auth "${1}:${2}" -s $JENKINS_URL groovy = < $PLUGINS_GROOVY > $DIR/plugins.txt

rm $JENKINS_CLI $PLUGINS_GROOVY
