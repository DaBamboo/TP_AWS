import boto3, json, os, logging, uuid
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)
sqs = boto3.client("sqs")

def handler(event, context):
    request_id = context.aws_request_id

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return {"statusCode": 400, "body": json.dumps({"error": "JSON invalide"})}

    if "name" not in body or "value" not in body:
        logger.warning(f"request_id={request_id} error=VALIDATION_FAILED")
        return {"statusCode": 400, "body": json.dumps({"error": "Champs 'name' et 'value' requis"})}

    item_id = str(uuid.uuid4())
    message = {
        "id":        item_id,
        "name":      body["name"],
        "value":     body["value"],
        "createdAt": datetime.utcnow().isoformat()
    }

    sqs.send_message(QueueUrl=os.environ["QUEUE_URL"], MessageBody=json.dumps(message))
    logger.info(f"request_id={request_id} item_id={item_id} status=SENT_TO_SQS")

    return {"statusCode": 202, "body": json.dumps({"id": item_id, "status": "queued"})}