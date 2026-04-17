/*
Script: waiting_times.sql
Purpose:
- Creates the view v_dspace_workflow_bottlenecks for queue-time analysis.
- Reconstructs workflow transitions from provenance text and computes waiting
    time in business hours between consecutive process events.

Data Scope:
- ReposiTUm/DSpace provenance metadata (metadata_field_id = 30).
- Target submissions from years 2023-2025.
- Archived items only, excluding selected non-target collections.

Method Summary:
1) Identify target items in the analysis window.
2) Parse ISO-8601 event timestamps from provenance text.
3) Classify events (Submitted, Approved, Rejected) and mark library approvals.
4) Build submission cycles to correctly handle resubmissions.
5) Sequence events, compute time deltas, subtract weekend hours.
6) Map transitions to workflow stages:
     - 1. RIS Check
     - 2. Library Check
     - 3. Faculty Check
     - Resubmission

Output (view columns):
- resource_id
- start_time
- end_time
- workflow_stage
- wait_time_hours
*/

CREATE OR REPLACE VIEW v_dspace_workflow_bottlenecks AS
WITH TargetItems AS (
    -- Step 1: Select submitted items in target years
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
    -- Step 2: Parse timestamps and classify actor group
    SELECT
        m.resource_id,
        TO_TIMESTAMP(
            REGEXP_SUBSTR(TO_CHAR(m.text_value), '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'),
            'YYYY-MM-DD"T"HH24:MI:SS"Z"'
        ) AS event_time,
        CASE
            WHEN LOWER(TO_CHAR(m.text_value)) LIKE 'submitted by%' THEN 'Submitted'
            WHEN LOWER(TO_CHAR(m.text_value)) LIKE 'approved for entry into archive by%' THEN 'Approved'
            WHEN LOWER(TO_CHAR(m.text_value)) LIKE 'rejected by%' THEN 'Rejected'
            ELSE 'Other'
        END AS event_type,
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
      AND i.owning_collection NOT IN (4, 7)
),
SubmissionCycles AS (
    -- Step 3: Build submission cycles
    SELECT
        r.*,
        SUM(CASE WHEN r.event_type = 'Submitted' THEN 1 ELSE 0 END) 
            OVER (PARTITION BY r.resource_id ORDER BY r.event_time) AS cycle_id
    FROM RawEvents r
    WHERE event_type != 'Other' AND event_time IS NOT NULL
),
OrderedEvents AS (
    -- Step 4: Pair each event with its next event
    SELECT
        resource_id, event_time, event_type, cycle_id, is_bib_user,
        CASE WHEN event_type = 'Approved' THEN 
            ROW_NUMBER() OVER (PARTITION BY resource_id, cycle_id, event_type ORDER BY event_time)
        ELSE 0 END as approval_step_num,
        LEAD(event_time) OVER (PARTITION BY resource_id ORDER BY event_time) AS next_event_time,
        LEAD(event_type) OVER (PARTITION BY resource_id ORDER BY event_time) AS next_event_type,
        LEAD(is_bib_user) OVER (PARTITION BY resource_id ORDER BY event_time) AS next_is_bib_user
    FROM SubmissionCycles
),
QueueTimes AS (
    -- Step 5: Compute business-hour waiting times
    SELECT
        resource_id, event_time AS start_time, next_event_time AS end_time,
        event_type AS start_stage, next_event_type AS end_stage,
        approval_step_num, is_bib_user, next_is_bib_user,
        GREATEST(0, ((CAST(next_event_time AS DATE) - CAST(event_time AS DATE)) * 24) -
        (((TRUNC(CAST(next_event_time AS DATE), 'IW') - TRUNC(CAST(event_time AS DATE), 'IW')) / 7) * 48)) AS biz_hours
    FROM OrderedEvents
    WHERE next_event_time IS NOT NULL
)
SELECT
    resource_id, start_time, end_time,
    CASE
        -- 1. RIS Check: submission to first non-library action
        WHEN start_stage = 'Submitted' AND next_is_bib_user = 0 THEN '1. RIS Check'
        
        -- 2. Library Check: first approval followed by library action
        WHEN start_stage = 'Approved' AND approval_step_num = 1 AND next_is_bib_user = 1 THEN '2. Library Check'
        
        -- 3. Faculty Check: first non-library approval path or second approval
        WHEN start_stage = 'Approved' AND approval_step_num = 1 AND next_is_bib_user = 0 THEN '3. Faculty Check'
        WHEN start_stage = 'Approved' AND approval_step_num = 2 THEN '3. Faculty Check'
        
        -- Resubmission: user correction time after rejection
        WHEN start_stage = 'Rejected' AND end_stage = 'Submitted' THEN 'Resubmission'
        
        ELSE 'Other'
    END AS workflow_stage,
    ROUND(biz_hours, 2) AS wait_time_hours
FROM QueueTimes
WHERE 
    -- Remove bypass cases where library acts immediately after submission
    NOT (start_stage = 'Submitted' AND next_is_bib_user = 1)
    AND 
    -- Keep only mapped workflow stages
    CASE
        WHEN start_stage = 'Submitted' AND next_is_bib_user = 0 THEN '1. RIS Check'
        WHEN start_stage = 'Approved' AND approval_step_num = 1 AND next_is_bib_user = 1 THEN '2. Library Check'
        WHEN start_stage = 'Approved' AND approval_step_num = 1 AND next_is_bib_user = 0 THEN '3. Faculty Check'
        WHEN start_stage = 'Approved' AND approval_step_num = 2 THEN '3. Faculty Check'
        WHEN start_stage = 'Rejected' AND end_stage = 'Submitted' THEN 'Resubmission'
        ELSE 'Other'
    END != 'Other';