# UX review, November 2026

Graded against [ux-principles.md](ux-principles.md) by reading the code (no screenshots).

## Scores before changes

| # | Criterion | Score |
|---|---|---|
| 1 | Next action is clear | 2 |
| 2 | Explains why and teaches | 3 |
| 3 | Tone and player control | 3 |
| 4 | Celebration and anticipation | 3 |
| 5 | Money coaching | 3 |
| 6 | Readability and visual order | 3 |
| 7 | Touch and layout soundness | 3 |
| 8 | Respect for attention | 2 |
| 9 | Page length and depth | 3 |

Average 2.8. This fails the pass bar (an average of at least 3.5, with criteria 1, 3 and 6 each at 3 or above).

## What changed in response

1. **Next up card** at the top of Overview, with one main button and Not now. It offers, in order: an upgrade you can equip, a talent point, finished quests to turn in, then a good zone to quest in.
2. **Overview tabs** are now Now, Coming up and Leveling. "To do" was merged into Now as "Also worth doing", and headers that repeated the tab name were dropped.
3. **Calm money.**
   - A Safety net bar with what it covers and how to close the gap ("Selling your bag items (~3g) would cover it").
   - Spendable at 0 reads "0, all set aside".
   - No red warnings; costs over your safety net read "after your safety net".
4. **Plain upgrade numbers.** Upgrades show "+8%" or "Upgrade". Raw scores moved to tooltips, and Equipped shows item level.
5. **Quieter celebrations.**
   - No cards during combat; they're held until combat ends.
   - Upgrades under 3% get one chat line instead of a card.
   - No duplicate level-up or talent chat lines, and no talent nag at login.
   - Card text no longer runs under the button.
6. **Next reward visible.** "Next up: level N" lists what that level brings. The Gear page has a Coming soon tab.
7. **Gear page.**
   - Upgrades in your bags equip with a tap.
   - New "What to chase" tab with one row per weak slot: the best find, an "Also:" line with other sources, and what you wear now.
8. **Just-in-time tips** with Got it, and an I know WoW switch in Settings.
9. **Touch and layout.**
   - Tabs and choice buttons are 40 px, with 8 px gaps.
   - Footer buttons are 36 px and sidebar buttons 40 px.
   - The tab bar makes room when it wraps.
   - Tile labels no longer wrap into the values above them.
10. **Guild polish.**
    - "Note to Claude" became "Leave a note".
    - The welcome message shows only on the first login ever.
    - The "recorded N recipes" messages are debug-only.
    - Many wording fixes for tone and jargon. For example, "abandon" became "fine to drop", "levels behind" became "levels below you", and AH "cut" became "fee".

## Kept, because the review praised them

- **Gear:** why-explanations, including set bonuses.
- **Bags:** the four verdicts with "Other options".
- **Money:** the itemised safety net and Skip grinds.
- **Talents:** "Best next" with "Rather stay in X?".
- **Celebrations:** the quieter later-gear card, and the friendly tone ("Nice work", "Go adventure!").
- **Layout:** section tabs, drag-to-scroll and whole-row taps.
- **Safety:** confirmation dialogs.

## Re-grade

| # | Criterion | Before | After the changes |
|---|---|---|---|
| 1 | Next action is clear | 2 | 4 |
| 2 | Explains why and teaches | 3 | 4 |
| 3 | Tone and player control | 3 | 4 |
| 4 | Celebration and anticipation | 3 | 4 |
| 5 | Money coaching | 3 | 4 |
| 6 | Readability and visual order | 3 | 3 |
| 7 | Touch and layout soundness | 3 | 4 |
| 8 | Respect for attention | 2 | 4 |
| 9 | Page length and depth | 3 | 3 |

Average 3.8: **pass**.

### Fixed after the re-grade

- **Bugs:**
  - Celebration cards no longer overflow; the icon is now anchored to the top.
  - A queued card can no longer appear mid-combat.
  - "Open plan" opens the Overview instead of toggling the window.
  - Profession trainer reminders are back on Overview.
  - Chase rows show the right icon.
  - The Next up item is no longer repeated in the list.
  - "Upgrade in your bags" rows only show gear you can wear now.
  - The zone card has a real button.
  - Next-level items are de-duplicated.
  - Single-section pages no longer show an empty tab bar.
- **Now tab:** "Also worth doing" moved to its own Quick wins tab, and Overview has two tiles (level, gold) so the plan starts higher.
- **One upgrade language:** percentages everywhere, drop chances read "12% drop", shorter tile labels, and truncated rows get a tooltip with the full text.
- **Closing the gap:** the Money safety net explains how to close the gap, and Bags leads with a sell card when you're below it.
- **Touch:**
  - "Got it" and the card close button are 40 px.
  - Tapping an item row pins its full tooltip, so disenchant odds no longer need hover.
