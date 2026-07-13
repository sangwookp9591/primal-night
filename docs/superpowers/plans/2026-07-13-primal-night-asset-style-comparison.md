# PRIMAL NIGHT Asset Style Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce one six-panel concept board comparing a survivor character and a feathered raptor in three viable production styles.

**Architecture:** Generate one controlled visual sheet so subject identity, pose, camera, scale, lighting, and palette remain comparable across styles. Treat the result as preview-only style exploration; no generated sheet is accepted as a final animation sprite or production texture.

**Tech Stack:** Built-in image generation, raster PNG preview, PRIMAL NIGHT design specification

## Global Constraints

- Serious survival-thriller tone; no comedy presentation.
- Original prehistoric world; no Jurassic Park branding, logos, costume designs, or facility designs.
- Isometric three-quarter orthographic presentation suitable for a 2D game.
- Same survivor identity and same dinosaur species/design across all three styles.
- No captions, letters, logos, signatures, or watermarks inside the image.
- Preview-only: production sprite sheets require a separate animation and transparency plan after style selection.

---

### Task 1: Generate the controlled six-panel comparison board

**Files:**
- Preview: built-in generated image shown in the Codex task

**Interfaces:**
- Consumes: `/Users/iron/Documents/new-idea/docs/superpowers/specs/2026-07-13-primal-night-design.md`
- Produces: one 3-column by 2-row style comparison board for user selection

- [ ] **Step 1: Define locked subjects**

Use one adult Korean survivor wearing a muted rust-red rain jacket, charcoal cargo pants, hiking boots, a compact dark backpack, and holding a flashlight. Use one anatomically plausible feathered dromaeosaur with charcoal-green plumage, a pale underside, restrained rust-red facial markings, a long rigid tail, and a raised sickle claw.

- [ ] **Step 2: Define the six cells**

Top row contains the survivor; bottom row contains the raptor. Column one is 48px dark pixel art, column two is high-resolution hand-painted 2D, and column three is stylized low-poly 3D pre-rendered as a 2D game asset.

- [ ] **Step 3: Generate the comparison image**

Run one built-in image generation request using a neutral studio-board background, equal cell sizes, matching poses and camera angles, generous spacing, and no text.

Expected: six clearly isolated subjects with recognizable identity continuity and visibly different production styles.

- [ ] **Step 4: Visual acceptance check**

Accept only if all six cells are present, the top/bottom subject mapping is correct, the three style differences are obvious, no trademarked imagery appears, and there is no unwanted text or watermark.

- [ ] **Step 5: Record style decision before production assets**

The user selects one style or a deliberate hybrid. Only then create transparent directional sprites, animation frames, environment tiles, item icons, UI, and Steam marketing assets.

