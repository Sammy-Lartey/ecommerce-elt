resource "aws_cloudwatch_event_rule" "new_workbook" {
  name        = "ecom-new-workbook"
  description = "an excel file landed in the landing/ folder"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.data.id] }
      object = { key = [{ wildcard = "landing/*.xlsx" }] }
    }
  })
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events_to_pipeline" {
  name               = "ecom-events-start-pipeline"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "start_pipeline" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.pipeline.arn]
  }
}

resource "aws_iam_role_policy" "start_pipeline" {
  name   = "start-pipeline"
  role   = aws_iam_role.events_to_pipeline.id
  policy = data.aws_iam_policy_document.start_pipeline.json
}

resource "aws_cloudwatch_event_target" "pipeline" {
  rule     = aws_cloudwatch_event_rule.new_workbook.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.events_to_pipeline.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }
    input_template = "{\"bucket\": \"<bucket>\", \"key\": \"<key>\"}"
  }
}