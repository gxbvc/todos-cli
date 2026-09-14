---
name: write-human-todos
description: >
  Write GTD-quality human todos and optional Areas/Projects for boards like
  todo.gxb.vc. Use when creating or rewriting tasks the human must do, when the
  user says "add todos for me" or "what do you need from me", or after agent
  work leaves human-gated steps. Prefer this over dumping checklists into chat.
---

# Write human todos (GTD)

Create work the human can reopen days later, understand in 10 seconds, and
finish without chat. Write into their trusted system, not yours.

## Hierarchy: Area → Project → Todo

| Level | Definition | End condition |
|---|---|---|
| **Area** | Ongoing responsibility, often a client or durable domain | Never done; active or inactive |
| **Project** | End-state requiring multiple actions | A stated outcome is true |
| **Todo** | One physical, visible next action or decision only a human can do | One sitting; unambiguous |

- Complete all agent-capable work. Todos are **human-gated only**: money, 2FA,
  legal decisions, personal accounts, body, inbox, signature.
- Multiple human actions require a Project and atomic todos. A Project needs an
  open next action or an incubating/waiting state.
- Areas group Projects, not actions. Use domain names (`Andy Sibley`, `Personal
  ops`), without action verbs or due dates.
- A standalone todo is fine when one action completes the outcome.

## Pre-digest first

The reader is often tired. Assume they will not open anything else. If you can
make the call yourself, make it, and put the reasoning on the ticket instead.
Never file `Comment on ticket N`, `Decide A vs B`, or a decision memo unless the
decision is irreversible, spends money, or is a taste call only they can make.

Every todo is one of three shapes:

1. **A physical action.** `Text Tom that the human run is done`.
2. **A look-and-riff.** `Look at Since last login and type 3 messy bullets`.
3. **A one-tap pick**, only when you truly cannot choose. One radio field, 2–3
   options, recommended first, each option a short example.

## Todo rules

A todo is an immediate **physical, visible** activity: a watcher could see the
keyboard, phone, browser, or body action. Replace `think about`, `look into`, or
bare `decide` with `Reply yes or no to …`. Require the next doable step.

### Title

- **One outcome.** Split independent decisions/deliverables. Use `and` only for
  one sitting and one done-state.
- Use a strong verb + object: `Confirm`, `Send`, `Claim`, `Paste`, `Upload`,
  `Pay`, `Grant`, `Reply`. Avoid `Handle`, `Work on`, `Address`, or bare `Review`.
- State the outcome, not a gesture; make done obvious.
- Never bundle “N questions”; create one todo per decision.
- Aim for 6–14 specific words. Cut `quick`, `just`, `for me`, `please`, `simple`.

### Description

- **Three short sentences, plus steps.** Prose past that is your context, not
  their next action.
- Make it **self-contained**: include every fact needed; never depend on chat,
  discovery history, or a private plan/PR.
- Every link must open for them. **Never a `file://` link** (it does not open
  from the web app) and never a repo path like `./plans/12`. Say the Finder
  path in words, or `open` the file yourself before assigning the todo.
- Include as needed: one-line why, facts, numbered steps with exact URLs/UI
  labels, and **Done looks like:** the required return.
- **No AI sloop:** omit `Here's what we found`, `As discussed`, `To recap`,
  `Hope this helps`, `Assumption:`, `It appears that`, `You may want to`,
  hedging, repeated titles, and investigation diaries. Prefer steps to prose.
- Never dump the source email or ticket body into the description.
- State a blocker as cause then action. No `Unfortunately`, no `There seems to
  be a problem`.
- Never put secrets in prose; request them through a password field.

### Self-contained or not filed

A todo is read cold, weeks later, by someone who has forgotten the project. It
must carry everything needed to decide and act. If the reader has to look
something up to start, the todo is not finished; you are.

**Never name a thing without carrying the thing.** These all fail:

| Written | Why it fails |
|---|---|
| `one line each for A3, B2, D5, D9` | Bare labels. The reader cannot judge what they cannot see. |
| `In Notes, type …` | Which notes? No link, no app, no file. |
| `Leave the Taiwan wording blank` | An unexplained proper noun doing load-bearing work. |
| `Do this in the Wave 1 workbook, not the old file` | Two unnamed files, one defined only as "not the other one". |
| `Reply on the existing thread` | Which thread, in which mailbox, from when? |

Fix by **inlining or linking, and preferably both**:

- **Inline the decision material.** If they must grade seven exhibits, put the
  seven titles in the description, one per line, each with the one fact that
  decides it. A decision todo carries its own evidence.
