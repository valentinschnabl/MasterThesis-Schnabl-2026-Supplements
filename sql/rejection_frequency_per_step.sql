/*
Script: rejection_frequency_per_step.sql
Purpose:
- Quantifies rejection frequencies across workflow validation steps.
- Makes rework loops visible ("Hidden Factory") by mapping each rejection event
  to Step 1 (RIS), Step 2 (Library), or Step 3 (Faculty) within the current submission cycle.
- Uses explicit user identification to correctly categorize Library rejections.

Data Scope:
- ReposiTUm/DSpace provenance metadata (metadata_field_id = 30).
- Target submissions from years 2023-2025.
- Archived items only (in_archive = 1).
*/

WITH TargetItems AS (
    -- Step 1: Select submitted items in the target timeframe
    SELECT DISTINCT mv.resource_id
    FROM metadatavalue mv
    JOIN item i ON i.item_id = mv.resource_id
    WHERE mv.metadata_field_id = 30
      AND mv.resource_type_id = 2
      AND (mv.text_value LIKE 'Submitted by % on 2023-%'
        OR mv.text_value LIKE 'Submitted by % on 2024-%'
        OR mv.text_value LIKE 'Submitted by % on 2025-%')
      AND mv.text_value NOT LIKE 'Submitted by %(katharina.kaiser@tuwien.ac.at)%'
      AND i.in_archive = 1
),
RawEvents AS (
    -- Collect provenance events for target items
    SELECT 
        m.resource_id, 
        m.metadata_value_id, 
        TO_CHAR(m.text_value) as txt,
        -- Flag whether the actor belongs to library staff
        CASE
            WHEN (LOWER(TO_CHAR(m.text_value)) LIKE '%magdalena.andrae%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%katharina.heinz%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%silvia.ziemkendorf%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%david.krassnig%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%matthias.heni%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%christoph.hornung%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%tanja.north%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%michaela.achleitner%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%sarah.krassnig%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%horst.leonhardsberger%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%ingrid.haas%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%katarina.hriber%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%christian.kaier%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%andreas.pacher%'
                 OR LOWER(TO_CHAR(m.text_value)) LIKE '%agnieszka.betzwar%')
            THEN 1 ELSE 0
        END as is_bib_user
    FROM metadatavalue m
    INNER JOIN item i ON m.resource_id = i.item_id
    INNER JOIN TargetItems t ON m.resource_id = t.resource_id
    WHERE m.metadata_field_id = 30
      AND i.owning_collection IS NOT NULL
      AND i.owning_collection != 4
      AND i.in_archive = 1
),
RejectionAnchors AS (
    -- Identify rejection events and their preceding cycle reset point
    SELECT
        r.resource_id,
        r.metadata_value_id AS current_rej_id,
        r.is_bib_user,
        (SELECT MAX(s.metadata_value_id)
         FROM RawEvents s
         WHERE s.resource_id = r.resource_id
           AND s.metadata_value_id < r.metadata_value_id
           AND (LOWER(s.txt) LIKE 'submitted by%'
             OR LOWER(s.txt) LIKE 'rejected by%')) AS last_reset_id
    FROM RawEvents r
    WHERE LOWER(r.txt) LIKE 'rejected by%'
),
StepCounter AS (
    -- Count approvals in the current cycle for non-library rejections
    SELECT
        ra.resource_id,
        ra.current_rej_id,
        ra.is_bib_user,
        (SELECT COUNT(*)
         FROM RawEvents a
         WHERE a.resource_id = ra.resource_id
           AND LOWER(a.txt) LIKE 'approved for entry into archive by%'
           AND a.metadata_value_id > NVL(ra.last_reset_id, 0)
           AND a.metadata_value_id < ra.current_rej_id) AS approvals_in_current_cycle
    FROM RejectionAnchors ra
),
Categorized AS (
    -- Map each rejection to a workflow step label
    SELECT DISTINCT
        resource_id,
        current_rej_id,
        CASE 
            -- Library actor indicates a Step 2 rejection
            WHEN is_bib_user = 1 THEN 'Step 2 Rejection (Library)'
            -- No prior approvals indicates Step 1 rejection
            WHEN is_bib_user = 0 AND approvals_in_current_cycle = 0 THEN 'Step 1 Rejection (RIS)'
            -- One or more approvals indicates Step 3 rejection
            WHEN is_bib_user = 0 AND approvals_in_current_cycle >= 1 THEN 'Step 3 Rejection (Faculty)'
            ELSE 'Unknown Rejection'
        END AS rejection_step
    FROM StepCounter
),
TotalSubmissions AS (
    -- Baseline count of unique submitted items
    SELECT COUNT(DISTINCT resource_id) AS total_items
    FROM RawEvents
    WHERE LOWER(txt) LIKE 'submitted by%'
)
-- Final percentage-based rejection report
SELECT
    c.rejection_step,
    COUNT(c.current_rej_id) AS total_rejection_events,
    COUNT(DISTINCT c.resource_id) AS distinct_items_rejected,
    ts.total_items AS total_items_submitted,
    ROUND((COUNT(DISTINCT c.resource_id) / NULLIF(ts.total_items, 0)) * 100, 2) AS percentage_of_total
FROM Categorized c
CROSS JOIN TotalSubmissions ts
GROUP BY c.rejection_step, ts.total_items
ORDER BY c.rejection_step;