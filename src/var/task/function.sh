#!/bin/bash

function definition_upload() {
  freshclam --no-warnings --config-file=${LAMBDA_TASK_ROOT}/freshclam.conf
  tar --create --gzip --verbose --file=/tmp/clamav/clamav.tar.gz /tmp/clamav/clamav
  aws s3 cp /var/lib/clamav.tar.gz s3://"${CLAMAV_DEFINITON_BUCKET_NAME}"/clamav.tar.gz
}

# TODO: Complete the below
function definition_download() {
  aws s3 cp s3://"${CLAMAV_DEFINITON_BUCKET_NAME}"/clamav.tar.gz /var/lib/clamav.tar.gz
  tar --extract --gzip --verbose --file=/var/lib/clamav.tar.gz /var/lib/clamav
}

# function scan() {

# }

function handler() {
  case "${MODE}" in
  definition-upload )
    definition_upload
    ;;
  scan )
    definition_download
    scan
    ;;
  * )
    echo "Invalid mode: ${MODE}"
    exit 1
    ;;
  esac

  if [ $? -eq 0 ]; then
    echo "Success"
    RESPONSE="{\"statusCode\": 200, \"body\": \"Success\"}"
  else
    echo "Failed"
    RESPONSE="{\"statusCode\": 500, \"body\": \"Failed\"}"
  fi

  echo "${RESPONSE}"
}
