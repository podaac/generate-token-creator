# AWS Lambda function
resource "aws_lambda_function" "aws_lambda_token_creator" {
  filename         = "token_creator.zip"
  function_name    = "${var.prefix}-token-creator"
  role             = aws_iam_role.aws_lambda_execution_role.arn
  handler          = "token_creator.token_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("token_creator.zip")
  timeout          = 300
}

# AWS Lambda role and policy
resource "aws_iam_role" "aws_lambda_execution_role" {
  name = "${var.prefix}-lambda-token-creator-execution-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  permissions_boundary = "arn:aws:iam::${local.account_id}:policy/NGAPShRoleBoundary"
}

resource "aws_iam_role_policy_attachment" "aws_lambda_execution_role_policy_attach" {
  role       = aws_iam_role.aws_lambda_execution_role.name
  policy_arn = aws_iam_policy.aws_lambda_execution_policy.arn
}

resource "aws_iam_policy" "aws_lambda_execution_policy" {
  name        = "${var.prefix}-lambda-token-creator-execution-policy"
  description = "Write to CloudWatch logs, publish and list SNS Topics, get and put SSM parameters."
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowCreatePutLogs",
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*"
      },
      {
        "Sid" : "AllowPublishToTopic",
        "Effect" : "Allow",
        "Action" : [
          "sns:Publish"
        ],
        "Resource" : "${data.aws_sns_topic.batch_failure_topic.arn}"
      },
      {
        "Sid" : "AllowListTopics",
        "Effect" : "Allow",
        "Action" : [
          "sns:ListTopics"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "DescribeParameters",
        "Effect" : "Allow",
        "Action" : "ssm:DescribeParameters",
        "Resource" : "*"
      },
      {
        "Sid" : "GetParameters",
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameter*"
        ],
        "Resource" : [
          "${data.aws_ssm_parameter.edl_password.arn}",
          "${data.aws_ssm_parameter.edl_username.arn}"
        ]
      },
      {
        "Sid" : "PutParameters",
        "Effect" : "Allow",
        "Action" : [
          "ssm:PutParameter*"
        ],
        "Resource" : "${aws_ssm_parameter.aws_ssm_parameter_edl_token.arn}"
      },
      {
        "Sid" : "EncryptDecryptKey",
        "Effect" : "Allow",
        "Action" : [
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:Decrypt"
        ],
        "Resource" : "${data.aws_kms_key.ssm_key.arn}"
      }
    ]
  })
}

# SSM Parameter Store parameter to EDL bearer token
resource "aws_ssm_parameter" "aws_ssm_parameter_edl_token" {
  name        = "${var.prefix}-edl-token"
  description = "Temporary EDL bearer token"
  type        = "SecureString"
  value       = "start"
  overwrite   = true
}

# EventBridge schedule
resource "aws_scheduler_schedule" "aws_schedule_token_creator" {
  name       = "${var.prefix}-token-creator"
  group_name = "default"
  flexible_time_window {
    mode = "OFF"
  }
  schedule_expression = "rate(59 days)"
  target {
    arn      = aws_lambda_function.aws_lambda_token_creator.arn
    role_arn = aws_iam_role.aws_eventbridge_token_creator_execution_role.arn
    input = jsonencode({
      "prefix": "${var.prefix}"
    })
  }
  state = "ENABLED"
}

# EventBridge execution role and policy
resource "aws_iam_role" "aws_eventbridge_token_creator_execution_role" {
  name = "${var.prefix}-eventbridge-token-creator-execution-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "scheduler.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  permissions_boundary = "arn:aws:iam::${local.account_id}:policy/NGAPShRoleBoundary"
}

resource "aws_iam_role_policy_attachment" "aws_eventbridge_token_creator_execution_role_policy_attach" {
  role       = aws_iam_role.aws_eventbridge_token_creator_execution_role.name
  policy_arn = aws_iam_policy.aws_eventbridge_token_creator_execution_policy.arn
}

resource "aws_iam_policy" "aws_eventbridge_token_creator_execution_policy" {
  name        = "${var.prefix}-eventbridge-token-creator-execution-policy"
  description = "Allow EventBridge to invoke a Lambda function."
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowInvokeLambda",
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction"
        ],
        "Resource" : "${aws_lambda_function.aws_lambda_token_creator.arn}"
      }
    ]
  })
}