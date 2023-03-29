# token_creator

The token_creator program is an AWS Lambda function that periodically creates or renews the ELD bearer token required to preform CMR queries.

token_creator removes old tokens and creates a new token to store as a secure string in the SSM parameter store. Other Generate components may access this token to perform CMR queries.

Top-level Generate repo: https://github.com/podaac/generate

## aws infrastructure

The token_creator program includes the following AWS services:
- Lambda function to execute code deployed via zip file.
- IAM role and policy for Lambda function execution.
- EventBridge Schedule that invokes the Lambda function every 59 days.

## terraform 

Deploys AWS infrastructure and stores state in an S3 backend.

To deploy:
1. Initialize terraform: 
    ```
    terraform init -backend-config="bucket=bucket-state" \
        -backend-config="key=component.tfstate" \
        -backend-config="region=aws-region" \
        -backend-config="profile=named-profile"
    ```
2. Plan terraform modifications: 
    ```
    ~/terraform plan -var="environment=venue" \
        -var="prefix=venue-prefix" \
        -var="profile=named-profile" \
        -out="tfplan"
    ```
3. Apply terraform modifications: `terraform apply tfplan`