# The educational layer

The mission: a child finishes a play session knowing real things about ores,
metals and the inside of the Earth — without ever feeling taught at.

## The core principle

**Facts are earned, recalled, and paid for. They are never just displayed.**

A fact shown in a menu is skipped. The same fact delivered at the moment a child
digs up the rock it describes lands, because curiosity is already open. So the
teaching is built on three beats, each mapped to a mechanic:

| Beat | Mechanic | Learning principle |
|---|---|---|
| Open the loop | Undiscovered ore shows as a silhouette `? ? ?` in the Codex | Information-gap curiosity |
| Close it | **Discovery Card** on first mine | Encoding at peak curiosity |
| Reinforce it | **Geologist's Log** quiz, later, for ether | Spaced retrieval practice |

Retrieval practice — being asked to *recall* rather than *re-read* — is the
best-evidenced study technique there is. The Log is that, wearing a payday hat.

## Self-Determination Theory

Motivation is designed against SDT's three needs, the best-supported model for
game-based learning:

- **Autonomy** — the Log is entirely optional and player-launched. Cards can be
  dismissed instantly. Nothing educational ever gates progress. A child who only
  wants to dig can ignore all of it and still finish the game.
- **Competence** — questions are only ever drawn from ores the player has
  actually mined and layers they have actually reached. The quiz can never ask
  about something it has not first taught.
- **Relatedness** — facts connect underground rock to the child's own world:
  iron is in your blood, gold is older than the planet, opal is why the colours
  move when you tilt it.

## Why the Discovery Card pauses the game

It pauses deliberately. A child needs time to read without the pod falling, and
the pause marks the moment as *important*. There are only six ores, so this can
happen at most six times in an entire playthrough — a rare ceremony, not an
interruption.

(The automated test has to dismiss these cards like a real player would; see
`_clear_cards()` in `tests/test_runner.gd`.)

## Why wrong answers cost nothing

A wrong answer shows the correct one plus **why**, and moves on. No score
penalty, no lost ether, no retry gate.

Punishing a wrong guess teaches a child that opening the Log is risky, and the
fastest way to kill a voluntary learning feature is to make it feel like a test
they can fail. Rewarding correct answers and explaining incorrect ones keeps the
feature something they choose to open.

The end-of-round message praises **effort**, never ability — "you have really
been paying attention" rather than "you're so clever". Ability praise makes
children avoid harder challenges to protect the label.

## Content and accuracy

All teaching copy lives in `data/codex.json`, deliberately separated from
`balance.json` so a science reviewer can edit facts without touching tuning
numbers, and so the Codex, Discovery Cards and quiz can never drift apart.

Each ore carries: `what`, `forms`, `where`, `uses`, a `wow` hook, and its quiz
questions. Each Earth layer carries a `fact` and questions.

Facts are drawn from mainstream geology/metallurgy sources — GIA, Geology
Science, Britannica, Provident Metals, the Australian Museum — and pitched at
roughly ages 8–13. The `wow` line is the one a child retells at dinner, so it is
rendered largest on the card:

- Iron — it is in your blood, and that is why blood is red
- Silver — the best electrical conductor of any metal, better than gold
- Gold — every atom was forged in space before Earth existed
- Emerald — rarer than diamond, because its two ingredients rarely meet
- Ruby — the same mineral as sapphire; chromium makes it red
- Black Opal — the colours are diffraction, not pigment

**If you change a fact, change it in `codex.json` only.** Nothing is duplicated
in code; the old hard-coded `CODEX_NOTES` dictionary in `main_menu.gd` was
deleted precisely so there is exactly one source of truth.

## Enemies teach too

The three newer enemies each threaten a *different* resource, which makes the
underlying systems legible through play rather than through text:

- **Magma Slug** — radiates heat. Teaches the heat/cooldown system by attacking it.
- **Crystal Bat** — fast erratic flyer. Teaches that open rooms beat tight shafts.
- **Rock Golem** — dormant until disturbed, then blocks the corridor. Teaches
  that route planning and heat are the same budget.

Each telegraphs its state change visibly (halo, wake-up shudder) so a child can
learn the rule by watching rather than by dying.
