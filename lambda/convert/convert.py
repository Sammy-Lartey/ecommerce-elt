import hashlib
import json
import os
from datetime import datetime, timezone
from decimal import Decimal

import openpyxl
import pyarrow as pa
import pyarrow.parquet as pq

from schema import SHEETS


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def clean(value, arrow_type):
    if value is None:
        return None
    if pa.types.is_string(arrow_type):
        return str(value)
    if pa.types.is_decimal(arrow_type):
        return Decimal(str(value))
    if pa.types.is_floating(arrow_type):
        return float(value)
    if pa.types.is_integer(arrow_type):
        number = float(value)
        if number != int(number):
            raise ValueError(f"expected a whole number, got {value}")
        return int(number)
    if pa.types.is_boolean(arrow_type):
        if isinstance(value, bool):
            return value
        raise ValueError(f"expected True or False, got {value}")
    if pa.types.is_timestamp(arrow_type):
        if isinstance(value, datetime):
            return value
        raise ValueError(f"expected a date, got {value}")
    raise ValueError(f"no rule for type {arrow_type}")


def read_sheet(ws, columns):
    rows = ws.iter_rows(values_only=True)
    header = list(next(rows))
    expected = [name for name, _ in columns]
    if header != expected:
        raise ValueError(f"{ws.title}: columns do not match. Expected {expected}, got {header}")

    values = {name: [] for name in expected}
    for number, row in enumerate(rows, start=2):
        if all(cell is None for cell in row):
            continue
        for (name, arrow_type), cell in zip(columns, row):
            try:
                values[name].append(clean(cell, arrow_type))
            except Exception as error:
                raise ValueError(f"{ws.title} row {number}, column {name}: {error}")
    return values


def convert_workbook(xlsx_path, out_dir):
    run_id = file_hash(xlsx_path)
    source_file = os.path.basename(xlsx_path)
    ingested_at = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)

    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    missing = [name for name in SHEETS if name not in wb.sheetnames]
    if missing:
        raise ValueError(f"sheets missing from workbook: {missing}")

    manifest = {"run_id": run_id, "source_file": source_file, "tables": {}}

    for sheet_name, (table, columns) in SHEETS.items():
        values = read_sheet(wb[sheet_name], columns)
        count = len(values[columns[0][0]])

        arrays = [pa.array(values[name], type=arrow_type) for name, arrow_type in columns]
        names = [name for name, _ in columns]

        arrays.append(pa.array([run_id] * count, type=pa.string()))
        arrays.append(pa.array([source_file] * count, type=pa.string()))
        arrays.append(pa.array([ingested_at] * count, type=pa.timestamp("us")))
        names += ["_run_id", "_source_file", "_ingested_at"]

        folder = os.path.join(out_dir, table, f"run_id={run_id}")
        os.makedirs(folder, exist_ok=True)
        pq.write_table(pa.Table.from_arrays(arrays, names=names), os.path.join(folder, "part-0.parquet"))

        manifest["tables"][table] = count

    with open(os.path.join(out_dir, f"manifest_{run_id}.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest