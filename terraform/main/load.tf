data "archive_file" "load" {
  type        = "zip"
  output_path = "${path.module}/load.zip"

  source {
    content  = file("${path.module}/../../lambda/load/handler.py")
    filename = "handler.py"
  }

  source {
    content  = file("${path.module}/../../sql/03_load.sql")
    filename = "03_load.sql"
  }
}

data "aws_iam_policy_document" "load_access" {
  statement {
    actions   = ["redshift-data:BatchExecuteStatement"]
    resources = [aws_redshiftserverless_workgroup.ecom.arn]
  }

  statement {
    actions   = ["redshift-data:DescribeStatement"]
    resources = ["*"]
  }

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_redshiftserverless_namespace.ecom.admin_password_secret_arn]
  }
}

resource "aws_iam_role" "load" {
  name               = "ecom-load-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "load_logs" {
  role       = aws_iam_role.load.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "load_access" {
  name   = "load-redshift-access"
  role   = aws_iam_role.load.id
  policy = data.aws_iam_policy_document.load_access.json
}

resource "aws_cloudwatch_log_group" "load" {
  name              = "/aws/lambda/ecom-load"
  retention_in_days = 14
}

resource "aws_lambda_function" "load" {
  function_name    = "ecom-load"
  role             = aws_iam_role.load.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.load.output_path
  source_code_hash = data.archive_file.load.output_base64sha256
  timeout          = 300
  memory_size      = 128

  environment {
    variables = {
      WORKGROUP  = aws_redshiftserverless_workgroup.ecom.workgroup_name
      DATABASE   = "ecom"
      SECRET_ARN = aws_redshiftserverless_namespace.ecom.admin_password_secret_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.load]
}