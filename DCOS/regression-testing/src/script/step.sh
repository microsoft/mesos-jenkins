#!/usr/bin/env bash

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

###############################################################################

set -e
set -u
set -o pipefail

source "${DIR}/common.sh"

ROOT="${DIR}/.."

case $1 in

set_azure_account)
  set_azure_account
;;

get_secrets)
  get_secrets
;;

create_resource_group)
  create_resource_group
;;

predeploy)
  ACSE_PREDEPLOY=${ACSE_PREDEPLOY:-}
  if [ ! -z "${ACSE_PREDEPLOY}" ] && [ -x "${ACSE_PREDEPLOY}" ]; then
    "${ACSE_PREDEPLOY}"
  fi
;;

postdeploy)
  ACSE_POSTDEPLOY=${ACSE_POSTDEPLOY:-}
  if [ ! -z "${ACSE_POSTDEPLOY}" ] && [ -x "${ACSE_POSTDEPLOY}" ]; then
    export OUTPUT=${OUTPUT:-"${ROOT}/_output/${INSTANCE_NAME}"}
    "${ACSE_POSTDEPLOY}"
  fi
;;

generate_template)
  export OUTPUT="${ROOT}/_output/${INSTANCE_NAME}"
  generate_template
;;

deploy_template)
  export OUTPUT="${ROOT}/_output/${INSTANCE_NAME}"
  deploy_template
;;

get_node_count)
  export OUTPUT="${ROOT}/_output/${INSTANCE_NAME}"
  get_node_count
;;

get_orchestrator_type)
  get_orchestrator_type
;;

get_orchestrator_version)
  export OUTPUT="${ROOT}/_output/${INSTANCE_NAME}"
  get_orchestrator_version
;;

get_name_suffix)
  export OUTPUT="${ROOT}/_output/${INSTANCE_NAME}"
  get_name_suffix
;;

validate)
  export OUTPUT=${OUTPUT:-"${ROOT}/_output/${INSTANCE_NAME}"}
  set +e
  validate
;;

cleanup)
  export CLEANUP="${CLEANUP:-true}"
  cleanup
;;

*)
  echo "unsupported command $1"
  exit 1
;;
esac
