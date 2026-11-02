CREATE DATABASE IF NOT EXISTS VENDOR_UAT;

CREATE SCHEMA IF NOT EXISTS VENDOR_UAT.SILVER;
CREATE SCHEMA IF NOT EXISTS VENDOR_UAT.GOLD;
CREATE SCHEMA IF NOT EXISTS VENDOR_UAT.SCHEMA_GOVERNANCE;


--- creating vendor, address & summury base tables

CREATE OR REPLACE TABLE VENDOR_UAT.SILVER.VENDOR_MASTER (
    VENDOR_ID       NUMBER,
    VENDOR_NAME     VARCHAR(100),
    EMAIL_ADDRESS   VARCHAR(150),
    VENDOR_STATUS   VARCHAR(20),
    CREATED_DATE    DATE
);

CREATE OR REPLACE TABLE VENDOR_UAT.SILVER.VENDOR_ADDRESS (
    ADDRESS_ID      NUMBER,
    VENDOR_ID       NUMBER,
    ADDRESS_TYPE    VARCHAR(20),
    CITY            VARCHAR(100),
    COUNTRY         VARCHAR(100)
);

CREATE OR REPLACE TABLE VENDOR_UAT.GOLD.VENDOR_SUMMARY (
    VENDOR_ID       NUMBER,
    VENDOR_NAME     VARCHAR(100),
    VENDOR_STATUS   VARCHAR(20)
);


--- Insert data into base tables

INSERT INTO VENDOR_UAT.SILVER.VENDOR_MASTER
VALUES
    (101, 'ABC Suppliers', 'abc@example.com', 'ACTIVE', '2025-01-10'),
    (102, 'Global Traders', 'global@example.com', 'ACTIVE', '2025-02-15'),
    (103, 'Prime Vendors', 'prime@example.com', 'INACTIVE', '2025-03-20');


INSERT INTO VENDOR_UAT.SILVER.VENDOR_ADDRESS
VALUES
    (1, 101, 'OFFICE', 'Pune', 'India'),
    (2, 102, 'WAREHOUSE', 'Mumbai', 'India'),
    (3, 103, 'OFFICE', 'Delhi', 'India');


INSERT INTO VENDOR_UAT.GOLD.VENDOR_SUMMARY
SELECT VENDOR_ID, VENDOR_NAME, VENDOR_STATUS
FROM VENDOR_UAT.SILVER.VENDOR_MASTER;



--- creating base table dependent views

CREATE OR REPLACE VIEW VENDOR_UAT.SILVER.VW_VENDOR_DETAILS AS
SELECT VENDOR_ID, VENDOR_NAME, EMAIL_ADDRESS
FROM VENDOR_UAT.SILVER.VENDOR_MASTER;


CREATE OR REPLACE VIEW VENDOR_UAT.SILVER.VW_ACTIVE_VENDORS AS
SELECT VENDOR_ID, VENDOR_NAME
FROM VENDOR_UAT.SILVER.VENDOR_MASTER
WHERE VENDOR_STATUS = 'ACTIVE';


CREATE OR REPLACE VIEW VENDOR_UAT.GOLD.VW_VENDOR_SUMMARY AS
SELECT VENDOR_ID, VENDOR_NAME, VENDOR_STATUS
FROM VENDOR_UAT.SILVER.VENDOR_MASTER;



--- creating base table dependent store procs

CREATE OR REPLACE PROCEDURE
    VENDOR_UAT.SILVER.SP_GET_VENDOR_COUNT()
RETURNS NUMBER
LANGUAGE SQL
AS
$$
DECLARE
    V_COUNT NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO :V_COUNT
    FROM VENDOR_UAT.SILVER.VENDOR_MASTER;

    RETURN V_COUNT;
END;
$$;




CREATE OR REPLACE PROCEDURE
    VENDOR_UAT.GOLD.SP_REFRESH_VENDOR_SUMMARY()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO VENDOR_UAT.GOLD.VENDOR_SUMMARY
    SELECT VENDOR_ID, VENDOR_NAME, VENDOR_STATUS
    FROM VENDOR_UAT.SILVER.VENDOR_MASTER;

    RETURN 'SUCCESS';
END;
$$;



--- creating metadata analyzer tables to store the metadata info

CREATE TABLE IF NOT EXISTS
    VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST (
        REQUEST_ID NUMBER AUTOINCREMENT START 1 INCREMENT 1,
        REQUESTED_BY VARCHAR(200) DEFAULT CURRENT_USER(),
        DEVELOPER_EMAIL VARCHAR(320),
        DATABASE_NAME VARCHAR(255),
        SCHEMA_NAME VARCHAR(255),
        TABLE_NAME VARCHAR(255),
        CHANGE_TYPE VARCHAR(30),
        OLD_COLUMN_NAME VARCHAR(255),
        NEW_COLUMN_NAME VARCHAR(255),
        NEW_DATA_TYPE VARCHAR(100),
        CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
        STATUS VARCHAR(30) DEFAULT 'SUBMITTED'
    );


CREATE TABLE IF NOT EXISTS
    VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL (
        REQUEST_ID NUMBER,
        OBJECT_DATABASE VARCHAR(255),
        OBJECT_SCHEMA VARCHAR(255),
        OBJECT_NAME VARCHAR(255),
        OBJECT_TYPE VARCHAR(50),
        IMPACT_TYPE VARCHAR(30),
        IMPACT_EVIDENCE VARCHAR,
        RECOMMENDED_ACTION VARCHAR,
        ANALYZED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );


CREATE TABLE IF NOT EXISTS
    VENDOR_UAT.SCHEMA_GOVERNANCE.DBT_MODEL_INVENTORY (
        PROJECT_NAME VARCHAR(255),
        MODEL_NAME VARCHAR(255),
        FILE_PATH VARCHAR(1000),
        DATABASE_NAME VARCHAR(255),
        SCHEMA_NAME VARCHAR(255),
        MATERIALIZATION VARCHAR(50),
        SQL_TEXT VARCHAR,
        LAST_SYNCED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );


CREATE TABLE IF NOT EXISTS
    VENDOR_UAT.SCHEMA_GOVERNANCE.EMAIL_NOTIFICATION_LOG (
        REQUEST_ID NUMBER,
        RECIPIENT_EMAIL VARCHAR(320),
        EMAIL_SUBJECT VARCHAR(500),
        SENT_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
        STATUS VARCHAR(30),
        DETAILS VARCHAR
    );




--- configuring email notification :

