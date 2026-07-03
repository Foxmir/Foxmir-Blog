# Unused Fox Divider Character Animation

This folder archives the character-animation attempt for the homepage divider.
It is intentionally not part of the active blog design.

## Why this was paused

The goal was to keep visual continuity with the fox avatar by adding a tiny
walking fox on the divider between sections. The idea was reasonable, but the
implementation route was wrong for this blog.

The failed route was:

1. Generate complete fox walk-cycle frames as bitmap sprites.
2. Remove chroma-key background.
3. Slice the strip into frames.
4. Move the whole sprite across the divider with frame-anchored CSS/JS.

Even after fixing the movement code so the root position did not slide inside a
static frame, the generated frames still had animation-level defects:

- frame-to-frame body scale drift;
- incomplete or uneven gait cycle;
- tail and body popping;
- phases that looked like two normal steps followed by a twitch/stretch;
- generated whole-body frames that could not preserve stable proportions.

The problem is not just code. A generated full-frame sprite strip can look good
as a still contact sheet while failing as motion.

## Archived contents

- `new-fox-divider-walk/`
  - Latest generated fox walk strip and sliced frames.
  - Visually close to the avatar style, but rejected as a motion loop.
- `earlier-rejected-fox-runner/`
  - Earlier generated running fox attempt.
  - Rejected for poor gait and visual quality.
- `earlier-rejected-fox-walker/`
  - Earlier generated walking fox attempt.
  - Rejected for stiff head/tail and incorrect leg motion.
- `probe-snapshots/`
  - Probe HTML snapshot that used character animation.
- `build_fox_sprite_asset.py`
  - Utility snapshot used to remove small fragments and compose sprite sheets.

## If this idea is revived

Do not restart by generating a complete 8- or 10-frame fox strip. That route is
too unstable for gait quality.

Use one of these routes instead:

1. **Layered lightweight rig, preferred for this blog**
   - Create separate transparent parts: body, head, tail, front legs, back legs.
   - Animate with explicit keyframes.
   - Keep planted foot anchors fixed during contact phases.
   - Export to a small sprite/WebP only after the loop is visually correct.

2. **Dedicated animation tool**
   - Use Rive, Spine, or a similar skeletal animation workflow.
   - Export a small web runtime animation or a baked sprite.
   - This is more robust but may be overkill for a quiet static blog.

3. **Use a proven open-source walk cycle as-is**
   - Only if the style mismatch is acceptable.
   - Avoid repainting whole frames unless a real animation workflow preserves
     pose, scale, and timing.

For the active blog direction, prefer an abstract animated fox-color divider:
a narrow color band using orange, red, green, cream, and dark brown accents.
That preserves the avatar color language without introducing a character gait
problem.
