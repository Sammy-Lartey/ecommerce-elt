# Overview

This document introduces the project, its overall architecture and the thinking behind some of the main engineering decisions. It provides a starting point for understanding how the different components work together, why particular technologies were chosen and what the pipeline is designed to achieve.

## What the project is for

E-commerce businesses generate data across different parts of their operations: what customers purchase, which products they buy, how much they pay and whether a transaction is eventually refunded. This information is often collected and maintained in spreadsheets, which can work well for smaller datasets and basic reporting.

However, as the volume of data grows, managing and analysing it through spreadsheets becomes increasingly difficult. Files may be copied, modified and uploaded multiple times, making it harder to maintain consistency and avoid duplicate records. Preparing the data for reporting can also involve repetitive manual work.

This project addresses those challenges by building an automated pipeline that takes care of the process from ingestion to reporting.

It starts with an Excel workbook uploaded to Amazon S3. From there, the pipeline validates the file, converts it into a more suitable format for processing, loads the data into a warehouse, and uses dbt to clean, transform and test it. Once the transformations are complete, the resulting datasets are made available to Metabase for analysis and visualisation.

The workflow also includes error handling and email notifications, so failures are identified and reported rather than going unnoticed.

The broader goal is to build a pipeline that is reliable and predictable, handles repeated executions safely, and makes it easier to identify problems when they occur.

## The architecture at a glance

The architecture is organised around five main areas, each responsible for a different part of the workflow. Together, they provide everything needed to move data from its original source into a warehouse and eventually into reporting.

| Part | What it does | Built with |
|---|---|---|
| **Storage** | Holds the original workbook and the converted data files throughout the pipeline. | Amazon S3 |
| **Processing** | Validates and converts the workbook, then loads the resulting data into the warehouse. | AWS Lambda (Python) |
| **Warehouse** | Stores the ingested data and provides the environment for transformations and analytical queries. | Amazon Redshift Serverless, dbt Core |
| **Orchestration** | Detects new uploads, coordinates the processing stages and handles execution outcomes. | Amazon EventBridge, AWS Step Functions, Amazon SNS |
| **Reporting** | Provides a way to explore the transformed data through dashboards and visualisations. | Metabase |

Each area has a specific responsibility, but none operates in isolation. For example, the orchestration layer coordinates the processing functions, while the warehouse provides the data environment used by dbt and Metabase.

The complete architecture and the movement of data between these components are illustrated in the [README](../README.md). For a more detailed explanation of the execution workflow, see [The pipeline](04-pipeline.md).

## Key design choices

The architecture reflects a number of decisions about how data should be stored, processed, transformed and managed. The following sections explore the reasoning behind those decisions and how they influence the way the pipeline operates.

### Keep a copy of the data in the lake, and model it in the warehouse

The project uses both a data lake and a data warehouse, with each serving a different purpose.

Amazon S3 acts as the data lake, providing storage for the original workbook and its converted Parquet files. Amazon Redshift Serverless serves as the warehouse, where the ingested data is stored in tables and prepared for analysis.

Keeping the files in S3 provides a durable copy of the incoming data that can be accessed independently of the warehouse. Redshift, on the other hand, provides a structured environment where the data can be queried, transformed and combined using SQL.

**Why this approach:** Storing the files separately from the warehouse gives the project more flexibility when working with the data. The original source remains available even after the data has been loaded, while the warehouse provides an environment optimised for analytical workloads. It also means that transformations can be revised and executed again without having to rely entirely on the original Excel workbook.

### Convert the workbook to Parquet at the ingestion stage

Excel is convenient for collecting and sharing data, but it is not particularly suited to repeated processing by data pipelines. Its structure can vary, reading workbooks can be relatively expensive, and column types are not enforced as consistently as they are in analytical file formats.

The project converts the workbook into Apache Parquet during the initial processing stage. Parquet is a columnar storage format designed for analytical workloads. It supports defined data types, efficient compression and selective column reads, making it a more suitable format for the subsequent stages of the pipeline.

The conversion process focuses on changing the file format rather than cleaning or modifying the underlying values. For example, values such as `N/A` and empty text are preserved as they appear in the source instead of being automatically interpreted or replaced. Data cleaning and standardisation are handled later through the warehouse transformations, where the logic can be maintained and tested.

**Why this approach:** Converting the workbook once at the beginning gives the rest of the pipeline a consistent format to work with. It also keeps the initial processing stage focused on ingestion and conversion, leaving the more involved transformation logic to dbt.

### Load first, transform afterwards (ELT)

There are two common approaches to building data pipelines: Extract, Transform, Load (ETL) and Extract, Load, Transform (ELT).