CREATE NOTIFICATION INTEGRATION IMPACT_EMAIL_INT
    TYPE = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('shubhgarje95@gmail.com');


-- testing email notification

CALL SYSTEM$SEND_EMAIL(
    'IMPACT_EMAIL_INT',  --- notification integration name
    'shubhgarje95@gmail.com',
    'Vendor UAT - Impact Analyzer Test',  --- Email Subject
    'Email notification setup test successful. All the bese for next development related to Snowflake SQL Schema Change Impact Analyzer tool.'  -- Email Body
);
--- email has been delivered on gmail testing is complete.


-- verifying objects

SHOW SCHEMAS IN DATABASE VENDOR_UAT;

SHOW TABLES IN SCHEMA VENDOR_UAT.SILVER;

SHOW TABLES IN SCHEMA VENDOR_UAT.GOLD;

SHOW VIEWS IN DATABASE VENDOR_UAT;

SHOW PROCEDURES IN DATABASE VENDOR_UAT;

SHOW TABLES IN SCHEMA VENDOR_UAT.SCHEMA_GOVERNANCE;


/*

What we have completed so far:

We have prepared the foundation for the Snowflake SQL Impact Analyzer use case:
    1. Created database VENDOR_UAT with business schemas SILVER and GOLD, plus SCHEMA_GOVERNANCE for the analyzer.
    2. Created sample vendor tables, views, and stored procedures to simulate dependencies across schemas.
    3. Created governance tables to store change requests, impact details, dbt model inventory, and email notification logs.
    4. Configured and tested Snowflake email notifications successfully.

Our goal: Before a developer renames, adds, or removes a column, the analyzer should identify potentially impacted objects, recommend actions, and email the impact report—without changing application SQL or dbt code automatically.


-- Metadata collector and dependency analyzer : 

We are going to implement this in two parts:

    - Metadata collector :--> Capture tables, columns, views, and their SQL definitions from VENDOR_UAT.SILVER and VENDOR_UAT.GOLD.
    - Dependency analyzer :-->  Use that metadata to identify objects potentially affected by a requested schema change.

*/

-- Creating metadata inventory tables 

USE DATABASE VENDOR_UAT;
USE SCHEMA SCHEMA_GOVERNANCE;

