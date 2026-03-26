import boto3, json, os, logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    request_id  = context.aws_request_id
    secret_name = os.environ["SECRET_NAME"]
    client      = boto3.client("secretsmanager", region_name="eu-west-3")

    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret   = json.loads(response["SecretString"])

        # On log l'username mais JAMAIS le password
        logger.info(f"request_id={request_id} secret_retrieved=OK username={secret['username']}")

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message":  "Secret recupere avec succes",
                "username": secret["username"],
                "host":     secret["host"]
                # Ne JAMAIS inclure le password dans la réponse
            })
        }
    except Exception as e:
        logger.error(f"request_id={request_id} error={str(e)}")
        raise