With ETL, data is cleaned and transformed before it enters the warehouse. ELT takes a different approach by loading the source data first and performing the transformations within the warehouse.

This project follows the ELT approach. Once the workbook has been converted into Parquet, the data is loaded into Redshift in its raw form. dbt then handles the subsequent transformations, producing the cleaned and structured datasets used for reporting.

The transformation logic is maintained in SQL models, allowing individual models to be updated and executed without having to repeat the initial ingestion process.

**Why this approach:** Keeping the transformation logic separate from ingestion makes the pipeline easier to maintain and adapt. If a business rule changes or a model needs to be adjusted, the relevant dbt models can be modified and run again using the data already stored in Redshift. It also means the transformation logic is version-controlled, organised into reusable models and supported by automated tests.

### Use Lambda for the smaller processing tasks and Fargate for dbt

Not every stage of a data pipeline has the same processing requirements. Some tasks are short-lived and straightforward, while others need a more complete execution environment.

The project uses AWS Lambda for the initial processing tasks: validating and converting the Excel workbook, and loading the resulting Parquet files into Redshift. These functions are relatively short operations that can run independently without requiring a continuously available server.

The dbt stage has different requirements. It needs its dependencies, project files and database configuration available in a consistent environment, and its execution can take several minutes. For this, the project uses Amazon ECS with AWS Fargate to run dbt inside a Docker container.

The container image is built with the required Python environment, dbt dependencies and project files, then stored in Amazon ECR. When the pipeline reaches the transformation stage, ECS launches a Fargate task using that image. The task connects to Redshift, executes the dbt commands and exits when the job is complete.

**Why this approach:** Lambda keeps the smaller processing tasks lightweight and serverless, while Fargate provides the flexibility needed for the more involved transformation workload. Packaging dbt in a container also makes its execution environment consistent. The same image can be tested locally and deployed to AWS, reducing differences between development and cloud execution.

Running the task within the warehouse's private network also allows it to communicate with Redshift without exposing the warehouse to the wider internet. The compute resources are only provisioned for the duration of the task.

### Let Step Functions coordinate the workflow

A pipeline needs more than individual functions to process data. It also needs a way to determine which task runs first, when the next task should begin and what should happen when something fails. This is the role of workflow orchestration.

AWS Step Functions handles this responsibility in the project. It coordinates the different stages of the pipeline, from file conversion and warehouse loading to the dbt transformation task. Each stage is represented as part of a state machine, making the execution flow easier to follow and manage.

Step Functions also provides execution-level visibility. Each run has a recorded history showing the states it passed through, their outcomes and any errors encountered along the way.

Amazon EventBridge handles the initial trigger by detecting new workbook uploads in S3, while Amazon SNS is used to send notifications about the overall execution outcome.

**Why this approach:** Step Functions provides a managed way to coordinate a workflow made up of several AWS services without introducing another server or scheduling system. It also supports timeouts, error handling and execution history, which are useful when investigating failed runs or monitoring the behaviour of the pipeline.

For a workflow with a relatively small number of sequential processing stages, this provides the orchestration capabilities needed without the additional operational overhead of running a dedicated scheduler such as Apache Airflow.

### Make every run safe to repeat

Data pipelines are not always executed just once. A file might be uploaded again, a previous run might need to be repeated, or a task might need to be retried after an interruption. Without the right safeguards, these repeated executions can introduce duplicate records into the warehouse.

To prevent this, the project uses an idempotent loading strategy.

Each workbook is assigned a fingerprint derived from its contents. This fingerprint acts as an identifier for the particular version of the source data being processed. Every record loaded from that workbook carries the same fingerprint, making it possible to identify which records belong to a particular ingestion.

When a workbook is processed again, the loading process removes the records associated with its fingerprint before inserting the new ones. Both operations are handled within a single database transaction, so the replacement either completes successfully or is rolled back.

**Why this approach:** Repeated executions are a normal part of maintaining data pipelines. By making the loading process idempotent, the project can safely process the same workbook again without accumulating duplicate records. Using a transaction also protects the warehouse from being left with a partially completed replacement if something goes wrong during loading.

In practical terms, processing the same workbook multiple times produces the same final set of records as processing it once, assuming the source content and processing logic remain unchanged.

### Stop early when something is wrong

The quality of the data entering a pipeline has a direct impact on everything that follows. Processing an invalid workbook can lead to incomplete loads, failed transformations or misleading results in the dashboards.

The project addresses this through an initial validation stage in the conversion Lambda function. Before the workbook is converted, the function checks that the uploaded file is a valid Excel workbook and contains the three expected sheets: Events, Customers and Products.

If the file does not meet these requirements, processing stops and an error is returned to the workflow. The failed execution is then reported through an email notification, with information about the reason for the failure.

