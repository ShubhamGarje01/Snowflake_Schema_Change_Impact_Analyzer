# Snowflake_Schema_Change_Impact_Analyzer

A Schema Change Impact Analyzer identifies potential downstream dependencies affected by proposed database schema changes, such as column renames, additions, or deletions.
It analyzes views, stored procedures, downstream tables, and dbt models, then generates an impact report with recommended actions and automated email notifications before the schema change is implemented.

## Features & Working:

- Developed an automated change request workflow using Snowflake SQL Stored Procedures.
- Implemented SP_SUBMIT_CHANGE_REQUEST to accept and validate schema-change requests.
- Supported 3 schema change operations: RENAME_COLUMN, ADD_COLUMN, and DROP_COLUMN.
- Automated request insertion and REQUEST_ID generation, eliminating manual INSERT operations.
- Integrated request submission and impact analysis through a single stored procedure call.
- Implemented dependency identification across 4 object categories: views, stored procedures, downstream tables, and dbt models.
- Centralized impact findings, SQL evidence, and recommended actions in IMPACT_DETAIL.
- Automated impact report generation and developer email notifications using Snowflake email integration.

## Measurable Outcomes:
- 3 Types of schema changes are supported. **(RENAME, ADD_COLUMN, DROP_COLUMN)**
- 4 dependency categories is.covered by impact analys **(Tables, Views, Store Procedures, dbt models)**
- 2 Store Procedures, 1 to Raise a Change Request and another 1 to Submit the Change Request, Analyze and share the report on developer email.
- Manual intervention for identifying the impacted objects has been **reduced by 90-95%**.
