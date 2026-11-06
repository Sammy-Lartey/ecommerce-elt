import json
import sys

from convert import convert_workbook

manifest = convert_workbook(sys.argv[1], sys.argv[2])
print(json.dumps(manifest, indent=2))