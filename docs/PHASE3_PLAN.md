# Phase 3 — Measured layout and reviewed content structure

Implementation baseline: 5 November 2026. Phase 2's software foundation is implemented; its Windows and physical display acceptance remain mandatory release gates. The user has authorized continued implementation while those checks are recorded honestly.

## Architecture and invariants

Keep the existing native operator/renderer process boundary and immutable staged output. Phase 3 changes the draft pipeline only: original source → optional reviewed structure → font-measured slides → explicit publication. The renderer receives a complete text/theme snapshot and never accesses the draft journal or recognizer. Recognition, manual layout changes, recovery and version restoration have no publication authority.

`ContentStructure` is versioned and bound to an exact original source string. Sections reference UTF-16 offsets and retain the exact corresponding source substrings, with types for verse, chorus, refrain, bridge, speaker, paragraph and custom. Labels are metadata. Manual split offsets and merged section boundaries are stored separately from original text. A source edit invalidates outdated structure instead of guessing offset adjustments. Recognition returns a suggested structure, detected content type, confidence and reasons; applying it always requires an operator action. Section labels/types can be overridden before applying.

The shared layout/canvas code measures actual shaped fonts on a canonical 1920 × 1080 canvas. It adds line height, paragraph spacing, vertical alignment and automatic/explicit text direction. Safe-area guides remain operator-only. Pagination prefers paragraph, line, sentence and legal word boundaries and respects grapheme clusters. It never reduces the selected font to conceal overflow. Unsupported content that cannot fit has an actionable error; publication remains blocked while the last accepted output remains intact.

## Persistence and migration

Migrate SQLite schema 1 to schema 2 in a transaction, preserving existing content, FTS, services, settings and revisions. Add nullable `content.structure_json` for supported structured metadata and a per-content draft journal containing a complete immutable snapshot and timestamp. Existing content and historical snapshots without structure remain readable. Future schema versions are rejected without resetting files.

Journal writes run on the database isolate, before the longer normal autosave delay. A committed save records a version and clears only the matching draft snapshot, so an older save cannot discard a newer journal entry. Startup exposes newer journal snapshots as recoverable editable drafts, independently of any surviving live renderer. Version restoration creates a new draft and a subsequent revision; it never deletes history. Undo/redo holds a bounded per-item edit history including structural changes.

## Operator workflow

Keep the service workspace and live controls accessible. A source-editor tools button opens Structure, Layout and History views:

1. Review detected type, confidence, section labels and exact source text; adjust labels/types and explicitly apply or retain the original layout.
2. Split at an editor/source cursor or merge adjacent section boundaries without changing source text. Automatic repagination still enforces fit after merges.
3. Adjust alignment, line/paragraph spacing and direction while inspecting a safe-area preview. Existing theme controls retain font size and margins.
4. Inspect saved revisions and explicitly restore one into preview. Undo/redo and journal recovery remain separate from Go Live.

## Milestones and evidence

| Milestone | Required checks |
| --- | --- |
| Phase 2 closure review | Audit native display guards; fix executable software defects; preserve pending Windows/physical/signing evidence in a concrete acceptance runbook. |
| Structure and measured layout | Source conservation, serialization, recognition confidence, manual overrides, grapheme-safe pagination, RTL/complex-script fixtures, meaningful overflow and shared rendering checks. |
| Persistence and draft lifecycle | Existing-schema migration, reopen/backup integrity, journal recovery, save races, revision restore and undo/redo without live mutation. |
| Volunteer workflow | Working structure/layout/history controls, compact desktop constraints, source-controller synchronization, keyboard actions and explicit publish separation. |
| Available native build | Format, static analysis, full automated suite, macOS release native process smoke and normal development package. Record exact failures/limits rather than assuming Windows or HDMI behavior. |

## Performance and risks

Retain bounded content input and transport sizes, bounded undo history, serialized database work and a separate renderer process. Font measurement still uses Flutter text APIs on the operator isolate; cache/batch work where practical and measure representative long passages. It cannot stall the separate renderer. Journal durability begins after an acknowledged journal write; power failure or termination before that point can lose the latest keystrokes. Native font fallback and typographic correctness need real multilingual-reader review on both platforms. Ambiguous speaker/verse rules must remain reviewable and never alter the original text silently.

The software tests cannot certify physical HDMI, mixed DPI, Windows runtime, television overscan, visual scanout latency, trusted signatures or an eight-hour service. Those remain explicitly recorded acceptance gates, alongside Phase 3's tested functionality and known limits.

## Implementation result

Version 0.3 implements this software scope with 210 passing tests, clean formatting/analysis, a passing macOS release process/recovery harness and a verified normal application development package. Long drafts and service publication now yield between bounded page measurements rather than synchronously compiling entire passages. The native closure review also fixed malformed display destinations and covered-window paint acknowledgements. Exact results and remaining limits are in [PHASE3_VERIFICATION.md](PHASE3_VERIFICATION.md); Windows/physical/trusted-distribution acceptance remains open.
