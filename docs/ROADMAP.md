# Development roadmap

The work proceeds through vertical slices. Each phase ships working behavior, relevant automated tests and a documented verification result. A later feature must not weaken the separation between drafts and live output.

## Phase 0 — Technical definition

Deliverables:

- Inspect the repository and available tooling.
- Record architecture, persistence schema, operator workflow, performance budgets and risks in [ARCHITECTURE.md](ARCHITECTURE.md).
- Record measurable automated and physical test requirements in [QA.md](QA.md).
- Create native Windows/macOS Flutter runners and pin only dependencies needed for the next working slice.

Gate: architecture and Phase 1 scope are concrete before significant application implementation. Platform verification limitations are visible.

## Phase 1 — Persistent desktop foundation and controlled output

Goal: prepare and run a text service locally with a true separate desktop presentation window.

Required working behavior:

1. Native macOS and Windows application structure; a usable operator shell with content sections, a running order, slide selection, preview and live monitor.
2. Local SQLite persistence owned off the UI isolate, numbered schema migration, service/item ordering and settings.
3. Create/edit library content, search locally, add content to a service, reorder or navigate service items and select individual text slides.
4. Edit a draft while preserving the published text and style. Auto-save updates the library, not the live screen.
5. Open/close an independent output window and deliberately publish a selected slide. Next/previous follow the committed sequence, independently of unrelated operator selection.
6. Black, clear text, freeze, restore, background toggle, emergency black and full-screen output have explicit visible states.
7. Detect available displays and intentionally select output placement where the platform adapter supports it. Remember useful preferences without silently presenting on a fallback screen.
8. Useful inline error handling; a database/search/output error must not erase a valid live snapshot.

Definition of done:

- Automated persistence, FTS search, navigation and live/preview separation tests pass.
- Formatting and static analysis pass.
- Available-platform desktop build succeeds.
- A live native launch demonstrates two windows and a published slide.
- The independent-output correction scenario is exercised end to end.
- Platform-specific items that cannot be executed on the current host have concrete tests and are marked unverified.

Explicit boundary: Phase 1 is not a production release of the complete product. It does not imply faithful PDF/PPTX support, video, complete multilingual layout, network receivers, full theme authoring or renderer-process crash isolation.

## Phase 2 — Reliable display lifecycle and release engineering

Current status: core process isolation, authenticated staged output, native disarming/recovery, output profiles and development packaging are implemented and macOS software-tested. Physical multi-display and Windows/runtime/signing gates remain open. See [PHASE2_VERIFICATION.md](PHASE2_VERIFICATION.md).

The 0.3 closure review also rejects malformed native output destinations instead of treating them as rehearsal, and negotiates rendering compatibility before adopting a process. Remaining hardware/release work has a concrete [acceptance procedure](PHASE2_ACCEPTANCE.md). Continued feature development does not mark those external checks as passed.

- Harden native monitor selection, placement and full-screen behavior on Windows and macOS.
- Handle unplug/replug, resolution/DPI changes and output-window closure without moving output onto the operator desktop.
- Add protocol session/revision ordering, frame-ready acknowledgement, health monitoring and deterministic reconnect.
- Split the renderer into a supervised process if necessary for the required operator-crash isolation guarantee.
- Make saved output profiles, scaling, safe margins and rehearsal choices explicit.
- Establish reproducible signed development builds and CI on both operating systems.

Gate: physical HDMI/multi-display matrix passes on both platforms. Killing nonessential workers leaves the output unchanged. If process isolation is implemented, terminating the operator leaves the last renderer frame visible. Emergency black beats queued navigation.

## Phase 3 — Measured text layout and church content structure

Core software is implemented in version 0.3; version 0.3.3 passes 255 automated tests. See [PHASE3_PLAN.md](PHASE3_PLAN.md), [PHASE3_VERIFICATION.md](PHASE3_VERIFICATION.md) and the current [Phase 2/3 status](PHASE23_STATUS.md). Native multilingual reader review and outstanding Windows/physical checks remain required; trusted external signing is a separate production-distribution requirement. These are not implied by the software results.

- Retain source text and introduce versioned sections for verse, chorus, refrain, bridge, speaker and paragraphs.
- Offline recognition suggests structure with confidence; ambiguous transformations require confirmation.
- Use actual font measurements to split at sensible boundaries without indefinite shrinking.
- Add overflow detection, safe-area guides, alignment and spacing controls, manual split/merge and durable layout overrides.
- Add undo/redo, revision history and recoverable in-progress drafts.
- Test complex scripts and font fallback with representative material.

Gate: long prayer/reading/hymn fixtures fit the safe area, conserve all original text and preserve intentional section order. Draft relayout never modifies live output. Unsupported unbreakable content has a visible actionable error.