- **Link with a URL that opens for them.** `https://` only. A ticket number,
  a plan path, a filename, or a `file://` link is not a link.
- **Spell out every proper noun on first use.** `Taiwan` becomes
  `the Taiwan question (does China blockade or strike Taiwan before 30 Jun 2027)`.
- **If you cannot inline it, you cannot file it.** Go find the thing first, or
  file the todo that produces it instead.

**Do not encode someone else's state.** `Leave it blank for Owen` and
`Send Owen the HTML` both rot silently the moment Owen moves. Write what the
reader does with what is true now, and re-check any todo that waits on a third
party before you hand it back to them.

**Do not depend on a thing that does not exist yet.** `Send the report` when no
report exists is two todos, and only the first one is fileable today.

The test: hand the todo to a competent stranger with no access to your chat,
your files, or your memory. If they cannot start within 10 seconds, rewrite it.

### Estimate and source (optional)

Both are `todos-cli` flags, not description text.

- `--estimate N` sets `estimated_minutes` and renders as a `~N min` pill on the
  card. Give it whenever you can name a number: `--estimate 2`, `--estimate 15`.
  A todo you cannot estimate is not scoped yet, so split it. Never write
  `quick`, `a bit`, or `shouldn't take long` in the description instead.
- `--source-url URL` sets `source_url`, the ticket that created this todo or the
  one it depends on. Hidden from the UI, readable through the API. Use it so
  the trail survives without spending description space on ticket archaeology.
  Must be `http://` or `https://`.

### Response fields

- One human-facing instruction field per return value: text, textarea, URL,
  password, file, radio, or checkboxes. Use radio for a single pick from two or
  more short options, with the recommended option first. Use checkboxes when
  more than one option can apply. Omit fields when marking done is enough.

## Projects

Use a short outcome title (`Website launch`, `Anthropic billing`). State
completed reality, not a task list; todos hold next actions.

## Split test

Rewrite or split when:

- there are two logins, decisions, or deliverables;
- half can finish while half is blocked;
- “mark done” could be ambiguous; or
- the agent can do any part instead.

## Pre-create check

Before `tasks create`, delete or fix:

1. A title whose verb is `Review`, `Handle`, `Look into`, `Think about`, or a
   bare `Decide` with no yes/no.
2. Any sentence describing what you did or found.
3. Anything they must open to resolve: a ticket number, a plan path, a
   `file://` link, `as discussed`.
4. Any bare identifier (`A3`, `D12`, `the Wave 1 workbook`, `the existing
   thread`) whose content is not inlined or linked with an `https://` URL.
5. Any proper noun a stranger would have to ask about.
6. Any instruction that depends on what a third party has or has not done yet.
7. Any decision you could have made yourself.
8. Any hedge: `might`, `probably`, `you may want to`.

Then verify: reading only the title and the first sentence, do they know what
to physically do, and where? If no, rewrite it.

## Rewrite examples

**Bad:** `Answer two quick yes/no questions for me`  
**Good:** two todos: `Decide whether to enable S3 versioning on prod-assets
(yes/no)` and `Decide whether to delete unused dev-scratch bucket (yes/no)`.
Each gives consequences, cost, recommendation, and a yes/no field.

**Bad:** `Run one AWS command and paste what it says`  
**Good:** `Paste aws organizations describe-account output to confirm management
account ID`. Include the command, known profile/region, relevant line, and why.

**Bad:** `Handle Anthropic billing`  
**Good:** Project outcome: “Anthropic account funded with auto-reload on”; todo:
`Put money on the Anthropic account and turn on auto-reload`, with URL, amount
guidance, and toggle location.

**Bad:** `Type keep, rebuild, or cut for each Wave 1 exhibit` / body: `In Notes,
one line each for A3, B2, D5, D9, D12, D14, D15.`  
**Good:** one todo per exhibit, or one todo with a radio per exhibit, each
carrying the exhibit's title, what it currently shows, and why it is in
question. The reader grades what is on the screen, not what they remember.

**Good bar:**

`Claim your Google Business Profile and start verification today`  
`Fix your Psychology Today listing and turn off call routing`  
`Decide whether to cancel Squarespace once the new site is live and tell me yes or no`

## Agent workflow

When asked to do complex work and add todos for human dependencies:

1. Finish all agent-capable work.
2. Group the remainder: Area for domain/client → Project for multi-step outcome
   → atomic todos.
3. Emit fewer, sharper todos; vague extras steal attention.
4. Require no chat context.
