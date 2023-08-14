#!/bin/bash
#
# Script to create a zipped deployment package for a Lambda function.
#
# Command line arguments:
# [1] app_name: Name of application to create a zipped deployment package for
# 
# Example usage: ./delpoy-lambda.sh "my-app-name"

APP_NAME=$1
ROOT_PATH="$PWD"

# Install dependencies
pip install --target ./package requests~=2.31.0 "urllib3<2"

# Zip dependencies
cd package/
zip -r ../$APP_NAME.zip .

# Zip script
cd ..
zip $APP_NAME.zip $APP_NAME.py
echo "Created: $APP_NAME.zip."
