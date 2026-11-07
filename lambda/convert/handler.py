import os
import shutil
import tempfile

import boto3

from convert import convert_workbook

s3 = boto3.client("s3")


def handler(event, context):
    bucket = event["bucket"]
    key = event["key"]

    if not key.startswith("landing/") or not key.endswith(".xlsx"):
        raise ValueError(f"expected an .xlsx file under landing/, got {key}")

    work = tempfile.mkdtemp(dir="/tmp")
    try:
        local_file = os.path.join(work, os.path.basename(key))
        out_dir = os.path.join(work, "out")

        s3.download_file(bucket, key, local_file)
        manifest = convert_workbook(local_file, out_dir)

        for folder, _, files in os.walk(out_dir):
            for name in files:
                path = os.path.join(folder, name)
                relative = os.path.relpath(path, out_dir).replace(os.sep, "/")
                if name.startswith("manifest_"):
                    target = f"bronze/_manifests/{name}"
                else:
                    target = f"bronze/{relative}"
                s3.upload_file(path, bucket, target)

        manifest["bucket"] = bucket
        manifest["bronze_prefix"] = "bronze/"
        return manifest
    finally:
        shutil.rmtree(work, ignore_errors=True)