CREATE TABLE IF NOT EXISTS OBJECT_METADATA (
    DATABASE_NAME VARCHAR(255),
    SCHEMA_NAME VARCHAR(255),
    OBJECT_NAME VARCHAR(255),
    OBJECT_TYPE VARCHAR(50),
    LAST_ALTERED TIMESTAMP_LTZ,
    COLLECTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS COLUMN_METADATA (
    DATABASE_NAME VARCHAR(255),
    SCHEMA_NAME VARCHAR(255),
    TABLE_NAME VARCHAR(255),
    COLUMN_NAME VARCHAR(255),
    DATA_TYPE VARCHAR(100),
    IS_NULLABLE VARCHAR(10),
    ORDINAL_POSITION NUMBER,
    COLLECTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS VIEW_METADATA (
    DATABASE_NAME VARCHAR(255),
    SCHEMA_NAME VARCHAR(255),
    VIEW_NAME VARCHAR(255),
    VIEW_DEFINITION VARCHAR,
    COLLECTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);



--- refresh & collect the metadata tables (OBJECT_METADATA, COLUMN_METADATA, VIEW_METADATA)
/*

We are performing 2 actions for each table :
    
    1. DELETE: Remove the previously collected column metadata for SILVER and GOLD.
    2. INSERT: Collect the current column metadata from Snowflake and save it in our governance table.

This is called a full refresh of the metadata inventory. It avoids accumulating duplicate snapshots every time we run the collection.

Snowflake's Information Schema exposes table, column, and view-definition metadata. We are just pulling the latest info from there, into schema_governance schema, so we can utilize it for IMPACT_ANALYZER.
*/

-- Refresh object inventory
DELETE FROM VENDOR_UAT.SCHEMA_GOVERNANCE.OBJECT_METADATA
WHERE DATABASE_NAME = 'VENDOR_UAT'
  AND SCHEMA_NAME IN ('SILVER', 'GOLD');

INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.OBJECT_METADATA
    (DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE, LAST_ALTERED)
SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    TABLE_TYPE,
    LAST_ALTERED
FROM VENDOR_UAT.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('SILVER', 'GOLD');



-- Refresh column inventory
DELETE FROM VENDOR_UAT.SCHEMA_GOVERNANCE.COLUMN_METADATA
WHERE DATABASE_NAME = 'VENDOR_UAT'
  AND SCHEMA_NAME IN ('SILVER', 'GOLD');

INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.COLUMN_METADATA
    (DATABASE_NAME, SCHEMA_NAME, TABLE_NAME,
     COLUMN_NAME, DATA_TYPE, IS_NULLABLE, ORDINAL_POSITION)
SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    ORDINAL_POSITION
FROM VENDOR_UAT.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN ('SILVER', 'GOLD');



-- Refresh view definitions
DELETE FROM VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA
WHERE DATABASE_NAME = 'VENDOR_UAT'
  AND SCHEMA_NAME IN ('SILVER', 'GOLD');

INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA
    (DATABASE_NAME, SCHEMA_NAME, VIEW_NAME, VIEW_DEFINITION)
SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    VIEW_DEFINITION
FROM VENDOR_UAT.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA IN ('SILVER', 'GOLD');



SELECT * FROM VENDOR_UAT.SCHEMA_GOVERNANCE.OBJECT_METADATA
ORDER BY SCHEMA_NAME, OBJECT_NAME; --- All objects with object type, obj name, Database name & Schema name.

SELECT * FROM VENDOR_UAT.SCHEMA_GOVERNANCE.COLUMN_METADATA
ORDER BY SCHEMA_NAME, TABLE_NAME, ORDINAL_POSITION; -- all objects with db & schema having column name & type for each table & view

SELECT
    SCHEMA_NAME,
    VIEW_NAME,
    VIEW_DEFINITION
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA
ORDER BY SCHEMA_NAME, VIEW_NAME;   --- all views from all schemas and their definition / DDL.




---- Building the initial dependency analyzer

SET TARGET_TABLE = 'VENDOR_MASTER';
SET TARGET_COLUMN = 'VENDOR_ID';

SELECT
    SCHEMA_NAME AS IMPACTED_SCHEMA,
    VIEW_NAME AS IMPACTED_OBJECT,
    'VIEW' AS OBJECT_TYPE,
    'POTENTIAL IMPACT' AS IMPACT_TYPE,
    'Review the view definition and update references if required'
        AS RECOMMENDED_ACTION,
    VIEW_DEFINITION AS IMPACT_EVIDENCE
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA
WHERE UPPER(VIEW_DEFINITION) LIKE '%' || $TARGET_TABLE || '%'
  AND UPPER(VIEW_DEFINITION) LIKE '%' || $TARGET_COLUMN || '%'
ORDER BY SCHEMA_NAME, VIEW_NAME;


 --- Troubleshoot
 
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    VIEW_DEFINITION
FROM VENDOR_UAT.INFORMATION_SCHEMA.VIEWS  ---> information schema
WHERE TABLE_SCHEMA IN ('SILVER', 'GOLD')
ORDER BY TABLE_SCHEMA, TABLE_NAME;



SELECT
    SCHEMA_NAME,
    VIEW_NAME,
    VIEW_DEFINITION
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA  --- schema governance
ORDER BY SCHEMA_NAME, VIEW_NAME;



SELECT
    SCHEMA_NAME AS IMPACTED_SCHEMA,
    VIEW_NAME AS IMPACTED_OBJECT,
    'VIEW' AS OBJECT_TYPE,
    'POTENTIAL IMPACT' AS IMPACT_TYPE,
    'Review this view before renaming VENDOR_ID'
        AS RECOMMENDED_ACTION,
    VIEW_DEFINITION AS IMPACT_EVIDENCE
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA
WHERE UPPER(VIEW_DEFINITION) LIKE '%VENDOR_MASTER%'
  AND UPPER(VIEW_DEFINITION) LIKE '%VENDOR_ID%'
ORDER BY SCHEMA_NAME, VIEW_NAME;





SELECT
    SCHEMA_NAME AS IMPACTED_SCHEMA,
    VIEW_NAME AS IMPACTED_OBJECT,
    'VIEW' AS OBJECT_TYPE,
    'POTENTIAL IMPACT' AS IMPACT_TYPE,
    'Review references to VENDOR_ID'
        AS RECOMMENDED_ACTION
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA
WHERE UPPER(VIEW_DEFINITION) LIKE '%VENDOR_MASTER%'
  AND UPPER(VIEW_DEFINITION) LIKE '%VENDOR_ID%'

UNION ALL

SELECT
    SCHEMA_NAME,
    VIEW_NAME,
    'VIEW',
    'POTENTIAL IMPACT',
    'Review references to VENDOR_NAME'
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA
WHERE UPPER(VIEW_DEFINITION) LIKE '%VENDOR_MASTER%'
  AND UPPER(VIEW_DEFINITION) LIKE '%VENDOR_NAME%'

ORDER BY 1, 2;



--- Step : 3 : now connecting change requests to impact results 

-- Step 3-A  :  Submit a change request

INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST  ---> inserting a CR
(
    DEVELOPER_EMAIL,
    DATABASE_NAME,
    SCHEMA_NAME,
    TABLE_NAME,
    CHANGE_TYPE,
    OLD_COLUMN_NAME,
    NEW_COLUMN_NAME
)
VALUES
(
    'shubhgarje95@gmail.com',
    'VENDOR_UAT',
    'SILVER',
    'VENDOR_MASTER',
    'RENAME_COLUMN',
    'VENDOR_ID',
    'CLIENT_ID'
);


SELECT *
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST  --> validating raised CR
WHERE TABLE_NAME = 'VENDOR_MASTER'
  AND CHANGE_TYPE = 'RENAME_COLUMN'
ORDER BY REQUEST_ID DESC
LIMIT 5;



-- step 3 B : Save impacted views against that request

INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
(
    REQUEST_ID,
    OBJECT_DATABASE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    OBJECT_TYPE,
    IMPACT_TYPE,
    IMPACT_EVIDENCE,
    RECOMMENDED_ACTION
)
SELECT
    cr.REQUEST_ID,
    cr.DATABASE_NAME,
    vm.SCHEMA_NAME,
    vm.VIEW_NAME,
    'VIEW',
    'POTENTIAL IMPACT',
    vm.VIEW_DEFINITION,
    'Review references to VENDOR_ID and update to CLIENT_ID if required'
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST cr
JOIN VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA vm
    ON UPPER(vm.VIEW_DEFINITION) LIKE
       '%' || UPPER(cr.TABLE_NAME) || '%'
   AND UPPER(vm.VIEW_DEFINITION) LIKE
       '%' || UPPER(cr.OLD_COLUMN_NAME) || '%'
WHERE cr.REQUEST_ID = 1
  AND cr.CHANGE_TYPE = 'RENAME_COLUMN';



--- Verify saved results 

SELECT
    REQUEST_ID,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    OBJECT_TYPE,
    IMPACT_TYPE,
    RECOMMENDED_ACTION,
    IMPACT_EVIDENCE
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
WHERE REQUEST_ID = 1
ORDER BY OBJECT_SCHEMA, OBJECT_NAME;


-- now lets create store procedure for submit_change_request, so we can pass Change_request_id to analyze the request & impact


CREATE OR REPLACE PROCEDURE
VENDOR_UAT.SCHEMA_GOVERNANCE.SP_SUBMIT_CHANGE_REQUEST
(
    P_DEVELOPER_EMAIL VARCHAR,
    P_DATABASE_NAME   VARCHAR,
    P_SCHEMA_NAME     VARCHAR,
    P_TABLE_NAME      VARCHAR,
    P_CHANGE_TYPE     VARCHAR,
    P_OLD_COLUMN_NAME VARCHAR,
    P_NEW_COLUMN_NAME VARCHAR,
    P_NEW_DATA_TYPE   VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    V_TABLE_COUNT       NUMBER DEFAULT 0;
    V_OLD_COLUMN_COUNT  NUMBER DEFAULT 0;
    V_NEW_COLUMN_COUNT  NUMBER DEFAULT 0;
    V_REQUEST_ID        NUMBER;
    V_INSERT_QUERY_ID   VARCHAR;
    V_ANALYSIS_RESULT   VARCHAR;
    V_CHANGE_TYPE       VARCHAR;
    V_DATABASE_NAME     VARCHAR;
    V_SCHEMA_NAME       VARCHAR;
    V_TABLE_NAME        VARCHAR;

BEGIN

    -- 1. Normalize inputs
    V_CHANGE_TYPE   := UPPER(TRIM(P_CHANGE_TYPE));
    V_DATABASE_NAME := UPPER(TRIM(P_DATABASE_NAME));
    V_SCHEMA_NAME   := UPPER(TRIM(P_SCHEMA_NAME));
    V_TABLE_NAME    := UPPER(TRIM(P_TABLE_NAME));

    -- 2. Validate required fields
    IF (P_DEVELOPER_EMAIL IS NULL
        OR V_DATABASE_NAME IS NULL
        OR V_SCHEMA_NAME IS NULL
        OR V_TABLE_NAME IS NULL
        OR V_CHANGE_TYPE IS NULL) THEN

        RETURN 'REJECTED: Required information is missing.';
    END IF;

    -- 3. Validate supported database and schemas
    IF (V_DATABASE_NAME <> 'VENDOR_UAT'
        OR V_SCHEMA_NAME NOT IN ('SILVER', 'GOLD')) THEN

        RETURN 'REJECTED: Unsupported database or schema.';
    END IF;

    -- 4. Validate change type
    IF (V_CHANGE_TYPE NOT IN
        ('RENAME_COLUMN', 'ADD_COLUMN', 'DROP_COLUMN')) THEN

        RETURN 'REJECTED: Unsupported change type.';
    END IF;

    -- 5. Check whether target table exists
    SELECT COUNT(*)
    INTO :V_TABLE_COUNT
    FROM VENDOR_UAT.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = :V_SCHEMA_NAME
      AND TABLE_NAME = :V_TABLE_NAME
      AND TABLE_TYPE = 'BASE TABLE';

    IF (V_TABLE_COUNT = 0) THEN
        RETURN 'REJECTED: Target table does not exist.';
    END IF;

    -- 6. Validate column requirements
    IF (V_CHANGE_TYPE IN ('RENAME_COLUMN', 'DROP_COLUMN')) THEN

        IF (P_OLD_COLUMN_NAME IS NULL) THEN
            RETURN 'REJECTED: Old column name is required.';
        END IF;

        SELECT COUNT(*)
        INTO :V_OLD_COLUMN_COUNT
        FROM VENDOR_UAT.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = :V_SCHEMA_NAME
          AND TABLE_NAME = :V_TABLE_NAME
          AND COLUMN_NAME = UPPER(TRIM(:P_OLD_COLUMN_NAME));

        IF (V_OLD_COLUMN_COUNT = 0) THEN
            RETURN 'REJECTED: Old column does not exist.';
        END IF;

    END IF;

    IF (V_CHANGE_TYPE IN ('RENAME_COLUMN', 'ADD_COLUMN')) THEN

        IF (P_NEW_COLUMN_NAME IS NULL) THEN
            RETURN 'REJECTED: New column name is required.';
        END IF;

        SELECT COUNT(*)
        INTO :V_NEW_COLUMN_COUNT
        FROM VENDOR_UAT.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = :V_SCHEMA_NAME
          AND TABLE_NAME = :V_TABLE_NAME
          AND COLUMN_NAME = UPPER(TRIM(:P_NEW_COLUMN_NAME));

        IF (V_NEW_COLUMN_COUNT > 0) THEN
            RETURN 'REJECTED: New column already exists.';
        END IF;

    END IF;

    IF (V_CHANGE_TYPE = 'ADD_COLUMN'
        AND P_NEW_DATA_TYPE IS NULL) THEN

        RETURN 'REJECTED: New data type is required for ADD_COLUMN.';

    END IF;

    -- 7. Insert validated request
    INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
(
    DEVELOPER_EMAIL,
    DATABASE_NAME,
    SCHEMA_NAME,
    TABLE_NAME,
    CHANGE_TYPE,
    OLD_COLUMN_NAME,
    NEW_COLUMN_NAME,
    NEW_DATA_TYPE
)
VALUES
(
    TRIM(:P_DEVELOPER_EMAIL),
    :V_DATABASE_NAME,
    :V_SCHEMA_NAME,
    :V_TABLE_NAME,
    :V_CHANGE_TYPE,
    UPPER(TRIM(:P_OLD_COLUMN_NAME)),
    UPPER(TRIM(:P_NEW_COLUMN_NAME)),
    :P_NEW_DATA_TYPE
);

    -- 8. Capture the identity generated by this INSERT
    V_INSERT_QUERY_ID := LAST_QUERY_ID();

    SELECT MAX(REQUEST_ID)
    INTO :V_REQUEST_ID
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
         AT (STATEMENT => :V_INSERT_QUERY_ID);

    -- 9. Invoke the existing analyzer
    CALL VENDOR_UAT.SCHEMA_GOVERNANCE.SP_ANALYZE_CHANGE_REQUEST(
        :V_REQUEST_ID
    ) INTO :V_ANALYSIS_RESULT;

    -- 10. Return final result
    RETURN
        'Request submitted successfully. REQUEST_ID = '
        || V_REQUEST_ID
        || '. Analyzer result: '
        || COALESCE(V_ANALYSIS_RESULT, 'Completed.');

END;
$$;


-- now lets test it -- calling store procedure with parameters

CALL VENDOR_UAT.SCHEMA_GOVERNANCE.SP_SUBMIT_CHANGE_REQUEST
(
    'shubhgarje95@gmail.com',
    'VENDOR_UAT',
    'SILVER',
    'VENDOR_MASTER',
    'RENAME_COLUMN',
    'VENDOR_STATUS',
    'STATUS',
    NULL
);


select * from SCHEMA_GOVERNANCE.CHANGE_REQUEST;

SELECT *
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
WHERE REQUEST_ID = 101;


SELECT *
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.EMAIL_NOTIFICATION_LOG
WHERE REQUEST_ID = 101;


--- automating workflow with store procedure (submit a change request --> identify impacted views --> save results and update status)

CREATE OR REPLACE PROCEDURE
    VENDOR_UAT.SCHEMA_GOVERNANCE.SP_ANALYZE_CHANGE_REQUEST(
        P_REQUEST_ID NUMBER
    )
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_REQUEST_COUNT NUMBER;
    V_IMPACT_COUNT NUMBER;
    V_CHANGE_TYPE VARCHAR;
BEGIN
    -- 1. Validate that the change request exists
    SELECT COUNT(*)
      INTO :V_REQUEST_COUNT
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    WHERE REQUEST_ID = :P_REQUEST_ID;

    IF (V_REQUEST_COUNT = 0) THEN
        RETURN 'ERROR: Change request not found.';
    END IF;

    -- 2. Read the requested change type
    SELECT MAX(CHANGE_TYPE)
      INTO :V_CHANGE_TYPE
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    WHERE REQUEST_ID = :P_REQUEST_ID;

    IF (V_CHANGE_TYPE <> 'RENAME_COLUMN') THEN
        RETURN 'Not supported yet: ' || V_CHANGE_TYPE;
    END IF;

    -- 3. Mark the request as processing
    UPDATE VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    SET STATUS = 'PROCESSING'
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 4. Remove previous results for this request.
    -- This makes reruns duplicate-safe.
    DELETE FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 5. Find potentially impacted views and save the results
    INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    (
        REQUEST_ID,
        OBJECT_DATABASE,
        OBJECT_SCHEMA,
        OBJECT_NAME,
        OBJECT_TYPE,
        IMPACT_TYPE,
        IMPACT_EVIDENCE,
        RECOMMENDED_ACTION
    )
    SELECT
        CR.REQUEST_ID,
        CR.DATABASE_NAME,
        VM.SCHEMA_NAME,
        VM.VIEW_NAME,
        'VIEW',
        'POTENTIAL IMPACT',
        VM.VIEW_DEFINITION,
        'Review references to '
            || CR.OLD_COLUMN_NAME
            || ' and update to '
            || CR.NEW_COLUMN_NAME
            || ' if required'
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST CR
    JOIN VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA VM
      ON UPPER(VM.VIEW_DEFINITION)
             LIKE '%' || UPPER(CR.TABLE_NAME) || '%'
     AND UPPER(VM.VIEW_DEFINITION)
             LIKE '%' || UPPER(CR.OLD_COLUMN_NAME) || '%'
    WHERE CR.REQUEST_ID = :P_REQUEST_ID
      AND CR.CHANGE_TYPE = 'RENAME_COLUMN';

    -- 6. Count the saved impacts
    SELECT COUNT(*)
      INTO :V_IMPACT_COUNT
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 7. Mark analysis as complete
    UPDATE VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    SET STATUS = 'ANALYZED'
    WHERE REQUEST_ID = :P_REQUEST_ID;

    RETURN 'Analysis completed. Request ID: '
        || P_REQUEST_ID
        || '; impacted objects: '
        || V_IMPACT_COUNT;

END;
$$;



--- store proc call 
CALL VENDOR_UAT.SCHEMA_GOVERNANCE.SP_ANALYZE_CHANGE_REQUEST(1);
-- got the output : Analysis completed. Request ID: 1; impacted objects: 3



--- validating Change Request : should be showing change_type = rename, status = analyzed
-- Check the change request status

SELECT REQUEST_ID, CHANGE_TYPE, STATUS, *
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
WHERE REQUEST_ID = 1;


-- Check the impact objects (obj type & obj name) with recommended actions:
SELECT
    REQUEST_ID,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    OBJECT_TYPE,
    RECOMMENDED_ACTION
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
WHERE REQUEST_ID = 1
ORDER BY OBJECT_SCHEMA, OBJECT_NAME;


--- running the store procedure again, to validate the duplicate request does not get created.


--- store proc call 
CALL VENDOR_UAT.SCHEMA_GOVERNANCE.SP_ANALYZE_CHANGE_REQUEST(1);


-- Check the change request status
SELECT REQUEST_ID, CHANGE_TYPE, STATUS, *
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
WHERE REQUEST_ID = 1;
--- in Change Request table, we can see only one entry for request ID, that means, duplication of same request has been handle in store procedure. 


-- Check the impact objects (obj type & obj name) with recommended actions:
SELECT
    REQUEST_ID,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    OBJECT_TYPE,
    RECOMMENDED_ACTION
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
WHERE REQUEST_ID = 1
ORDER BY OBJECT_SCHEMA, OBJECT_NAME;


--- replacing above mentioned store procedure : existing logic : submit a change request --> identify impacted views --> save results and update status
-- new logic added on top of existing logic : duplicate-safe processing --> email sending --> email sent logs


CREATE OR REPLACE PROCEDURE
    VENDOR_UAT.SCHEMA_GOVERNANCE.SP_ANALYZE_CHANGE_REQUEST(
        P_REQUEST_ID NUMBER
    )
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_REQUEST_COUNT NUMBER DEFAULT 0;
    V_TABLE_COUNT NUMBER DEFAULT 0;
    V_OLD_COLUMN_COUNT NUMBER DEFAULT 0;
    V_NEW_COLUMN_COUNT NUMBER DEFAULT 0;
    V_IMPACT_COUNT NUMBER DEFAULT 0;

    V_CHANGE_TYPE VARCHAR;
    V_DATABASE_NAME VARCHAR;
    V_SCHEMA_NAME VARCHAR;
    V_TABLE_NAME VARCHAR;
    V_OLD_COLUMN_NAME VARCHAR;
    V_NEW_COLUMN_NAME VARCHAR;
    V_EMAIL VARCHAR;

    V_SUBJECT VARCHAR;
    V_BODY VARCHAR;
    V_IMPACT_SUMMARY VARCHAR;
    V_EMAIL_STATUS VARCHAR DEFAULT 'FAILED';
    V_EMAIL_ERROR VARCHAR DEFAULT NULL;

BEGIN

    -- 1. Confirm request exists
    SELECT COUNT(*)
      INTO :V_REQUEST_COUNT
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    WHERE REQUEST_ID = :P_REQUEST_ID;

    IF (V_REQUEST_COUNT = 0) THEN
        RETURN 'ERROR: Change request not found.';
    END IF;

    -- 2. Read request details
    SELECT
        MAX(UPPER(CHANGE_TYPE)),
        MAX(UPPER(DATABASE_NAME)),
        MAX(UPPER(SCHEMA_NAME)),
        MAX(UPPER(TABLE_NAME)),
        MAX(UPPER(OLD_COLUMN_NAME)),
        MAX(UPPER(NEW_COLUMN_NAME)),
        MAX(DEVELOPER_EMAIL)
    INTO
        :V_CHANGE_TYPE,
        :V_DATABASE_NAME,
        :V_SCHEMA_NAME,
        :V_TABLE_NAME,
        :V_OLD_COLUMN_NAME,
        :V_NEW_COLUMN_NAME,
        :V_EMAIL
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 3. Validate supported change type
    IF (
        V_CHANGE_TYPE IS NULL
        OR V_CHANGE_TYPE NOT IN (
            'RENAME_COLUMN',
            'ADD_COLUMN',
            'DROP_COLUMN'
        )
    ) THEN
        RETURN 'ERROR: Unsupported change type.';
    END IF;

    -- 4. Validate developer email
    IF (V_EMAIL IS NULL OR TRIM(V_EMAIL) = '') THEN
        RETURN 'ERROR: Developer email is missing.';
    END IF;

    -- 5. Restrict analysis to approved database and schemas
    IF (
        V_DATABASE_NAME IS NULL
        OR V_DATABASE_NAME <> 'VENDOR_UAT'
        OR V_SCHEMA_NAME NOT IN ('SILVER', 'GOLD')
        OR V_TABLE_NAME IS NULL
        OR TRIM(V_TABLE_NAME) = ''
    ) THEN
        RETURN 'ERROR: Only VENDOR_UAT.SILVER and VENDOR_UAT.GOLD are supported.';
    END IF;

    -- 6. Validate required column names
    IF (
        V_CHANGE_TYPE = 'RENAME_COLUMN'
        AND (
            V_OLD_COLUMN_NAME IS NULL
            OR V_NEW_COLUMN_NAME IS NULL
            OR TRIM(V_OLD_COLUMN_NAME) = ''
            OR TRIM(V_NEW_COLUMN_NAME) = ''
            OR V_OLD_COLUMN_NAME = V_NEW_COLUMN_NAME
        )
    ) THEN
        RETURN 'ERROR: Rename requires different old and new column names.';
    END IF;

    IF (
        V_CHANGE_TYPE = 'ADD_COLUMN'
        AND (
            V_NEW_COLUMN_NAME IS NULL
            OR TRIM(V_NEW_COLUMN_NAME) = ''
        )
    ) THEN
        RETURN 'ERROR: Add column requires a new column name.';
    END IF;

    IF (
        V_CHANGE_TYPE = 'DROP_COLUMN'
        AND (
            V_OLD_COLUMN_NAME IS NULL
            OR TRIM(V_OLD_COLUMN_NAME) = ''
        )
    ) THEN
        RETURN 'ERROR: Drop column requires an old column name.';
    END IF;

    -- 7. Confirm target table exists
    SELECT COUNT(*)
      INTO :V_TABLE_COUNT
    FROM VENDOR_UAT.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = :V_SCHEMA_NAME
      AND TABLE_NAME = :V_TABLE_NAME;

    IF (V_TABLE_COUNT = 0) THEN
        RETURN 'ERROR: Target table not found in VENDOR_UAT.';
    END IF;

    -- 8. Validate current column state
    IF (V_CHANGE_TYPE IN ('RENAME_COLUMN', 'DROP_COLUMN')) THEN

        SELECT COUNT(*)
          INTO :V_OLD_COLUMN_COUNT
        FROM VENDOR_UAT.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = :V_SCHEMA_NAME
          AND TABLE_NAME = :V_TABLE_NAME
          AND COLUMN_NAME = :V_OLD_COLUMN_NAME;

        IF (V_OLD_COLUMN_COUNT = 0) THEN
            RETURN 'ERROR: Old column does not exist in target table.';
        END IF;

    END IF;

    IF (V_CHANGE_TYPE = 'RENAME_COLUMN') THEN

        SELECT COUNT(*)
          INTO :V_NEW_COLUMN_COUNT
        FROM VENDOR_UAT.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = :V_SCHEMA_NAME
          AND TABLE_NAME = :V_TABLE_NAME
          AND COLUMN_NAME = :V_NEW_COLUMN_NAME;

        IF (V_NEW_COLUMN_COUNT > 0) THEN
            RETURN 'ERROR: New column name already exists.';
        END IF;

    END IF;

    IF (V_CHANGE_TYPE = 'ADD_COLUMN') THEN

        SELECT COUNT(*)
          INTO :V_NEW_COLUMN_COUNT
        FROM VENDOR_UAT.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = :V_SCHEMA_NAME
          AND TABLE_NAME = :V_TABLE_NAME
          AND COLUMN_NAME = :V_NEW_COLUMN_NAME;

        IF (V_NEW_COLUMN_COUNT > 0) THEN
            RETURN 'ERROR: Column already exists in target table.';
        END IF;

    END IF;

    -- 9. Mark request as processing
    UPDATE VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    SET STATUS = 'PROCESSING'
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 10. Delete previous analysis results for safe reruns
    DELETE FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 11. Analyze views
    INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    (
        REQUEST_ID,
        OBJECT_DATABASE,
        OBJECT_SCHEMA,
        OBJECT_NAME,
        OBJECT_TYPE,
        IMPACT_TYPE,
        IMPACT_EVIDENCE,
        RECOMMENDED_ACTION
    )
    SELECT
        CR.REQUEST_ID,
        CR.DATABASE_NAME,
        VM.SCHEMA_NAME,
        VM.VIEW_NAME,
        'VIEW',
        'POTENTIAL IMPACT',
        VM.VIEW_DEFINITION,
        CASE
            WHEN CR.CHANGE_TYPE = 'RENAME_COLUMN' THEN
                'Review references to ' || CR.OLD_COLUMN_NAME
                || ' and update to ' || CR.NEW_COLUMN_NAME
            WHEN CR.CHANGE_TYPE = 'DROP_COLUMN' THEN
                'Review references to ' || CR.OLD_COLUMN_NAME
                || ' before dropping the column'
            WHEN CR.CHANGE_TYPE = 'ADD_COLUMN' THEN
                'Review whether the new column ' || CR.NEW_COLUMN_NAME
                || ' should be incorporated'
        END
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST CR
    JOIN VENDOR_UAT.SCHEMA_GOVERNANCE.VIEW_METADATA VM
      ON UPPER(VM.VIEW_DEFINITION)
             LIKE '%' || UPPER(CR.TABLE_NAME) || '%'
     AND (
            (
                CR.CHANGE_TYPE IN ('RENAME_COLUMN', 'DROP_COLUMN')
                AND UPPER(VM.VIEW_DEFINITION)
                    LIKE '%' || UPPER(CR.OLD_COLUMN_NAME) || '%'
            )
            OR CR.CHANGE_TYPE = 'ADD_COLUMN'
         )
    WHERE CR.REQUEST_ID = :P_REQUEST_ID;

    -- 12. Analyze stored procedures
    INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    (
        REQUEST_ID,
        OBJECT_DATABASE,
        OBJECT_SCHEMA,
        OBJECT_NAME,
        OBJECT_TYPE,
        IMPACT_TYPE,
        IMPACT_EVIDENCE,
        RECOMMENDED_ACTION
    )
    SELECT
        CR.REQUEST_ID,
        'VENDOR_UAT',
        P.PROCEDURE_SCHEMA,
        P.PROCEDURE_NAME,
        'PROCEDURE',
        'POTENTIAL IMPACT',
        P.PROCEDURE_DEFINITION,
        CASE
            WHEN CR.CHANGE_TYPE = 'RENAME_COLUMN' THEN
                'Review references to ' || CR.OLD_COLUMN_NAME
                || ' and update to ' || CR.NEW_COLUMN_NAME
            WHEN CR.CHANGE_TYPE = 'DROP_COLUMN' THEN
                'Review references to ' || CR.OLD_COLUMN_NAME
                || ' before dropping the column'
            WHEN CR.CHANGE_TYPE = 'ADD_COLUMN' THEN
                'Review whether the new column ' || CR.NEW_COLUMN_NAME
                || ' should be incorporated'
        END
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST CR
    JOIN VENDOR_UAT.INFORMATION_SCHEMA.PROCEDURES P
      ON UPPER(P.PROCEDURE_DEFINITION)
             LIKE '%' || UPPER(CR.TABLE_NAME) || '%'
     AND (
            (
                CR.CHANGE_TYPE IN ('RENAME_COLUMN', 'DROP_COLUMN')
                AND UPPER(P.PROCEDURE_DEFINITION)
                    LIKE '%' || UPPER(CR.OLD_COLUMN_NAME) || '%'
            )
            OR CR.CHANGE_TYPE = 'ADD_COLUMN'
         )
    WHERE CR.REQUEST_ID = :P_REQUEST_ID
      AND P.PROCEDURE_SCHEMA IN ('SILVER', 'GOLD');

    -- 13. Analyze dbt model inventory
    INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    (
        REQUEST_ID,
        OBJECT_DATABASE,
        OBJECT_SCHEMA,
        OBJECT_NAME,
        OBJECT_TYPE,
        IMPACT_TYPE,
        IMPACT_EVIDENCE,
        RECOMMENDED_ACTION
    )
    SELECT
        CR.REQUEST_ID,
        COALESCE(DM.DATABASE_NAME, 'VENDOR_UAT'),
        COALESCE(DM.SCHEMA_NAME, 'DBT_PROJECT'),
        DM.MODEL_NAME,
        'DBT_MODEL',
        'POTENTIAL IMPACT',
        DM.SQL_TEXT,
        CASE
            WHEN CR.CHANGE_TYPE = 'RENAME_COLUMN' THEN
                'Review dbt model ' || DM.MODEL_NAME
                || ' for references to ' || CR.OLD_COLUMN_NAME
                || ' and update to ' || CR.NEW_COLUMN_NAME
            WHEN CR.CHANGE_TYPE = 'DROP_COLUMN' THEN
                'Review dbt model ' || DM.MODEL_NAME
                || ' for references to ' || CR.OLD_COLUMN_NAME
                || ' before dropping the column'
            WHEN CR.CHANGE_TYPE = 'ADD_COLUMN' THEN
                'Review whether dbt model ' || DM.MODEL_NAME
                || ' should incorporate column ' || CR.NEW_COLUMN_NAME
        END
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST CR
    JOIN VENDOR_UAT.SCHEMA_GOVERNANCE.DBT_MODEL_INVENTORY DM
      ON UPPER(DM.SQL_TEXT)
             LIKE '%' || UPPER(CR.TABLE_NAME) || '%'
     AND (
            (
                CR.CHANGE_TYPE IN ('RENAME_COLUMN', 'DROP_COLUMN')
                AND UPPER(DM.SQL_TEXT)
                    LIKE '%' || UPPER(CR.OLD_COLUMN_NAME) || '%'
            )
            OR CR.CHANGE_TYPE = 'ADD_COLUMN'
         )
    WHERE CR.REQUEST_ID = :P_REQUEST_ID;

    -- 14. Count all detected candidates
    SELECT COUNT(*)
      INTO :V_IMPACT_COUNT
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 15. Build impact summary for email
    SELECT LISTAGG(
        OBJECT_SCHEMA || '.' || OBJECT_NAME
        || ' (' || OBJECT_TYPE || ') - '
        || RECOMMENDED_ACTION,
        '\n'
    ) WITHIN GROUP (ORDER BY OBJECT_SCHEMA, OBJECT_NAME)
    INTO :V_IMPACT_SUMMARY
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 16. Build email
    SELECT
        'SQL Impact Analysis - Request ' || REQUEST_ID,
        'Change request: ' || REQUEST_ID
        || CHR(10) || 'Target: '
        || DATABASE_NAME || '.' || SCHEMA_NAME || '.' || TABLE_NAME
        || CHR(10) || 'Change type: ' || CHANGE_TYPE
        || CHR(10) || 'Old column: '
        || COALESCE(OLD_COLUMN_NAME, 'N/A')
        || CHR(10) || 'New column: '
        || COALESCE(NEW_COLUMN_NAME, 'N/A')
        || CHR(10) || 'Potentially impacted objects: '
        || :V_IMPACT_COUNT
        || CHR(10) || CHR(10)
        || COALESCE(
            :V_IMPACT_SUMMARY,
            'No matching impact candidates were found.'
        )
        || CHR(10) || CHR(10)
        || 'These are potential impacts based on metadata/text matching.'
        || CHR(10)
        || 'Review the findings before applying the schema change.'
    INTO :V_SUBJECT, :V_BODY
    FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 17. Mark analysis complete independently of email delivery
    UPDATE VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST
    SET STATUS = 'ANALYZED'
    WHERE REQUEST_ID = :P_REQUEST_ID;

    -- 18. Send email and log outcome
    BEGIN
        CALL SYSTEM$SEND_EMAIL(
            'IMPACT_EMAIL_INT',
            :V_EMAIL,
            :V_SUBJECT,
            :V_BODY
        );

        V_EMAIL_STATUS := 'SENT';

        INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.EMAIL_NOTIFICATION_LOG
        (
            REQUEST_ID,
            RECIPIENT_EMAIL,
            EMAIL_SUBJECT,
            STATUS,
            DETAILS
        )
        VALUES
        (
            :P_REQUEST_ID,
            :V_EMAIL,
            :V_SUBJECT,
            'SENT',
            'Impact report sent successfully.'
        );

    EXCEPTION
        WHEN OTHER THEN
            V_EMAIL_STATUS := 'FAILED';
            V_EMAIL_ERROR := SQLERRM;

            INSERT INTO VENDOR_UAT.SCHEMA_GOVERNANCE.EMAIL_NOTIFICATION_LOG
            (
                REQUEST_ID,
                RECIPIENT_EMAIL,
                EMAIL_SUBJECT,
                STATUS,
                DETAILS
            )
            VALUES
            (
                :P_REQUEST_ID,
                :V_EMAIL,
                :V_SUBJECT,
                'FAILED',
                :V_EMAIL_ERROR
            );
    END;

    RETURN 'Analysis completed. Request ID: '
        || P_REQUEST_ID
        || '; impacts: ' || V_IMPACT_COUNT
        || '; email: ' || V_EMAIL_STATUS;

END;
$$;




-- lets test email feature & log feature
CALL VENDOR_UAT.SCHEMA_GOVERNANCE.SP_ANALYZE_CHANGE_REQUEST(2);
-- got the output as expected : Analysis completed. Request ID: 1; impacts: 3; email: SENT
-- also got the email.

-- lets verify email log:
SELECT
    REQUEST_ID,
    RECIPIENT_EMAIL,
    EMAIL_SUBJECT,
    STATUS,
    DETAILS,
    SENT_AT
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.EMAIL_NOTIFICATION_LOG
WHERE REQUEST_ID = 1
ORDER BY SENT_AT DESC;

SELECT *
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
WHERE REQUEST_ID = 1;


--- adding new features

SELECT
    PROCEDURE_SCHEMA,
    PROCEDURE_NAME,
    PROCEDURE_LANGUAGE,
    PROCEDURE_DEFINITION
FROM VENDOR_UAT.INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA IN ('SILVER', 'GOLD')
ORDER BY PROCEDURE_SCHEMA, PROCEDURE_NAME;


SELECT
    PROCEDURE_SCHEMA AS IMPACTED_SCHEMA,
    PROCEDURE_NAME AS IMPACTED_OBJECT,
    'PROCEDURE' AS OBJECT_TYPE,
    'POTENTIAL IMPACT' AS IMPACT_TYPE,
    'Review references to VENDOR_ID before renaming it'
        AS RECOMMENDED_ACTION,
    PROCEDURE_DEFINITION AS IMPACT_EVIDENCE
FROM VENDOR_UAT.INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA IN ('SILVER', 'GOLD')
  AND UPPER(PROCEDURE_DEFINITION) LIKE '%VENDOR_MASTER%'
  AND UPPER(PROCEDURE_DEFINITION) LIKE '%VENDOR_ID%'
ORDER BY PROCEDURE_SCHEMA, PROCEDURE_NAME;


-- Before changing the main stored procedure, validating if we can get the details of store procs, currently impact analyzer is only for view, now we are adding store procs into it. before adding into main store proc, validating:

SELECT
    CR.REQUEST_ID,
    'VENDOR_UAT' AS OBJECT_DATABASE,
    P.PROCEDURE_SCHEMA AS OBJECT_SCHEMA,
    P.PROCEDURE_NAME AS OBJECT_NAME,
    'PROCEDURE' AS OBJECT_TYPE,
    'POTENTIAL IMPACT' AS IMPACT_TYPE,
    P.PROCEDURE_DEFINITION AS IMPACT_EVIDENCE,
    'Review references to '
        || CR.OLD_COLUMN_NAME
        || ' and update to '
        || CR.NEW_COLUMN_NAME
        || ' if required' AS RECOMMENDED_ACTION
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.CHANGE_REQUEST CR
JOIN VENDOR_UAT.INFORMATION_SCHEMA.PROCEDURES P
    ON UPPER(P.PROCEDURE_DEFINITION)
       LIKE '%' || UPPER(CR.TABLE_NAME) || '%'
   AND UPPER(P.PROCEDURE_DEFINITION)
       LIKE '%' || UPPER(CR.OLD_COLUMN_NAME) || '%'
WHERE CR.REQUEST_ID = 1
  AND CR.CHANGE_TYPE = 'RENAME_COLUMN'
  AND P.PROCEDURE_SCHEMA IN ('SILVER', 'GOLD');



SELECT
    REQUEST_ID,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    OBJECT_TYPE,
    IMPACT_TYPE,
    RECOMMENDED_ACTION
FROM VENDOR_UAT.SCHEMA_GOVERNANCE.IMPACT_DETAIL
WHERE REQUEST_ID = 1
ORDER BY OBJECT_TYPE, OBJECT_SCHEMA, OBJECT_NAME;

--- yes, as per impact object type, we can see now store procs & view both.

--- Lets add DBT Model for Impact Analysis as feature

DESC TABLE VENDOR_UAT.SCHEMA_GOVERNANCE.DBT_MODEL_INVENTORY;

SELECT * FROM VENDOR_UAT.SCHEMA_GOVERNANCE.DBT_MODEL_INVENTORY;
 
--- before stating DBT_MODEL impact, lets add composite unique key

ALTER TABLE VENDOR_UAT.SCHEMA_GOVERNANCE.DBT_MODEL_INVENTORY
ADD CONSTRAINT UQ_DBT_MODEL_PROJECT_FILE
UNIQUE (PROJECT_NAME, FILE_PATH, MODEL_NAME);

/* To insert the records DBT Model table, we need manual efforts. we are gonna use update statement and take the info from dbt  manifest.json file and update the table for all the existing models. 

UPDATE VENDOR_UAT.SCHEMA_GOVERNANCE.DBT_MODEL_INVENTORY
SET
    SQL_TEXT = '<paste the updated model SQL here>',
    LAST_SYNCED_AT = CURRENT_TIMESTAMP()
WHERE PROJECT_NAME = 'Airbnb_snfk_aws_dbt_project'
  AND FILE_PATH = 'models/gold/dim_vendor.sql'
  AND MODEL_NAME = 'dim_vendor';

After updating, in the project SOP, we will add one point, that any new addition/deletion/modification of dbt models, needs to be tracked in   DBT_MODEL_INVENTORY  manually, everytime. without keeping he history. 

*/


--- need to continue with end-to-end testing for adding/removing/renaming columns and with their impacts on tables, views, store procs & dbt models. get these impact list on email setup on email notification. 



select * from IMPACT_DETAIL;

select * from change_request;

---- take the screenshots of each steps output with query for GitHub.