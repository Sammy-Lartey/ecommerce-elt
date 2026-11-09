data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "redshift" {
  name        = "ecom-redshift"
  description = "Redshift access from my IP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  ingress {
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    security_groups = [aws_security_group.dbt_task.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "redshift_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com", "redshift-serverless.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "redshift" {
  name               = "ecom-redshift-s3-read"
  assume_role_policy = data.aws_iam_policy_document.redshift_assume.json
}

data "aws_iam_policy_document" "redshift_s3" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data.arn}/bronze/*"]
  }

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.data.arn]
  }
}

resource "aws_iam_role_policy" "redshift_s3" {
  name   = "redshift-s3-read"
  role   = aws_iam_role.redshift.id
  policy = data.aws_iam_policy_document.redshift_s3.json
}

resource "aws_redshiftserverless_namespace" "ecom" {
  namespace_name        = "ecom"
  db_name               = "ecom"
  admin_username        = "admin"
  manage_admin_password = true
  iam_roles             = [aws_iam_role.redshift.arn]
  default_iam_role_arn  = aws_iam_role.redshift.arn

  depends_on = [aws_iam_role_policy.redshift_s3]
}

resource "aws_redshiftserverless_workgroup" "ecom" {
  namespace_name      = aws_redshiftserverless_namespace.ecom.namespace_name
  workgroup_name      = "ecom"
  base_capacity       = 4
  max_capacity        = 8
  publicly_accessible = true
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [aws_security_group.redshift.id]
}

resource "aws_redshiftserverless_usage_limit" "daily" {
  resource_arn  = aws_redshiftserverless_workgroup.ecom.arn
  usage_type    = "serverless-compute"
  amount        = 20
  period        = "daily"
  breach_action = "deactivate"
}