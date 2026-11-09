FROM python:3.12-slim

RUN pip install --no-cache-dir dbt-core==1.13.0rc1 dbt-redshift==1.11.2

WORKDIR /dbt
COPY . .

ENTRYPOINT ["dbt"]
CMD ["build"]