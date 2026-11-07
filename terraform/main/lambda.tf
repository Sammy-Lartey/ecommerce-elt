locals {
  convert_zip = "${path.module}/../../lambda/convert/build/convert.zip"
}

resource "aws_s3_object" "convert_zip" {
  bucket      = aws_s3_bucket.data.id
  key         = "artifacts/convert.zip"
  source      = local.convert_zip
  source_hash = filemd5(local.convert_zip)
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "convert" {
  name               = "ecom-convert-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "convert_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data.arn}/landing/*"]
  }

  statement {
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.data.arn}/bronze/*"]
  }
}

resource "aws_iam_role_policy" "convert_access" {
  name   = "convert-s3-access"
  role   = aws_iam_role.convert.id
  policy = data.aws_iam_policy_document.convert_access.json
}

resource "aws_iam_role_policy_attachment" "convert_logs" {
  role       = aws_iam_role.convert.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "convert" {
  name              = "/aws/lambda/ecom-convert"
  retention_in_days = 14
}

resource "aws_lambda_function" "convert" {
  function_name = "ecom-convert"
  role          = aws_iam_role.convert.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  memory_size   = 1024
  timeout       = 120

  s3_bucket         = aws_s3_object.convert_zip.bucket
  s3_key            = aws_s3_object.convert_zip.key
  s3_object_version = aws_s3_object.convert_zip.version_id
  source_code_hash  = filebase64sha256(local.convert_zip)

  depends_on = [
    aws_cloudwatch_log_group.convert,
    aws_iam_role_policy_attachment.convert_logs,
  ]
}