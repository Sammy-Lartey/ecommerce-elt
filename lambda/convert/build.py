import os
import shutil
import subprocess
import sys
import zipfile

here = os.path.dirname(os.path.abspath(__file__))
build = os.path.join(here, "build")
package = os.path.join(build, "package")
zip_path = os.path.join(build, "convert.zip")

shutil.rmtree(build, ignore_errors=True)
os.makedirs(package)

subprocess.check_call([
    sys.executable, "-m", "pip", "install",
    "--target", package,
    "--platform", "manylinux2014_x86_64",
    "--platform", "manylinux_2_28_x86_64",
    "--python-version", "3.12",
    "--implementation", "cp",
    "--only-binary=:all:",
    "--no-compile",
    "-r", os.path.join(here, "requirements.txt"),
])

for name in ["schema.py", "convert.py", "handler.py"]:
    shutil.copy(os.path.join(here, name), package)

with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    for folder, _, files in os.walk(package):
        for name in files:
            path = os.path.join(folder, name)
            zf.write(path, os.path.relpath(path, package).replace(os.sep, "/"))

print("built", zip_path, round(os.path.getsize(zip_path) / 1024 / 1024), "MB")