-- =============================================================================
-- Migration: 013_create_refund_claims.sql
-- Description: Replace the in-memory refund idempotency store with a
--              Postgres-backed table so refund claims survive restarts and
--              are shared across every backend instance. (#512)
--
-- The PRIMARY KEY on refund_id is the authoritative duplicate guard: two
-- concurrent requests with the same refundId cannot both INSERT successfully,
-- so only one proceeds to the on-chain executor.
--
-- All statements are idempotent so the migration can be re-applied safely.
-- =============================================================================

-- Up Migration

CREATE TABLE IF NOT EXISTS refund_claims (
    refund_id       TEXT        PRIMARY KEY,
    escrow_id       TEXT        NOT NULL,
    claimed_at      TIMESTAMPTZ NOT NULL,
    amount          TEXT,
    currency        TEXT,
    claimed_by      TEXT,
    status          TEXT        NOT NULL DEFAULT 'claimed'
        CHECK (status IN ('claimed', 'pending', 'submitted', 'failed')),
    refund_to       TEXT,
    escrow_type     TEXT,
    milestone_index TEXT,
    tx_hash         TEXT,
    failure_reason  TEXT
);

CREATE INDEX IF NOT EXISTS idx_refund_claims_escrow_id
    ON refund_claims (escrow_id);
CREATE INDEX IF NOT EXISTS idx_refund_claims_claimed_at
    ON refund_claims (claimed_at);

-- Attach the row-change audit trigger defined in 012_row_change_audit.sql so
-- direct manual edits to refund_claims are captured in the audit log.
SELECT attach_row_change_audit('refund_claims');

-- Down Migration

SELECT detach_row_change_audit('refund_claims');
DROP TABLE IF EXISTS refund_claims;