**Why this approach:** Catching structural problems at the ingestion stage prevents unsuitable files from progressing further into the pipeline. It is much easier to identify and address an invalid source file before it reaches the warehouse than to discover the problem after several processing and transformation steps have already taken place.

### Define the infrastructure in code

The AWS environment is managed using Terraform, with the resource definitions and configuration files maintained in the project repository.

Rather than creating and configuring resources individually through the AWS Console, Terraform describes the infrastructure in code. This includes the resources required for storage, processing, orchestration, networking, warehouse access and other parts of the pipeline.

The project also has a separate bootstrap configuration for provisioning the remote state storage used by Terraform. This keeps the foundation required for infrastructure state management separate from the main project resources.

**Why this approach:** Managing infrastructure through code makes the environment easier to reproduce, review and maintain. Changes can be tracked through version control, and resources can be provisioned or removed through repeatable Terraform commands. It also provides a clear record of how the cloud environment is structured, rather than relying on manually maintained configurations in the AWS Console.

### Give each component only the access it needs

Security is considered across the different parts of the architecture, particularly where database access, credentials and communication between services are involved.

The project uses a combination of network restrictions, IAM permissions, secrets management and database-level access controls to limit how each component interacts with the environment.

Some of the measures include:

- **Restricted warehouse connectivity:** Redshift accepts connections from an approved IP address and from the pipeline's own private network, limiting where database connections can originate.
- **Centralised secrets management:** Database passwords and other sensitive credentials are stored in AWS Secrets Manager and retrieved by the components that require them during execution. They are not committed to the repository.
- **Scoped IAM permissions:** Each Lambda function and the Fargate task operates with an IAM role that grants access to the resources required for its specific responsibilities.
- **Read-only reporting access:** Metabase connects to Redshift using a dedicated database user with read-only access limited to the finished gold tables.

**Why this approach:** Restricting access at different levels reduces unnecessary exposure across the architecture. Each component can perform its intended job without having unrestricted access to the rest of the environment. It also means the reporting layer can query the finished datasets without having permission to modify the underlying warehouse data.

## What the project guarantees

The combination of these design decisions gives the pipeline a number of important operational and data-quality characteristics.

- **Repeatable:** Given the same source data and processing logic, the pipeline produces consistent results.
- **Safe to re-run:** Processing the same workbook again does not introduce duplicate records because existing records associated with its fingerprint are replaced.
- **Tested:** Nineteen automated data-quality checks run during the dbt build. These include a reconciliation check that verifies that total revenue in the gold layer matches the corresponding raw data to the cent.
- **Observable:** Step Functions maintains an execution history for each run, while SNS notifications communicate whether the overall workflow succeeded or failed.
- **Controlled failure:** Invalid workbooks are rejected during initial validation, and failures in subsequent stages are handled by the workflow rather than being silently ignored.

Together, these characteristics make the pipeline easier to operate, troubleshoot and maintain while providing greater confidence in the data made available for reporting.

## What the project does not try to do

Understanding the project's scope is just as important as understanding its capabilities. The architecture is designed around a particular type of workload, and there are a few limitations worth keeping in mind.

- **Batch processing rather than streaming:** The pipeline processes uploaded workbooks as individual batches. It is not designed to ingest a continuous stream of transactions or events in real time.
- **Local dashboard deployment:** Metabase runs through a local Docker Compose setup rather than a hosted or production-facing deployment.
- **Sample data rather than live business operations:** The project uses a sample e-commerce dataset. Its primary focus is demonstrating the engineering behind data ingestion, processing, transformation and analytics rather than supporting decisions for an actual operating business.
- **A defined source structure:** The ingestion process expects the workbook to contain the three specified sheets. It is not intended to handle arbitrary Excel files or dynamically accommodate entirely different source schemas.

These boundaries keep the implementation focused on demonstrating a complete, automated ELT workflow without introducing infrastructure or processing requirements that the project does not currently need.

## Where to go next

With the overall architecture and its design principles established, the following documents explore individual parts of the implementation in more detail.

| If you want to know... | Read |
|---|---|
| How the data changes as it moves through the pipeline | [Data layers](02-data-layers.md) |
| What each AWS resource does and how the infrastructure is configured | [Infrastructure](03-infrastructure.md) |
| What happens at each stage when a new workbook is uploaded | [The pipeline](04-pipeline.md) |
| How the warehouse tables are structured and how data quality is tested | [Data model](05-data-model.md) |
| How to provision the infrastructure and run the project yourself | [Run it yourself](06-run-it-yourself.md) |
| How the dashboards are configured and what they reveal about the dataset | [Dashboards](07-dashboards.md) |
| How to investigate common problems and shut down the environment | [Troubleshooting](08-troubleshooting.md) |