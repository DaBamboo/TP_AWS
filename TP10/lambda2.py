import boto3, json, os, logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
dynamodb = boto3.resource("dynamodb")

def handler(event, context):
    request_id  = context.aws_request_id
    table       = dynamodb.Table(os.environ["TABLE_NAME"])
    force_error = os.environ.get("FORCE_ERROR", "false").lower() == "true"

    for record in event["Records"]:
        body = json.loads(record["body"])
        logger.info(f"request_id={request_id} processing item_id={body['id']}")

        if force_error:
            logger.error(f"request_id={request_id} FORCE_ERROR actif → DLQ")
            raise Exception("Erreur simulee pour test DLQ")

        table.put_item(Item=body)
        logger.info(f"request_id={request_id} item_id={body['id']} status=PERSISTED")