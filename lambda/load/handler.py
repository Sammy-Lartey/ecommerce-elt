import os
import re
import time
from string import Template

import boto3

data = boto3.client("redshift-data")

WORKGROUP = os.environ["WORKGROUP"]
DATABASE = os.environ["DATABASE"]
SECRET_ARN = os.environ["SECRET_ARN"]


def read_statements(path, run_id):
    with open(path) as f:
        lines = [line for line in f if not line.strip().startswith("--")]
    sql = Template("".join(lines)).substitute(run_id=run_id)
    return [s.strip() for s in sql.split(";") if s.strip()]


def handler(event, context):
    run_id = event["run_id"]
    if not re.fullmatch(r"[0-9a-f]{64}", run_id):
        raise ValueError(f"run_id does not look like a file hash: {run_id}")

    here = os.path.dirname(__file__)
    statements = read_statements(os.path.join(here, "03_load.sql"), run_id)

    response = data.batch_execute_statement(
        WorkgroupName=WORKGROUP,
        Database=DATABASE,
        SecretArn=SECRET_ARN,
        Sqls=statements,
    )

    while True:
        info = data.describe_statement(Id=response["Id"])
        if info["Status"] in ("FINISHED", "FAILED", "ABORTED"):
            break
        time.sleep(2)

    if info["Status"] != "FINISHED":
        raise RuntimeError(f"load {info['Status']}: {info.get('Error')}")

    return {"run_id": run_id, "statements": len(statements)}