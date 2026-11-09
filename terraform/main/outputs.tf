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

output "redshift_endpoint" {
  value = aws_redshiftserverless_workgroup.ecom.endpoint[0].address
}

output "redshift_secret" {
  value = aws_redshiftserverless_namespace.ecom.admin_password_secret_arn
}

output "dbt_repository" {
  value = aws_ecr_repository.dbt.repository_url
}

output "dbt_task_security_group" {
  value = aws_security_group.dbt_task.id
}

output "default_subnets" {
  value = data.aws_subnets.default.ids
}

output "alerts_topic" {
  value = aws_sns_topic.alerts.arn
}

output "load_function" {
  value = aws_lambda_function.load.function_name
}

output "pipeline_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}