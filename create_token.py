"""AWS Lambda that creates and stores an Authrorization Bearer Token.

Stores token in SSM Parameter Store 'SecureString'. Meant to be run every 59 
days as token expires every 60 days. Logs status and the errors.

Documentation on tokens: https://urs.earthdata.nasa.gov/documentation/for_users/user_token
"""

# Standard imports
import json
import logging
import os
import sys

# Third-party imports
import boto3
import botocore
import requests
from requests.auth import HTTPBasicAuth

# Constants
HEADERS = {"Accept": "application/json"}
TOPIC_STRING = "batch-job-failure"

def token_handler(event, context):
    """Handles the creation of a EDL bearer token."""
    
    logger = get_logger()
    
    if event["prefix"].endswith("-sit") or event["prefix"].endswith("-uat"):
        token_url = "https://uat.urs.earthdata.nasa.gov/api/users/token"
        delete_token_url = "https://uat.urs.earthdata.nasa.gov/api/users/revoke_token?token"
        logger.info("Attempting to create token for UAT environment.")
    else:
        token_url = "https://urs.earthdata.nasa.gov/api/users/token"
        delete_token_url = "https://urs.earthdata.nasa.gov/api/users/revoke_token?token"
        logger.info("Attempting to create token for OPS environment.")
    
    try:
        username, password = get_edl_creds(logger)
        token = generate_token(username, password, token_url, delete_token_url, logger)
        store_token(token, event["prefix"], logger)
        if not token:
            publish_event("ERROR", "Issue generating and storing bearer token.", "", logger)
            sys.exit(1)
    except botocore.exceptions.ClientError as error:
        publish_event("ERROR", error, "", logger)
        sys.exit(1)
        
def get_logger():
    """Return a formatted logger object."""
    
    # Remove AWS Lambda logger
    logger = logging.getLogger()
    for handler in logger.handlers:
        logger.removeHandler(handler)
    
    # Create a Logger object and set log level
    logger = logging.getLogger(__name__)
    logger.setLevel(logging.DEBUG)

    # Create a handler to console and set level
    console_handler = logging.StreamHandler()

    # Create a formatter and add it to the handler
    console_format = logging.Formatter("%(asctime)s - %(module)s - %(levelname)s : %(message)s")
    console_handler.setFormatter(console_format)

    # Add handlers to logger
    logger.addHandler(console_handler)

    # Return logger
    return logger

def get_edl_creds(logger):
    """Return EDL username and password stored in SSM Parameter Store.
    
    Raises botocore.exceptions.ClientError
    """
    
    try:
        ssm_client = boto3.client('ssm', region_name="us-west-2")
        username = ssm_client.get_parameter(Name="generate-edl-username", WithDecryption=True)["Parameter"]["Value"]
        password = ssm_client.get_parameter(Name="generate-edl-password", WithDecryption=True)["Parameter"]["Value"]
        logger.info("Retrieved EDL username and password.")
        return username, password
    except botocore.exceptions.ClientError as error:
        logger.error("Could not retrieve EDL credentials from SSM Parameter Store.")
        logger.error(error)
        raise error
    
def generate_token(username, password, token_url, delete_token_url, logger):
    """Generate and store bearer token using EDL credentials in SSM Parameter Store."""
    
    post_response = requests.post(token_url, headers=HEADERS, auth=HTTPBasicAuth(username, password))
    token_data = json.loads(post_response.content)
    if "error" in token_data.keys(): 
        if token_data["error"] == "max_token_limit": 
            token = handle_token_error(token_data, username, password, token_url, delete_token_url, logger)
        else:
            logger.error("Error encountered when trying to retrieve bearer token from EDL.")
            return False
    else:
        token = token_data["access_token"]
    logger.info("Successfully generated EDL bearer token.")
    return token
    
def handle_token_error(token_data, username, password, token_url, delete_token_url,  logger):
    """Attempts to handle errors encoutered in token generation and return a
    valid bearer token."""
    
    # Get all tokens and attempt to remove any that exist
    get_response = requests.get(f"{token_url}s", headers=HEADERS, auth=HTTPBasicAuth(username, password))
    token_data = json.loads(get_response.content)
    for token in token_data:
        if "access_token" in token.keys():
            requests.post(f"{delete_token_url}={token['access_token']}", headers=HEADERS, auth=HTTPBasicAuth(username, password))
    
    # Generate a new token
    post_response = requests.post(token_url, headers=HEADERS, auth=HTTPBasicAuth(username, password))
    token_data = json.loads(post_response.content)
    if "error" in token_data.keys():
        logger.error("Error encountered when trying to retrieve bearer token from EDL.")
        return False
    else:
        return token_data["access_token"]
    
def store_token(token, prefix, logger):
    """Store bearer token in SSM Parameter Store."""
    
    try:
        
        kms_client = boto3.client('kms', region_name="us-west-2")
        kms_response = kms_client.describe_key(KeyId="alias/aws/ssm")
        key = kms_response["KeyMetadata"]["KeyId"]
        
        ssm_client = boto3.client('ssm', region_name="us-west-2")
        ssm_response = ssm_client.put_parameter(
            Name=f"{prefix}-edl-token",
            Description="Temporary EDL bearer token",
            Value=token,
            Type="SecureString",
            KeyId=key,
            Overwrite=True,
            Tier="Standard"
        )
        logger.info("EDL bearer token has been stored as a secure string in SSM Parameter Store.")
    except botocore.exceptions.ClientError as error:
        logger.error("Could not store EDL bearer token in SSM Parameter Store.")
        logger.error(error)
        raise error
    
def publish_event(sigevent_type, sigevent_description, sigevent_data, logger):
    """Publish event to SNS Topic."""
    
    sns = boto3.client("sns")
    
    # Get topic ARN
    try:
        topics = sns.list_topics()
    except botocore.exceptions.ClientError as e:
        logger.error("Failed to list SNS Topics.")
        logger.error(f"Error - {e}")
        sys.exit(1)
    for topic in topics["Topics"]:
        if TOPIC_STRING in topic["TopicArn"]:
            topic_arn = topic["TopicArn"]
            
    # Publish to topic
    subject = f"Generate Token Creator Lambda Failure"
    message = f"The Generate Token Creator has encountered an error.\n" \
        + f"Log file: {os.getenv('AWS_LAMBDA_LOG_GROUP_NAME')}/{os.getenv('AWS_LAMBDA_LOG_STREAM_NAME')}.\n" \
        + f"Error type: {sigevent_type}.\n" \
        + f"Error description: {sigevent_description}\n"
    if sigevent_data != "": message += f"Error data: {sigevent_data}"
    try:
        response = sns.publish(
            TopicArn = topic_arn,
            Message = message,
            Subject = subject
        )
    except botocore.exceptions.ClientError as e:
        logger.error(f"Failed to publish to SNS Topic: {topic_arn}.")
        logger.error(f"Error - {e}")
        sys.exit(1)
    
    logger.info(f"Message published to SNS Topic: {topic_arn}.")