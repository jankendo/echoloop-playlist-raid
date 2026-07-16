# ADR-0001: Keep Phase 0–2 offline and deterministic

## Status

Accepted — 2026-07-16

## Decision

The first public slice uses a generated WAV and a fixed chart. Network acquisition,
audio analysis, and stem separation are represented by schemas and a worker boundary,
but are not runtime dependencies.

## Rationale

This preserves the specification's local-first and testability requirements, lets the
game be verified in headless CI, and avoids bundling copyrighted recordings or requiring
network services before the core ECHOLOOP experience is stable.

