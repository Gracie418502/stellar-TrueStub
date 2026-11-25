-- =============================================================================
-- Migration: 013_persist_refund_store.sql
-- Description: Replace the in-memory RefundStore with a Postgres-backed table
--              so refund idempotency records survive a restart or second
--              instance and cannot double-pay a refund (#512).
--
-- The existing `refunds` table (used by getRefundRetryCount /
-- incrementRefundRetryCount in HasuraService) only has `id` and `retry_count`.
-- This migration extends it with the full ClaimedRefund payload columns.
--
-- All statements are idempotent so the migration can be re-applied safely.
-- =============================================================================
-- Up Migration
-- ---------------------------------------------------------------------------
-- Create the full refunds table if it does not exist yet.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS refunds (
    -- Idempotency key — the application-level refundId.  The PRIMARY KEY
    -- constraint is the authoritative cross-instance duplicate guard: two
    -- concurrent INSERT … ON CONFLICT DO NOTHING requests for the same
    -- refund_id are serialized by the database; only one will return
    -- affected_rows = 1.
    refund_id        TEXT        PRIMARY KEY,
    escrow_id        TEXT        NOT NULL,
    claimed_at       TIMESTAMPTZ NOT NULL,
    amount           TEXT,
    currency         TEXT,
    claimed_by       TEXT,
    status           TEXT        NOT NULL DEFAULT 'claimed'
        CHECK (status IN ('claimed', 'pending', 'submitted', 'failed')),
    refund_to        TEXT,
    escrow_type      TEXT,
    milestone_index  TEXT,
    tx_hash          TEXT,
    failure_reason   TEXT,
    -- Retained for backward-compatibility with the existing retry-count path
    -- (HasuraService.getRefundRetryCount / incrementRefundRetryCount).
    retry_count      INT         NOT NULL DEFAULT 0
);

-- Index for the common escrow-scoped lookup.
CREATE INDEX IF NOT EXISTS idx_refunds_escrow_id
    ON refunds (escrow_id);

-- Index to support cleanup queries (cleanupBefore).
CREATE INDEX IF NOT EXISTS idx_refunds_claimed_at
    ON refunds (claimed_at);

-- Attach the row-change audit trigger if the function exists (created by
-- migration 012).  The DO block is a no-op when the function is absent so
-- this migration is safe to run in environments that skipped 012.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'attach_row_change_audit'
    ) THEN
        PERFORM attach_row_change_audit('refunds');
    END IF;
END;
$$;

-- Down Migration
DROP TABLE IF EXISTS refunds;
