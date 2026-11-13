# 08 · Troubleshooting

Most issues with this project tend to fall into a handful of areas: connecting to Redshift, pipeline failures, missing alert emails, Terraform changes, and a few Windows or tooling quirks.

This guide works through the common symptoms, what is likely causing them, and how to resolve them. If you're not sure where to start, use the initial checks below before jumping into a specific section.

**Placeholders:** `<PIPELINE_ARN>`, `<ALERTS_TOPIC_ARN>`, and `<ACCOUNT_ID>`. Get the pipeline and alerts topic ARNs from `terraform output`.

---

## 1. Start here

When something goes wrong, these checks are a good starting point:

1. **Did you receive a failure email?** If so, open the failed execution in the Step Functions console (`ecom-pipeline`). The execution view shows which state failed and includes the associated error message.
2. **Can you connect to Redshift?** Connection timeouts or "connection refused" errors often mean your public IP address has changed. See [Connecting to Redshift](#2-connecting-to-redshift).
3. **Is your SNS subscription confirmed?** If you're not receiving any emails, check that the email subscription was confirmed. See [No alert emails](#4-no-alert-emails).
4. **Is the dbt image up to date?** The Fargate task uses whichever image is currently tagged `latest` in ECR. Changes to your dbt project won't take effect until you rebuild and push the image. See [A pipeline run failed](#3-a-pipeline-run-failed).

---

## 2. Connecting to Redshift

Redshift connection problems are often caused by the security group no longer allowing your current public IP address.

| Symptom | Likely cause | Fix |
|---|---|---|
| Connection timed out or refused from SQL scripts, `dbt`, or Metabase ("The connection attempt failed") | Your public IP has changed, so the security group no longer allows the connection | Update `my_ip` and apply the Terraform change below |
| Metabase still fails after updating the IP | Metabase may have retained the failed connection state, or Docker is not running | Start Docker Desktop and retry. You can also use **Admin → Databases → Sync database schema now** |
| Metabase connects but shows no tables | The `bi_reader` user may be missing, or the `marts` schema has not been exposed correctly | Re-run `sql/06_bi_user.sql`, then `sql/07_bi_check.sql`. When connecting Metabase, select only the `marts` schema |

### Updating your IP address

From `terraform\main` in the project root, run:

```powershell
$ip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim(); $ip
(Get-Content terraform.tfvars) -replace '^my_ip\s*=.*', "my_ip = `"$ip`"" | Set-Content terraform.tfvars
terraform apply
```

The Terraform plan should show a change to the `ecom-redshift` security group only. If it proposes any other changes, stop and review the plan before applying it.

**The `\s*` in the replacement pattern matters.** It allows the command to match a `my_ip` assignment even when there are spaces around the equals sign, as in `my_ip = "..."`. Without it, the replacement may miss the existing line and leave the file unchanged.

---

## 3. A pipeline run failed

The first thing to check is the failed execution in the **Step Functions** console. Open `ecom-pipeline` and look at the state highlighted as failed. This tells you which part of the workflow needs attention.

| Failed state | What it usually means | Where to look next |
|---|---|---|
| **Convert** | The uploaded file could not be read as a workbook, or it does not contain the expected worksheets | Check the `ecom-convert` Lambda log in CloudWatch. Fix or replace the workbook, then upload it again |
| **Load** | Redshift could not be reached, or a Parquet file in `bronze/` does not match the expected table definition | Check the `ecom-load` Lambda log in CloudWatch |
| **Transform** | A dbt model or test failed during the transformation step | Inspect the dbt output, as described below |

The Load step runs its Redshift operations in a single transaction. If that transaction fails, its changes are rolled back rather than leaving a partial load behind.

### Reading the dbt logs

You can follow the Fargate task's CloudWatch output directly from your terminal. From the project root, run:

```powershell
aws logs tail /ecs/ecom-dbt --since 1h
```

Alternatively, open the `/ecs/ecom-dbt` log group in CloudWatch.

A successful run should end with all models built and all tests passing. If the Transform step fails, the output should identify the model or test associated with the failure.

### After fixing the cause

Once you've addressed the problem, you can rerun the same workbook. The pipeline is designed to handle repeated processing safely:

- The Load step replaces the rows associated with that workbook's `run_id` rather than adding another copy.
- The gold tables are rebuilt from the silver layer on each successful `dbt build`.

This means you generally do not need to upload a different file just to retry a failed run. See [04 · Pipeline](04-pipeline.md), under **Starting a run by hand**, for instructions on starting an execution manually.

### Common Transform failures

| Symptom | Likely cause | Fix |
|---|---|---|
| A dbt test fails | The source data may have violated an assumption, such as a duplicate ID or an unmatched product reference | Check the failing test name in the log, inspect the relevant source data, correct the issue, and rerun |
| A change to a dbt model has no effect | The Fargate task is still using an older image | Rebuild and push the dbt image to ECR. See [06 · Run it yourself](06-run-it-yourself.md) |
| The task fails to start with a "cannot pull image" error | The ECR repository may be empty, or the image push may not have completed successfully | Run `aws ecr describe-images --repository-name ecom-dbt` to check the available images, then build and push the image if necessary |
| A `relationships` test reports a configuration error | The dbt version expects test settings to be nested under `arguments:` when using `data_tests:` | Check the syntax against the examples in `dbt/models/*/schema.yml` |

### `dbt debug` reports `git [ERROR]`

Running `dbt debug` inside the container may report a Git-related error. This is harmless for the current project. It does not use external dbt packages, so Git is not required for the pipeline's transformation process.

---

## 4. No alert emails

The pipeline sends success and failure notifications through SNS. If no emails arrive, start by checking whether the email subscription was confirmed.

| Symptom | Likely cause | Fix |
|---|---|---|
| No success or failure emails arrive | The SNS email subscription was never confirmed | Find the initial email sent by AWS and click **Confirm subscription** |
| The subscription is confirmed, but emails still do not arrive | You may have confirmed a different subscription, or the configured email address may be incorrect | Check the subscription status and email address below |

### Check the subscription status

From the project root, run:

```powershell
aws sns list-subscriptions-by-topic --topic-arn <ALERTS_TOPIC_ARN>
```

Look at the `SubscriptionArn` field in the output. If it shows `PendingConfirmation`, the subscription has not been confirmed.

If you need a fresh confirmation email, you can change `alert_email` and run `terraform apply` again. You can also request a resend from the SNS console.

---

## 5. Terraform

A few Terraform issues can arise when running commands from the wrong directory or when modifying the Redshift security group.

| Symptom | Likely cause | Fix |
|---|---|---|
| "No configuration files" | Terraform was run from the wrong directory | Run the command from `terraform\main` or `terraform\bootstrap`. From the project root, you can also use `terraform -chdir=terraform\main <command>` |
| The plan wants to remove an ingress rule from `ecom-redshift` | One of the two inline security group rules is missing from the configuration | Check `redshift.tf`. Both the rule for your IP and the rule allowing the dbt task's security group must be present. Restore any missing rule before applying |
| Unexpected changes appear after updating your IP | The `my_ip` value may not have been updated correctly | Open `terraform.tfvars` and check that `my_ip` contains your current public IP address |

Always review the Terraform plan before confirming it with `yes`. If the proposed changes are unexpected, investigate them before proceeding.

---

## 6. SQL and naming

Some issues come down to Redshift naming conventions or how dbt handles schema names.

| Symptom | Likely cause | Fix |
|---|---|---|
| Creating or querying a schema or table named `raw` produces a syntax error | `raw` is a reserved word in Redshift | The project uses `raw_data` as the raw schema name instead |
| Gold tables appear under `staging_marts` instead of `marts` | By default, dbt combines the project schema with the schema configured for a model's folder | Check that the custom `generate_schema_name` macro is still present under `dbt/macros/` |
| `NULL` appears as `True` in query output | An older version of the `run_sql.py` display code handled null values incorrectly | Update to the current version of the script |

---

## 7. Windows, Docker and Git

The local development setup has a few Windows-specific quirks worth keeping in mind.

| Symptom | Likely cause | Fix |
|---|---|---|
| `docker login` to ECR fails with `400 Bad Request` | PowerShell is interfering with the piped password | Run the pipe inside `cmd /c "..."`, as shown in [06 · Run it yourself](06-run-it-yourself.md) |
| The Python virtual environment will not activate | PowerShell is blocking script execution | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`, then activate with `.venv\Scripts\Activate.ps1` |
| `git add .` misses files | The command was run from a subdirectory, so it only stages files below that location | Run it from the project root |
| Git reports `.git/config.lock` rename errors | OneDrive may be syncing the repository and holding the file | Pause OneDrive sync or move the repository outside the synced folder, then retry |
| Log files appear in `git status` | dbt writes logs to `logs/dbt.log` | Make sure `logs/` is included in `.gitignore`. If the log was already committed, run `git rm --cached logs/dbt.log` |
| An AWS CLI query returns `None` unexpectedly | `--max-items` is being combined with an index in the `--query` expression | Use `--max-results` where the command supports it |

---

## 8. If you're still stuck

If none of the fixes above resolves the problem, collect a few details before investigating further or asking for help:

1. **The failed state:** The name of the state that failed in the Step Functions execution.
2. **The relevant logs:** The last 30 lines of the CloudWatch log for the component that failed.
3. **The Terraform plan:** If the issue involves infrastructure, include the output of `terraform plan`.

These details make it much easier to narrow down whether the problem is in the source file, the pipeline, the AWS infrastructure, or the local development environment.

---

**Back to the [README](../README.md)**