#!/bin/bash

function definition_upload() {
  # Create the directory to store the definitions
  mkdir --parents /tmp/clamav/database

  # Pull the latest definitions
  freshclam --no-warnings --user $(id --user) --config-file="${LAMBDA_TASK_ROOT}"/freshclam.conf

  # Archive the definitions
  tar --create --gzip --verbose --file=/tmp/clamav/clamav.tar.gz -C /tmp/clamav/database .

  # Upload the definitions to S3
  aws s3 cp /tmp/clamav/clamav.tar.gz s3://"${CLAMAV_DEFINITON_BUCKET_NAME}"/clamav.tar.gz
}

function definition_download() {
  # Create the directory to store the definitions
  mkdir --parents /tmp/clamav/database

  # Download the definitions from S3
  aws s3 cp s3://"${CLAMAV_DEFINITON_BUCKET_NAME}"/clamav.tar.gz /tmp/clamav/clamav.tar.gz

  # Extract the definitions
  tar --extract --gzip --verbose --file=/tmp/clamav/clamav.tar.gz -C /tmp/clamav/database
}

function scan() {
  EVENT_DATA="${1}"

  objectKey="$(echo "${EVENT_DATA}" | jq -r '.Records[0].s3.object.key')"
  object=$(echo "${objectKey}" | cut -d'/' -f2)

  # Create the directory for running the scan
  mkdir --parents /tmp/clamav/scan

  # Download the file to scan
  aws s3 cp s3://"${LANDING_BUCKET_NAME}"/"${objectKey}" /tmp/clamav/scan/"${object}"

  # Scan the test file
  clamscan --database=/tmp/clamav/database /tmp/clamav/scan/"${object}"

  # Debug: Process clamscan exit code
  if [ $? -eq 0 ]; then
    echo "Scan result: Clean"
    move_to_processed
  else
    echo "Scan result: Infected"
    move_to_quarantine
  fi
}

move_to_processed() {
  # Move the file to the processed bucket
  aws s3 mv s3://"${LANDING_BUCKET_NAME}"/"${objectKey}" s3://"${PROCESSED_BUCKET_NAME}"/"${objectKey}"

  # Tag the file with the scan result
  aws s3api put-object-tagging --bucket "${PROCESSED_BUCKET_NAME}" --key "${objectKey}" --tagging 'TagSet=[{Key=scan-result,Value=clean},{Key=scan-time,Value='"$(date --iso-8601=minutes)"'}]'

  if [ $? -eq 0 ]; then
    echo "Success"
    export RESPONSE="{\"statusCode\": 200, \"body\": \"Complete - Clean\"}"
  else
    echo "Failed"
    RESPONSE="{\"statusCode\": 500, \"body\": \"Failed\"}"
  fi
}

move_to_quarantine() {
  # Move the file to the quarantine bucket
  aws s3 mv s3://"${LANDING_BUCKET_NAME}"/"${objectKey}" s3://"${QUARANTINE_BUCKET_NAME}"/"${objectKey}"

  # Tag the file with the scan result
  aws s3api put-object-tagging --bucket "${QUARANTINE_BUCKET_NAME}" --key "${objectKey}" --tagging 'TagSet=[{Key=scan-result,Value=infected},{Key=scan-time,Value='"$(date --iso-8601=minutes)"'}]'

  if [ $? -eq 0 ]; then
    echo "Success"
    export RESPONSE="{\"statusCode\": 200, \"body\": \"Complete - Infected\"}"
  else
    echo "Failed"
    RESPONSE="{\"statusCode\": 500, \"body\": \"Failed\"}"
  fi
}

function handler() {
  EVENT_DATA="${1}"

  case "${MODE}" in
  definition-upload)
    definition_upload
    ;;
  scan)
    definition_download
    scan "${EVENT_DATA}"
    ;;
  *)
    echo "Invalid mode: ${MODE}"
    exit 1
    ;;
  esac

  echo "${RESPONSE}"
}
