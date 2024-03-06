#!/bin/bash

function definition_upload() {
  # Pull the latest definitions
  freshclam --no-warnings --config-file="${LAMBDA_TASK_ROOT}"/freshclam.conf

  # Archive the definitions
  tar --create --gzip --verbose --file=/tmp/clamav/clamav.tar.gz /tmp/clamav/

  # Upload the definitions to S3
  aws s3 cp /tmp/clamav/clamav.tar.gz s3://"${CLAMAV_DEFINITON_BUCKET_NAME}"/clamav.tar.gz
}

# TODO: Complete the below
function definition_download() {
  # Download the definitions from S3
  aws s3 cp s3://"${CLAMAV_DEFINITON_BUCKET_NAME}"/clamav.tar.gz /tmp/clamav/clamav.tar.gz

  # Extract the definitions
  tar --extract --gzip --verbose --file=/tmp/clamav/clamav.tar.gz /tmp/clamav/
}

# function scan() {}

function handler() {
  case "${MODE}" in
  definition-upload)
    definition_upload
    ;;
  scan)
    definition_download
    scan
    ;;
  *)
    echo "Invalid mode: ${MODE}"
    exit 1
    ;;
  esac

  # TODO: Implement proper response
  if [ $? -eq 0 ]; then
    echo "Success"
    RESPONSE="{\"statusCode\": 200, \"body\": \"Success\"}"
  else
    echo "Failed"
    RESPONSE="{\"statusCode\": 500, \"body\": \"Failed\"}"
  fi

  echo "${RESPONSE}"
}
