/*
 * 00_create_vocabulary_tables.sql
 * Purpose : Create the empty OMOP vocabulary tables that 00_load_vocabulary.sql
 *           populates. Run this ONCE against a new DuckDB database, before
 *           00_load_vocabulary.sql.
 *
 * If your database was built from an existing OMOP CDM instance, these tables
 * already exist and you can skip this script entirely.
 *
 * Table definitions follow the OMOP CDM v5.4 vocabulary specification:
 * https://ohdsi.github.io/CommonDataModel/cdm54.html
 *
 * -------------------------------------------------------------------------
 * PREPARING THE ATHENA FILES
 * -------------------------------------------------------------------------
 * ATHENA (https://athena.ohdsi.org) delivers the vocabulary as a single .zip.
 * DuckDB cannot read inside a .zip, so extract it first into one flat folder:
 *
 *   PowerShell:  Expand-Archive -Path vocabulary_download.zip -DestinationPath vocabulary\
 *   bash:        unzip vocabulary_download.zip -d vocabulary/
 *
 * The extracted folder contains one tab-delimited .csv per table, with
 * uppercase filenames (CONCEPT.csv, CONCEPT_ANCESTOR.csv, ...). That folder
 * path is what goes into vocab_path in 00_load_vocabulary.sql.
 *
 * Note: CONCEPT_CPT4.csv / the cpt4.jar step is only required if you need CPT4
 * concepts. This pipeline does not use them, so it can be skipped.
 * -------------------------------------------------------------------------
 *
 * Type choices:
 *   - Concept identifiers are BIGINT to match the explicit casts in
 *     00_load_vocabulary.sql (the OMOP spec says INTEGER; BIGINT is a
 *     superset and avoids any narrowing on load).
 *   - valid_start_date / valid_end_date are DATE. 00_load_vocabulary.sql
 *     parses the ATHENA YYYYMMDD format via dateformat = '%Y%m%d'.
 *   - No PRIMARY KEY constraints are declared. They are not needed by any
 *     query in this pipeline, and omitting them keeps the bulk load of
 *     CONCEPT / CONCEPT_ANCESTOR (millions of rows) fast.
 */

BEGIN TRANSACTION;

-- -------------------------------------------------------------------------
-- 1. vocabulary
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vocabulary (
    vocabulary_id           VARCHAR NOT NULL,
    vocabulary_name         VARCHAR NOT NULL,
    vocabulary_reference    VARCHAR,
    vocabulary_version      VARCHAR,
    vocabulary_concept_id   BIGINT  NOT NULL
);

-- -------------------------------------------------------------------------
-- 2. domain
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS domain (
    domain_id           VARCHAR NOT NULL,
    domain_name         VARCHAR NOT NULL,
    domain_concept_id   BIGINT  NOT NULL
);

-- -------------------------------------------------------------------------
-- 3. concept_class
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS concept_class (
    concept_class_id            VARCHAR NOT NULL,
    concept_class_name          VARCHAR NOT NULL,
    concept_class_concept_id    BIGINT  NOT NULL
);

-- -------------------------------------------------------------------------
-- 4. relationship
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS relationship (
    relationship_id           VARCHAR NOT NULL,
    relationship_name         VARCHAR NOT NULL,
    is_hierarchical           VARCHAR NOT NULL,
    defines_ancestry          VARCHAR NOT NULL,
    reverse_relationship_id   VARCHAR NOT NULL,
    relationship_concept_id   BIGINT  NOT NULL
);

-- -------------------------------------------------------------------------
-- 5. concept
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS concept (
    concept_id          BIGINT  NOT NULL,
    concept_name        VARCHAR NOT NULL,
    domain_id           VARCHAR NOT NULL,
    vocabulary_id       VARCHAR NOT NULL,
    concept_class_id    VARCHAR NOT NULL,
    standard_concept    VARCHAR,
    concept_code        VARCHAR NOT NULL,
    valid_start_date    DATE    NOT NULL,
    valid_end_date      DATE    NOT NULL,
    invalid_reason      VARCHAR
);

-- -------------------------------------------------------------------------
-- 6. concept_relationship
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS concept_relationship (
    concept_id_1        BIGINT  NOT NULL,
    concept_id_2        BIGINT  NOT NULL,
    relationship_id     VARCHAR NOT NULL,
    valid_start_date    DATE    NOT NULL,
    valid_end_date      DATE    NOT NULL,
    invalid_reason      VARCHAR
);

-- -------------------------------------------------------------------------
-- 7. concept_ancestor
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS concept_ancestor (
    ancestor_concept_id         BIGINT  NOT NULL,
    descendant_concept_id       BIGINT  NOT NULL,
    min_levels_of_separation    INTEGER NOT NULL,
    max_levels_of_separation    INTEGER NOT NULL
);

-- -------------------------------------------------------------------------
-- 8. concept_synonym
--
-- Columns are nullable by design: 00_load_vocabulary.sql loads this table
-- with try_cast + ignore_errors to tolerate the embedded delimiters and
-- quote characters that appear in some synonym names. A NOT NULL constraint
-- here would abort the whole load transaction on a single malformed row.
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS concept_synonym (
    concept_id              BIGINT,
    concept_synonym_name    VARCHAR,
    language_concept_id     BIGINT
);

-- -------------------------------------------------------------------------
-- 9. drug_strength
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS drug_strength (
    drug_concept_id                 BIGINT  NOT NULL,
    ingredient_concept_id           BIGINT  NOT NULL,
    amount_value                    DOUBLE,
    amount_unit_concept_id          BIGINT,
    numerator_value                 DOUBLE,
    numerator_unit_concept_id       BIGINT,
    denominator_value               DOUBLE,
    denominator_unit_concept_id     BIGINT,
    box_size                        INTEGER,
    valid_start_date                DATE    NOT NULL,
    valid_end_date                  DATE    NOT NULL,
    invalid_reason                  VARCHAR
);

COMMIT;

-- -------------------------------------------------------------------------
-- POST-CREATE VALIDATION
-- All nine tables should be listed, each with 0 rows.
-- Run 00_load_vocabulary.sql next to populate them.
-- -------------------------------------------------------------------------
SELECT table_name, estimated_size AS row_count
FROM duckdb_tables()
WHERE table_name IN (
    'vocabulary', 'domain', 'concept_class', 'relationship', 'concept',
    'concept_relationship', 'concept_ancestor', 'concept_synonym', 'drug_strength'
)
ORDER BY table_name;
