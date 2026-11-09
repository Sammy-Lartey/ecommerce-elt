data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "ecom-pipeline-sfn"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "pipeline_access" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.convert.arn, aws_lambda_function.load.arn]
  }

  statement {
    actions = ["ecs:RunTask"]
    resources = [
      aws_ecs_task_definition.dbt.arn_without_revision,
      "${aws_ecs_task_definition.dbt.arn_without_revision}:*",
    ]
  }

  statement {
    actions   = ["ecs:StopTask", "ecs:DescribeTasks"]
    resources = ["*"]
  }

  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.dbt_execution.arn]
  }

  # step functions uses this rule to find out when the ecs task has finished
  statement {
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:aws:events:${var.region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"]
  }

  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "pipeline_access" {
  name   = "pipeline-access"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline_access.json
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "ecom-pipeline"
  role_arn = aws_iam_role.pipeline.arn

  definition = jsonencode({
    Comment = "excel to parquet, load into redshift, dbt build"
    StartAt = "Convert"
    States = {

      Convert = {
        Type           = "Task"
        Resource       = "arn:aws:states:::lambda:invoke"
        TimeoutSeconds = 300
        Parameters = {
          FunctionName = aws_lambda_function.convert.arn
          "Payload.$"  = "$"
        }
        ResultSelector = {
          "run_id.$" = "$.Payload.run_id"
          "tables.$" = "$.Payload.tables"
        }
        ResultPath = "$.convert"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 5
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "NotifyFailure" }]
        Next  = "Load"
      }

      Load = {
        Type           = "Task"
        Resource       = "arn:aws:states:::lambda:invoke"
        TimeoutSeconds = 400
        Parameters = {
          FunctionName = aws_lambda_function.load.arn
          Payload      = { "run_id.$" = "$.convert.run_id" }
        }
        ResultSelector = { "statements.$" = "$.Payload.statements" }
        ResultPath     = "$.load"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 5
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "NotifyFailure" }]
        Next  = "Transform"
      }

      Transform = {
        Type           = "Task"
        Resource       = "arn:aws:states:::ecs:runTask.sync"
        TimeoutSeconds = 1800
        Parameters = {
          Cluster        = aws_ecs_cluster.ecom.arn
          TaskDefinition = aws_ecs_task_definition.dbt.family
          LaunchType     = "FARGATE"
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = data.aws_subnets.default.ids
              SecurityGroups = [aws_security_group.dbt_task.id]
              AssignPublicIp = "ENABLED"
            }
          }
        }
        ResultSelector = { "task_arn.$" = "$.TaskArn" }
        ResultPath     = "$.transform"
        Catch          = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "NotifyFailure" }]
        Next           = "NotifySuccess"
      }

      NotifySuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.alerts.arn
          Subject     = "ecom pipeline succeeded"
          "Message.$" = "States.Format('Run {} finished. Rows loaded: {}', $.convert.run_id, States.JsonToString($.convert.tables))"
        }
        End = true
      }

      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.alerts.arn
          Subject     = "ecom pipeline FAILED"
          "Message.$" = "States.Format('A pipeline step failed. Details: {}', States.JsonToString($.error))"
        }
        Next = "Failed"
      }

      Failed = {
        Type  = "Fail"
        Error = "PipelineFailed"
        Cause = "see the execution history for the failing step"
      }
    }
  })
}