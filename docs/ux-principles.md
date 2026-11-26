# Forever Companion UX principles

Research summary used to guide and grade the addon's design (November 2026). Goal, in the owner's words: teach people to play WoW so they're **delighted to play and excited for new gear, but never destitute**, without grinding past the point of fun.

The common thread: players enjoy a guide that makes them feel **capable and in charge**. It shows the next good step and why, celebrates rarely, and never guilt-trips. It feels like homework when it commands, interrupts, piles everything on one screen, or punishes a missed day.

## Principles

1. **Suggest, don't command.** Autonomy drives enjoyment. "Good next: Deadmines (lvl 18–23), 3 of your quests end there [Go] [Not today]", not "You must run Deadmines."
2. **One clear next step per page.** The panel competes with the game for attention. Lead with one "Next up" card and one button; tiles and lists come below, detail behind tabs.
3. **"Why" in one line, depth on demand.** "▲ Upgrade: +9 Agility, +4 Stamina (≈ +4% damage)"; tapping or hovering shows the full comparison.
4. **Make progress and the next reward visible.** "Level 20 in about 2 bars: talent point + new spell rank"; "Next upgrade drops from Mr. Smite (Deadmines, boss 4)".
5. **Celebrate rarely, at the size of the moment, only for the player's own wins.** Full card and sound for level-ups and real upgrades; a line of green text for small wins; never celebrate the addon's own work. Sound can be turned off.
6. **Forgive by default; never guilt.** The plan quietly rolls over. No "you missed 3 tasks" and no red overdue counts. After a break: "Welcome back, here's a light plan."
7. **Teach just in time, once, skippably.** "Grey = junk; any merchant buys it. [Got it]", then never again. An "I know WoW" switch hides all tips.
8. **Respect the game's claim on attention.** No pop-ups in combat; collect alerts on the Overview; at most one chat line per event; controls for how often alerts appear.
9. **Money as a safety net, not a scolding.** "Safety net: 12g of 15g (repairs + level-20 training). Selling 4 Linen Cloth would close the gap." Not "You are broke" or red warning bars.
10. **Scannable text, consistent units and colors.** Titles stay to one line; details wrap to two at most, with the full text in a tooltip. Use g/s/c and "Lvl 18–23" formats. Item-quality colors only for items; green always comes with ▲ and a word; red only for real risk.
11. **Big touch targets, layouts that never overlap.** Buttons at least 40–44 px with about 8 px gaps. Whole rows can be tapped, drag scrolls the list, and nothing depends on hover alone.
12. **Make empty states useful.** "No professions yet. From level 5, Mining + Blacksmithing pays for itself. Trainers are in Ironforge."

## Rubric (score 1–5; 3 = acceptable)

| # | Criterion | 1 | 3 | 5 |
|---|---|---|---|---|
| 1 | Next action is clear | Wall of rows that all look equally important | Plan exists but competes with tiles and lists | One obvious next step in 3 seconds; each page leads with its top item |
| 2 | Explains why and teaches | Bare verdicts | Most advice has a reason, but it's cut off or jargon | Plain one-line reason plus detail on demand; novices learn the rule |
| 3 | Tone and player control | Commands, guilt, red overdue counts | Neutral but bossy; nothing can be dismissed | Suggestions can be skipped, encouraging tone, no punishment, players can tune it |
| 4 | Celebration and anticipation | None, or celebrations for trivia | Celebrates, but every event gets the same size | Size matches the moment, the next reward is always visible, sound can be turned off, never in combat |
| 5 | Money coaching | Shames, or ignores money | Shows a target but not how to reach it | Calm, clear target with what it covers, concrete ways to close the gap |
| 6 | Readability and visual order | Text cut off, overlaps, mixed units, color as the only signal | Occasional clipping or dense blocks of text | Nothing lost to clipping, clear title > detail > value order, consistent formats |
| 7 | Touch and layout soundness | Small or overlapping targets, hover-only actions | Usable by touch, some controls cramped | Targets at least 40 px, whole rows tappable, drag scrolls, no overlap at 0.8–1.2 scale |
| 8 | Respect for attention | Pop-ups during play, chat spam | Few interruptions, but no controls | Quiet in combat, alerts collected in one place, clear controls |
| 9 | Page length and depth | Long scrolling pages | Tabs exist, but the first view is crowded | First view fits without scrolling; at most two levels deep |

Pass bar: an average of at least 3.5, with criteria 1, 3 and 6 each at 3 or above.

## Anti-patterns

- Guilt or fear-of-loss wording; red counters for skipped items.
- Big celebration and sound for minor events or for the addon's own actions.
- Every metric at the same visual weight; several "primary" buttons.
- Truncated reasons with no tooltip or way to expand them.
- A tutorial on first launch; tips that keep returning after "Got it".
- Pop-ups, sounds or chat during combat or loading screens.
- Color as the only signal; item-quality colors reused for status.
- Plans that become chores: long checklists, required grinds, no skip.
- Bare verdicts with no reason.
- Gold-optimization pressure ("You're losing 3g/hr") instead of a safety net.
- Hover-only controls, tiny close buttons, labels hidden under buttons.
- Blank pages that say only "No data".

## Sources

Ryan, Rigby & Przybylski 2006 (SDT and games); Tyack & Mekler 2024; NN/g on progressive disclosure, onboarding tutorials and empty states; SAP Fiori and Wikimedia Codex on wrapping and truncation; YNAB's four rules and "Roll with the Punches"; Mobbin's study of 859 streak designs; Smashing Magazine on streaks and notifications; Apple's activity ring pause; Xbox Accessibility Guideline 102; Game Accessibility Guidelines; Android touch target guidance; Mobalytics companion app; RestedXP and Questie for Forever. Full links are in the research report from the session that produced this file.
