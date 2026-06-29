/*
 * 00_load_vocabulary.sql
 * Purpose : Load all OMOP vocabulary files into DuckDB.
 * Instructions:
 * 1. Download vocabulary files from https://athena.ohdsi.org
 * 2. Place all files in a single folder (see vocab_path below)
 * 3. Update vocab_path to point to that folder
 * 4. Run this script
 */
-- -------------------------------------------------------------------------
-- STEP 0: ENVIRONMENT CONFIGURATION

-- CHANGE THESE PATHS to your local directory before running
SET file_search_path = '/path/to/your/vocabulary/';
SET VARIABLE vocab_path = '/path/to/your/vocabulary/';

-- Wrap everything in a transaction to prevent partial/corrupted states if a file load fails
BEGIN TRANSACTION;

-- -------------------------------------------------------------------------
-- 1. vocabulary
-- -------------------------------------------------------------------------
DELETE FROM vocabulary;
INSERT INTO vocabulary BY NAME
SELECT *
FROM read_csv(
    getvariable('vocab_path') || 'VOCABULARY.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true
);

-- -------------------------------------------------------------------------
-- 2. domain
-- -------------------------------------------------------------------------
DELETE FROM domain;
INSERT INTO domain BY NAME
SELECT *
FROM read_csv(
    getvariable('vocab_path') || 'DOMAIN.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true
);

-- -------------------------------------------------------------------------
-- 3. concept_class
-- -------------------------------------------------------------------------
DELETE FROM concept_class;
INSERT INTO concept_class BY NAME
SELECT *
FROM read_csv(
    getvariable('vocab_path') || 'CONCEPT_CLASS.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true
);

-- -------------------------------------------------------------------------
-- 4. relationship
-- -------------------------------------------------------------------------
DELETE FROM relationship;
INSERT INTO relationship BY NAME
SELECT *
FROM read_csv(
    getvariable('vocab_path') || 'RELATIONSHIP.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true
);

-- -------------------------------------------------------------------------
-- 5. concept (Dates cleanly parsed from YYYYMMDD format)
-- -------------------------------------------------------------------------
DELETE FROM concept;
INSERT INTO concept BY NAME
SELECT *
FROM read_csv(
    getvariable('vocab_path') || 'CONCEPT.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true,
    dateformat = '%Y%m%d',
    types = {
        'concept_id': 'BIGINT',
        'valid_start_date': 'DATE',
        'valid_end_date': 'DATE'
    }
);

-- -------------------------------------------------------------------------
-- 6. concept_relationship
-- -------------------------------------------------------------------------
DELETE FROM concept_relationship;
INSERT INTO concept_relationship BY NAME
SELECT *
FROM read_csv(
    getvariable('vocab_path') || 'CONCEPT_RELATIONSHIP.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true,
    dateformat = '%Y%m%d',
    types = {
        'concept_id_1': 'BIGINT',
        'concept_id_2': 'BIGINT',
        'valid_start_date': 'DATE',
        'valid_end_date': 'DATE'
    }
);

-- -------------------------------------------------------------------------
-- 7. concept_ancestor
-- -------------------------------------------------------------------------
DELETE FROM concept_ancestor;
INSERT INTO concept_ancestor BY NAME
SELECT *
FROM read_csv(
    getvariable('vocab_path') || 'CONCEPT_ANCESTOR.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true,
    types = {
        'ancestor_concept_id': 'BIGINT',
        'descendant_concept_id': 'BIGINT',
        'min_levels_of_separation': 'INTEGER',
        'max_levels_of_separation': 'INTEGER'
    }
);

-- -------------------------------------------------------------------------
-- 8. concept_synonym
-- -------------------------------------------------------------------------
DELETE FROM concept_synonym;
INSERT INTO concept_synonym BY NAME
SELECT
    try_cast(concept_id AS BIGINT) AS concept_id,
    concept_synonym_name,
    try_cast(language_concept_id AS BIGINT) AS language_concept_id
FROM read_csv(
    getvariable('vocab_path') || 'CONCEPT_SYNONYM.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true,
    all_varchar = true,
    ignore_errors = true
);
-- -------------------------------------------------------------------------
-- 9. drug_strength
-- -------------------------------------------------------------------------
DELETE FROM drug_strength;
INSERT INTO drug_strength BY NAME
SELECT *
FROM read_csv(
    getvariable('vocab_path') || 'DRUG_STRENGTH.csv',
    header = true,
    delim = '\t',
    quote = '',
    null_padding = true,
    dateformat = '%Y%m%d',
    types = {
        'drug_concept_id': 'BIGINT',
        'ingredient_concept_id': 'BIGINT',
        'valid_start_date': 'DATE',
        'valid_end_date': 'DATE'
    }
);


COMMIT;

-- -------------------------------------------------------------------------
-- POST-LOAD VALIDATION
-- -------------------------------------------------------------------------
SELECT 'vocabulary' AS tbl, COUNT(*) FROM vocabulary
UNION ALL SELECT 'domain', COUNT(*) FROM domain
UNION ALL SELECT 'concept_class', COUNT(*) FROM concept_class
UNION ALL SELECT 'relationship', COUNT(*) FROM relationship
UNION ALL SELECT 'concept', COUNT(*) FROM concept
UNION ALL SELECT 'concept_relationship', COUNT(*) FROM concept_relationship
UNION ALL SELECT 'concept_ancestor', COUNT(*) FROM concept_ancestor
UNION ALL SELECT 'concept_synonym', COUNT(*) FROM concept_synonym
UNION ALL SELECT 'drug_strength', COUNT(*) FROM drug_strength;
