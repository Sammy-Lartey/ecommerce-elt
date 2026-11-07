output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "data_bucket" {
  value = aws_s3_bucket.data.id
}

output "convert_function" {
  value = aws_lambda_function.convert.function_name
}