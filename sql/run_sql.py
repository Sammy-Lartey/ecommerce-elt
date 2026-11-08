import re
import sys
import time
from string import Template

import boto3

region = "us-east-1"
workgroup = "ecom"
database = "ecom"

data = boto3.client("redshift-data", region_name=region)
serverless = boto3.client("redshift-serverless", region_name=region)


def read_statements(path, values):
    with open(path) as f:
        text = f.read()
    text = "\n".join(line for line in text.splitlines() if not line.strip().startswith("--"))
    text = Template(text).substitute(values)
    return [s.strip() for s in text.split(";") if s.strip()]


def wait(statement_id):
    while True:
        info = data.describe_statement(Id=statement_id)
        if info["Status"] in ("FINISHED", "FAILED", "ABORTED"):
            return info
        time.sleep(1)


def show_rows(statement_id):
    result = data.get_statement_result(Id=statement_id)
    names = [c["name"] for c in result["ColumnMetadata"]]
    print("  " + " | ".join(names))
    for record in result["Records"]:
        cells = ["NULL" if cell.get("isNull") else list(cell.values())[0] for cell in record]
        print("  " + " | ".join(str(c) for c in cells))


def main():
    path = sys.argv[1]
    values = dict(arg.split("=", 1) for arg in sys.argv[2:])
    statements = read_statements(path, values)

    secret = serverless.get_namespace(namespaceName=workgroup)["namespace"]["adminPasswordSecretArn"]

    response = data.batch_execute_statement(
        WorkgroupName=workgroup,
        Database=database,
        SecretArn=secret,
        Sqls=statements,
    )
    info = wait(response["Id"])

    for number, sub in enumerate(info.get("SubStatements", []), start=1):
        print(f"{number}. {sub['Status']} - {statements[number - 1][:70]!r}")
        if sub.get("Error"):
            print("   error:", sub["Error"])
        if sub.get("HasResultSet"):
            show_rows(sub["Id"])

    if info["Status"] != "FINISHED":
        print("FAILED:", info.get("Error", info["Status"]))
        sys.exit(1)
    print(f"done, {len(statements)} statements in one transaction")


main()