## Phase 4 — Complete local library and service planning

**Not started.** The user requires Phase 2 and Phase 3 acceptance first. [PHASE23_STATUS.md](PHASE23_STATUS.md) records the pending Windows/physical checks and current local evidence. Trusted external distribution is a separate release requirement; a Developer ID purchase is not necessary for local development.

- Add author/language/tags, favorites, recent/frequent views, collections/folders and bulk editing.
- Add duplicate suggestions based on normalized text and title, requiring review before consolidation.
- Add bounded typo-tolerant ranking and clear phrase/prefix semantics.
- Add reusable service templates, duplication, multiple saved services and drag reordering.
- Preserve the prepared running order while presenting an unplanned item, with an explicit return action.
- Track usage and suggestions locally; allow disabling/clearing history.

Gate: 10,000-record benchmark meets agreed search budget; bulk edits are transactional; deleting/removing records cannot silently damage service plans; suggestions never publish.

## Phase 5 — Presentation themes and workspace customization

- Add reusable, versioned theme definitions with fonts/weights, color/gradient, shadows/outlines, margins, spacing and alignment.
- Add theme presets appropriate to different service contexts without assuming a denomination.
- Preview changes before applying to one slide, selected slides or a whole service.
- Add content-type default rules with clear override precedence.
- Add imported/system font handling and font portability reports.
- Add adjustable panels, saved workspace layouts, compact/full-focus modes and configurable shortcuts.

Gate: golden/render tests cover representative themes; font/theme changes trigger draft measurement, never live mutation. Preview and output render the same canonical canvas.

## Phase 6 — Managed assets and media playback

- Copy imported images/logos/backgrounds to managed storage with hashes and metadata.
- Generate thumbnails in workers; add crop, opacity, dimming, replacement and offline caching.
- Add tested playback backends for named video/audio formats and predictable stop/pause behavior.
- Add safe preloading, decode byte budgets, disposal and failed-media fallback.
- Add optional licensed external image search with attribution and download metadata.

Gate: known offline media remain usable with network disabled; switching or failing media retains the last good frame; memory stays bounded during a long service.

## Phase 7 — Interoperability and packages

- Implement versioned structured library/service packages with media manifests and conflict review.
- Add TXT and OpenLyrics import/export with source retention and repeat-structure fixtures.
- Add PDF page rendering and separately labeled optional text extraction.
- Add PDF and slide-image export.
- Evaluate PPTX faithful conversion and editable extraction as separate capabilities. State local converter dependencies and unsupported features.
- Run import work in cancellable workers with progress and per-file diagnostics.

Gate: round-trip corpus preserves supported fields; malformed/huge archives cannot escape extraction directories; partial imports are reviewed before commit. PPTX capability claims match tested reference decks.

## Phase 8 — Backup, recovery and operational hardening

- Add automatic rotating local backups and manual backup/restore with integrity and manifest verification.
- Add pre-migration backup gates, database diagnostics and recovery without overwriting the original library.
- Restore interrupted drafts and service state while output begins black.
- Run fault injection for disk full, permissions, busy database, damaged package, renderer disconnect and unexpected app termination.
- Run the performance and eight-hour soak matrix on representative hardware.
- Add accessibly labeled controls, focus order and high-contrast state review with volunteers.

Gate: verified restores recover full records/assets; failed migrations preserve original data; all committed edits survive restart; no live disruption from an optional subsystem failure.

## Phase 9 — Optional intelligence and network receivers

- Enhance offline parsing/ranking using local usage patterns and explicit suggestions.
- Add opt-in AI recognition through a replaceable adapter with clear data/availability handling.
- Add local-network receiver transport with pairing, capabilities and independent connectivity state.
- Maintain local HDMI publishing independently of receiver health or network latency.

Gate: disabling network/AI leaves all essential presentation features working. No suggestion or receiver message can authorize a live replacement. HDMI never waits for remote delivery.

## Production release gate

Before describing the application as production quality for live services, require all of the following:

- Windows and macOS signed release packages install on clean supported systems.
- Physical display matrix, unplug/replug, rapid switching and extended-service soak pass.
- Complete backup/restore and migration exercises pass with real managed media.
- Content import compatibility is published as a tested format/feature matrix.
- Performance results include hardware, OS, build mode, dataset and measurement method.
- A volunteer can prepare, run, correct and recover a service using the documented workflow.
- Open defects are triaged by severity; no unresolved defect can unexpectedly replace output or lose user content.

## Evidence policy

For each completed phase, record the build/version, commands run, test results, platform, physical scenarios exercised and remaining limitations. “Implemented” means the main behavior exists. “Automated verified” means a relevant test passed. “Hardware verified” means the scenario ran on the actual platform/display setup. These are different claims and should remain separate.
