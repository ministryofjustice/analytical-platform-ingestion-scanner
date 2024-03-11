import json
import os
import subprocess
from datetime import datetime

import boto3
import botocore.exceptions

s3_client = boto3.client("s3")


def run_command(command):
    result = subprocess.run(
        command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    return (
        result.returncode,
        result.stdout.decode("utf-8"),
        result.stderr.decode("utf-8"),
    )


def definition_upload():
    try:
        # Create the directory to store the definitions
        os.makedirs("/tmp/clamav/database", exist_ok=True)

        # Pull the latest definitions
        user_id = run_command("id --user")[1].strip()
        clamav_config = os.environ.get("LAMBDA_TASK_ROOT", "") + "/freshclam.conf"
        run_command(
            f'freshclam --no-warnings --user {user_id} --config-file="{clamav_config}"'
        )

        # Archive the definitions
        run_command(
            "tar --create --gzip --verbose --file=/tmp/clamav/clamav.tar.gz -C /tmp/clamav/database ."
        )

        # Upload the definitions to S3
        bucket_name = os.environ.get("CLAMAV_DEFINITON_BUCKET_NAME")
        if not bucket_name:
            raise ValueError(
                "CLAMAV_DEFINITON_BUCKET_NAME environment variable not set."
            )
        s3_client.upload_file("/tmp/clamav/clamav.tar.gz", bucket_name, "clamav.tar.gz")
    except botocore.exceptions.ClientError as e:
        print(f"Failed to upload ClamAV definitions: {e}")


def definition_download():
    try:
        # Create the directory to store the definitions
        os.makedirs("/tmp/clamav/database", exist_ok=True)

        # Download the definitions from S3
        bucket_name = os.environ.get("CLAMAV_DEFINITON_BUCKET_NAME")
        if not bucket_name:
            raise ValueError(
                "CLAMAV_DEFINITON_BUCKET_NAME environment variable not set."
            )
        s3_client.download_file(
            bucket_name, "clamav.tar.gz", "/tmp/clamav/clamav.tar.gz"
        )
        print("Successfully downloaded ClamAV definitions from S3.")

        # Extract the definitions
        run_command(
            "tar --extract --gzip --verbose --file=/tmp/clamav/clamav.tar.gz -C /tmp/clamav/database"
        )
        print("Successfully extracted ClamAV definitions.")
    except botocore.exceptions.ClientError as e:
        print(f"Failed to download or extract ClamAV definitions: {e}")


def scan(event):
    # event_json = json.loads(event_data)
    object_key = event["Records"][0]["s3"]["object"]["key"]
    object_name = object_key.split("/")[-1]

    # Create the directory for running the scan
    os.makedirs("/tmp/clamav/scan", exist_ok=True)

    # Download the file to scan
    landing_bucket_name = os.environ.get("LANDING_BUCKET_NAME")
    if not landing_bucket_name:
        raise ValueError("LANDING_BUCKET_NAME environment variable not set.")
    s3_client.download_file(
        landing_bucket_name, object_key, f"/tmp/clamav/scan/{object_name}"
    )

    # Scan the test file
    exit_code, stdout, _ = run_command(
        f"clamscan --database=/tmp/clamav/database /tmp/clamav/scan/{object_name}"
    )
    print(stdout)
    if exit_code == 0:
        print("Scan result: Clean")
        move_to_processed(object_key)
    else:
        print("Scan result: Infected")
        move_to_quarantine(object_key)


def move_to_processed(object_key):
    try:
        processed_bucket_name = os.environ.get("PROCESSED_BUCKET_NAME")
        if not processed_bucket_name:
            raise ValueError("PROCESSED_BUCKET_NAME environment variable not set.")
        # Move the file to the processed bucket
        copy_source = {"Bucket": os.environ["LANDING_BUCKET_NAME"], "Key": object_key}
        s3_client.copy_object(
            Bucket=processed_bucket_name, CopySource=copy_source, Key=object_key
        )
        s3_client.delete_object(
            Bucket=os.environ["LANDING_BUCKET_NAME"], Key=object_key
        )

        # Tag the file with the scan result
        s3_client.put_object_tagging(
            Bucket=processed_bucket_name,
            Key=object_key,
            Tagging={
                "TagSet": [
                    {"Key": "scan-result", "Value": "clean"},
                    {"Key": "scan-time", "Value": datetime.now().isoformat()},
                ]
            },
        )
        print("File moved to processed and tagged")
    except botocore.exceptions.ClientError as e:
        print(f"Failed to move file to processed: {e}")


def move_to_quarantine(object_key):
    try:
        quarantine_bucket_name = os.environ.get("QUARANTINE_BUCKET_NAME")
        if not quarantine_bucket_name:
            raise ValueError("QUARANTINE_BUCKET_NAME environment variable not set.")
        # Move the file to the quarantine bucket
        copy_source = {"Bucket": os.environ["LANDING_BUCKET_NAME"], "Key": object_key}
        s3_client.copy_object(
            Bucket=quarantine_bucket_name, CopySource=copy_source, Key=object_key
        )
        s3_client.delete_object(
            Bucket=os.environ["LANDING_BUCKET_NAME"], Key=object_key
        )

        # Tag the file with the scan result
        s3_client.put_object_tagging(
            Bucket=quarantine_bucket_name,
            Key=object_key,
            Tagging={
                "TagSet": [
                    {"Key": "scan-result", "Value": "infected"},
                    {"Key": "scan-time", "Value": datetime.now().isoformat()},
                ]
            },
        )
        print("File moved to quarantine and tagged")
    except botocore.exceptions.ClientError as e:
        print(f"Failed to move file to quarantine: {e}")


def handler(event, context):
    print("Received event:", event)
    try:
        mode = os.environ.get("MODE")
        if mode == "definition-upload":
            definition_upload()
        elif mode == "scan":
            definition_download()
            scan(event)
        else:
            raise ValueError(f"Invalid mode: {mode}")
    except Exception as e:
        print(f"Error: {e}")
        return {"statusCode": 500, "body": json.dumps({"message": "Error occurred"})}
    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Operation completed successfully"}),
    }
