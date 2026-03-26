import boto3
import os
import json
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    request_id = context.aws_request_id
    logger.info(f"request_id={request_id} status=START")

    s3 = boto3.client("s3")
    bucket    = os.environ["BUCKET_NAME"]
    max_size  = int(os.environ["MAX_SIZE_MB"]) * 1024 * 1024
    allowed   = os.environ["ALLOWED_TYPES"].split(",")

    for record in event["Records"]:
        key  = record["s3"]["object"]["key"]
        size = record["s3"]["object"]["size"]
        logger.info(f"request_id={request_id} key={key} size={size}")

        if size > max_size:
            msg = f"REJECT: fichier trop grand ({size} > {max_size} bytes)"
            logger.warning(f"request_id={request_id} key={key} result=REJECTED reason=SIZE")
            _write_result(s3, bucket, key, "REJECTED", msg, request_id)
            continue

        try:
            head = s3.head_object(Bucket=bucket, Key=key)
            content_type = head.get("ContentType", "unknown")
        except Exception as e:
            logger.error(f"request_id={request_id} key={key} error={str(e)}")
            continue

        if content_type not in allowed:
            msg = f"REJECT: type non autorise ({content_type})"
            logger.warning(f"request_id={request_id} key={key} result=REJECTED reason=TYPE")
            _write_result(s3, bucket, key, "REJECTED", msg, request_id)
            continue

        msg = f"ACCEPTED: {key} ({content_type}, {size} bytes)"
        logger.info(f"request_id={request_id} key={key} result=ACCEPTED")
        _write_result(s3, bucket, key, "ACCEPTED", msg, request_id)

    return {"statusCode": 200}


def _write_result(s3, bucket, original_key, status, message, request_id):
    filename   = original_key.replace("input/", "").replace("/", "_")
    output_key = f"output/{filename}.json"

    result = {
        "originalKey": original_key,
        "status":      status,
        "message":     message,
        "requestId":   request_id,
        "processedAt": datetime.utcnow().isoformat()
    }

    s3.put_object(
        Bucket      = bucket,
        Key         = output_key,
        Body        = json.dumps(result, indent=2),
        ContentType = "application/json"
    )
