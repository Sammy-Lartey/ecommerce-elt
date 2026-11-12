# 06 · Run it yourself

This page gives you an overview of what you need to get the project running, how the initial setup fits together, and the commands you'll use to manage it once everything is in place.

It is intended as a quick reference rather than a step-by-step installation guide. The Terraform configuration and SQL scripts contain the implementation details, while the other documentation explains how the different parts of the system work.

Commands are written for Windows PowerShell, and references to the *project root* mean the `ecommerce-elt` folder you cloned from GitHub.

The following placeholders are used throughout:

| Placeholder | Meaning |
|---|---|
| `<ACCOUNT_ID>` | Your 12-digit AWS account ID |
| `<DATA_BUCKET>` | The project data bucket name, available through `terraform output` |
| `<PIPELINE_ARN>` | The Step Functions state machine ARN, available through `terraform output` |

---

## 1. What you need

Before setting up the project, make sure you have:

- An AWS account with the **AWS CLI** configured
- **Terraform**
- **Docker Desktop**
- **Python 3**
- **Git**

The infrastructure deploys to `us-east-1` by default. The Terraform configuration uses the AWS provider version `~> 6.0`.

---

## 2. Setting it up, at a glance

The initial setup involves a few steps across the local project and AWS. Here's how they fit together:

| # | Step | Where it happens |
|---|---|---|
| 1 | Clone the repository and create a Python virtual environment | Project root |
| 2 | Create the Terraform state bucket (one-time setup) | `terraform/bootstrap/` |
| 3 | Configure your public IP address and alert email in a git-ignored `terraform.tfvars` file | `terraform/main/` |
| 4 | Deploy the AWS infrastructure using `terraform apply` | `terraform/main/` |
| 5 | Confirm the SNS email subscription using the link AWS sends | Your inbox |
| 6 | Build the dbt Docker image and push it to ECR | `dbt/` |
| 7 | Create the Redshift schemas and raw tables | `sql/` |
| 8 | Upload a workbook to `landing/` to trigger the pipeline | S3 |
| 9 | Create the read-only `bi_reader` user and connect Metabase | `sql/06_bi_user.sql`, `bi/` |

A couple of details are worth keeping in mind:

- **Terraform state bucket:** The bucket name must be globally unique. If you change the default name, update it in both `terraform/bootstrap/` and the backend block in `terraform/main/main.tf`.
- **Email notifications:** AWS requires you to confirm the SNS subscription before the pipeline can send alerts to your inbox.

For a breakdown of the AWS resources and how they're configured, see [03 · Infrastructure](03-infrastructure.md). For the sequence of events after a workbook is uploaded, see [04 · Pipeline](04-pipeline.md).

---

## 3. Everyday tasks

Once the initial setup is complete, most interactions with the pipeline happen through S3, the AWS console and a handful of commands.

### Load a new or updated workbook

Upload the Excel workbook to the `landing/` folder in your S3 data bucket:

```powershell
aws s3 cp <WORKBOOK>.xlsx s3://<DATA_BUCKET>/landing/
```

The upload triggers the pipeline automatically. You don't need to start the Step Functions execution yourself.

The pipeline uses a fingerprint of the workbook's contents to identify each run. Uploading the same workbook again safely replaces its previous records rather than appending duplicates.

### Re-run a workbook that is already uploaded

If you want to run the pipeline again without uploading the workbook, you can start a Step Functions execution manually.

First, prepare the `input.json` file using the format described in [04 · Pipeline](04-pipeline.md). Then, from the project root, run:

```powershell
aws stepfunctions start-execution --state-machine-arn <PIPELINE_ARN> --input file://input.json
```

### Update the dbt models

The ECS task pulls the Docker image referenced by the `latest` tag when it starts. It does not rebuild the image as part of the pipeline.

After changing anything under `dbt/`, rebuild the image and push the updated version to ECR. From the `dbt/` directory in the project root:

```powershell
cmd /c "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com"

docker build -t ecom-dbt .

docker tag ecom-dbt:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/ecom-dbt:latest

docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/ecom-dbt:latest
```

The next pipeline run automatically picks up the updated image.

> **Why `cmd /c`?**
>
> Piping the ECR login password directly through PowerShell can corrupt it and cause a `400 Bad Request` error. Running the command through `cmd` avoids that issue.

### Your IP address changed

Redshift connections from your machine are restricted to the public IP address allowed by the `ecom-redshift` security group.

If your public IP changes, your machine will no longer match that rule, and connection attempts may time out. Update `my_ip` in `terraform.tfvars` and apply the change.

From `terraform/main/` in the project root:

```powershell
$ip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()

(Get-Content terraform.tfvars) -replace '^my_ip\s*=.*', "my_ip = `"$ip`"" | Set-Content terraform.tfvars

terraform apply
```

Review the Terraform plan before applying it. The expected change is an update to the `ecom-redshift` security group.

### Check the data

The project includes SQL checks in `sql/04_checks.sql`. Run them through `run_sql.py` from the project root, with your Python virtual environment active.

These checks confirm that the loads were recorded and allow you to inspect the row counts in Redshift. The counts reflect the workbook that was processed and may change with a different source file.

For the dbt execution, check the CloudWatch log group `/ecs/ecom-dbt`. A successful run should show all models built and all 19 tests passing.

### Start the dashboards

Metabase runs locally through Docker Compose. From the `bi/` directory in the project root, start it with:

```powershell
docker compose up -d
```

Once the container is running, open [http://localhost:3000](http://localhost:3000).

Connect Metabase to Redshift using the `bi_reader` account and expose the `marts` schema only. This keeps dashboard access limited to the reporting-ready gold tables.

For the available dashboards and the metrics they cover, see [07 · Dashboards](07-dashboards.md).

### Remove the project infrastructure

If you want to tear down the project, empty the data bucket before destroying the main Terraform stack.

Run `terraform destroy` from `terraform/main/`, then remove the Terraform state bucket separately from `terraform/bootstrap/`.

Keep in mind that the data bucket has versioning enabled. Deleting its current objects may not remove older versions, so you may need to clear those through the S3 console before Terraform can delete the bucket.

The state bucket should be removed last, after the main infrastructure has been destroyed.

---

Something not working as expected? See [08 · Troubleshooting](08-troubleshooting.md).

**Next:** [07 · Dashboards](07-dashboards.md)