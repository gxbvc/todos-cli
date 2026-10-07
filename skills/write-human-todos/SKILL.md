---
name: write-human-todos
description: >
  Write GTD-quality human todos and optional Areas/Projects for boards like
  todo.gxb.vc. Use when creating or rewriting tasks the human must do, when the
  user says "add todos for me" or "what do you need from me", or after agent
  work leaves human-gated steps. Prefer this over dumping checklists into chat.
---

# Write human todos (GTD)

A good todo can be reopened days later, understood in 10 seconds, and finished
without the chat. Write it into their trusted system, not yours.

## Area, Project, Todo

| Level | What it is | When it ends |
|---|---|---|
| **Area** | Ongoing responsibility, often a client or durable domain | Never. Active or inactive. |
| **Project** | An end state that needs several actions | When the stated outcome is true |
| **Todo** | One physical, visible next action or decision only a human can do | One sitting. Done is unambiguous. |

- Do the agent's work first. Todos are only for what a human must do: money,
  2FA, legal decisions, personal accounts, body, inbox, signature.
- Several human actions need a Project with one atomic todo each, and always
  an open next action or an incubating or waiting state.
- Areas hold Projects, not actions. Name them by domain (`Andy Sibley`,
  `Personal ops`), with no action verb and no due date.
- A standalone todo is fine when one action finishes the outcome.

## Decide what you can first

The reader is tired and will not open anything else. If you can make the call,
make it, and put the reasoning on the ticket. Never file
`Comment on ticket N`, `Decide A vs B`, or a decision memo unless the decision
is irreversible, spends money, or is a taste call only they can make.

Every todo has one of three shapes:

1. **A physical action.** `Text Tom that the human run is done`.
2. **A look-and-riff.** `Look at Since last login and type 3 messy bullets`.
3. **A one-tap pick**, only when you truly cannot choose. One radio field, 2 or 3
   options, recommended first, each with a short example.

## Todo rules

A todo is a physical, visible act. A watcher could see the keyboard, phone,
browser, or body move. Replace `think about`, `look into`, or a bare
`decide` with `Reply yes or no to …`. Always give the next doable step.

### Title

- One outcome. Split independent decisions and deliverables, and never bundle
  "N questions". Use `and` only for one sitting with one done state.
- Strong verb plus object: `Confirm`, `Send`, `Claim`, `Paste`, `Upload`,
  `Pay`, `Grant`, `Reply`. Avoid `Handle`, `Work on`, `Address`, and a bare
  `Review`.
- Name the outcome, not the gesture, so done is obvious.
- 6 to 14 specific words. Cut `quick`, `just`, `for me`, `please`, `simple`.

### Description

- Three short sentences, then steps. Anything more is your context, not their
  next action.
- Every link must open for them. Never a `file://` link (the web app cannot
  open it) or a repo path like `./plans/12`. Say the Finder path in words, or
  `open` the file yourself first.
- Include as needed: a one-line why, facts, numbered steps with exact URLs and
  UI labels, and **Done looks like:** with the required return.
- No AI slop: `Here's what we found`, `As discussed`, `To recap`, `Hope this
  helps`, `Assumption:`, `It appears that`, `You may want to`, hedging, repeated
  titles, or investigation diaries. Prefer steps to prose.
- Never paste in the source email or ticket body.
- Text they must copy (a prompt to paste, an email or text message to send, a
  command) goes in a fenced code block. The card shows a Copy button, and a tap
  on the box copies it. Never put copy text in quotes, italics, or a `>` quote.
  Under a numbered step, indent the block so it lines up with the step text.
  Put a short value to copy (an email address, a subject line) in
  `inline code`. A tap copies it.

  ````markdown
  1. Open https://claude.ai and start a new chat.
  2. Paste this:

     ```
     Write a one-page practice letter of intent. Give it to me as a Word file.
     ```

  3. Click the Word file to download it.
  ````
- State a blocker as cause, then action. No `Unfortunately`. No `There seems to
  be a problem`.
- Never put a secret in prose. Ask for it with a password field.

### Self-contained or not filed

The reader opens this cold, weeks later, with the project forgotten. It must
carry every fact they need to decide and act, and never depend on the chat,
your discovery history, or a private plan or PR. If they have to look something
up to start, the todo is not finished. You are.

**Never name a thing without carrying the thing.** These all fail:

| Written | Why it fails |
|---|---|
| `one line each for A3, B2, D5, D9` | Bare labels. The reader cannot judge what they cannot see. |
| `In Notes, type …` | Which notes? No link, no app, no file. |
| `Leave the Taiwan wording blank` | An unexplained proper noun carries the whole meaning. |
| `Do this in the Wave 1 workbook, not the old file` | Two unnamed files, one defined only as "not the other one". |
| `Reply on the existing thread` | Which thread, in which mailbox, from when? |

Fix it by inlining or linking, and preferably both:

- **Inline the decision material.** Seven exhibits to grade means seven titles
  in the description, one per line, each with the one fact that decides it.
- **Link with an `https://` URL.** A ticket number, a plan path, a filename, or
  a `file://` link is not a link.
- **Spell out every proper noun the first time.** `Taiwan` becomes
  `the Taiwan question (does China blockade or strike Taiwan before 30 Jun 2027)`.
- **If you cannot inline it, you cannot file it.** Go find the thing first, or
  file the todo that produces it instead.

**Do not encode someone else's state.** `Leave it blank for Owen` and
`Send Owen the HTML` both go wrong the moment Owen moves. Write what the reader
does with what is true now, and re-check any todo that waits on a third party
before you hand it back.

**Do not depend on a thing that does not exist yet.** `Send the report` with no
report is two todos, and only the first can be filed today.

The test: give the todo to a competent stranger with no access to your chat,
files, or memory. If they cannot start within 10 seconds, rewrite it.

### Estimate and source (optional)

Both are `todos-cli` flags, not description text.

- `--estimate N` sets `estimated_minutes` and shows a `~N min` pill on the card.
  Give it whenever you can name a number: `--estimate 2`, `--estimate 15`. A
  todo you cannot estimate is not scoped yet, so split it. Never write `quick`,
  `a bit`, or `shouldn't take long` in the description instead.
- `--source-url URL` sets `source_url`: the ticket that created this todo or the
  one it depends on. Hidden in the UI, readable through the API. It keeps the
  trail out of the description. Must be `http://` or `https://`.

### Plan day (`--do-on`)

`--do-on DATE` puts the todo in the person's Today on that day. Set it only
when the person chose the day ("I will call the bank Friday"). Never set it to
today to get their attention: Today fills with todos nobody planned, and the
ones that matter get lost. A real deadline is `--due`. Importance is
`--priority`. With no deadline and no day the person chose, the todo waits in
Needs a date, where the person picks a day.

### Response fields

One instruction field per value you need back. No fields when marking done is
enough.

| Type | Use it for |
|---|---|
| `text` | A short answer: a name, a number, an order id. |
| `textarea` | A longer answer: notes, a pasted reply. |
| `url` | A link they paste back. |
| `password` | A secret. Only the asker reads it back, on the web page. Never ask for a secret in prose. |
| `file` | An upload. |
| `voice` | A voice memo, for a talk or record task. |
| `radio` | One pick from 2 or more short options, recommended first. |
| `checkboxes` | Any number of picks, when more than one can apply. |

Each field has a `label` and a `type`. `radio` and `checkboxes` need
`options`. Set `"required": true` when Done must wait for the answer.

## Projects

A short outcome title (`Website launch`, `Anthropic billing`). Describe the
finished state, not a task list. Todos hold the next actions.

On todo.gxb.vc, put a todo in an internal project unless the user names an
external one (`external: true`: people outside your email domain can see it),
and only then pass `allow_external` (`--allow-external` in todos-cli).

## When to split

Rewrite or split when:

- there are two logins, decisions, or deliverables;
- half can finish while half is blocked;
- "mark done" could mean more than one thing; or
- the agent can do any part instead.

## How todo.gxb.vc scores it

The server asks Jev 7 yes/no questions about the title, the description, and
each field's label, type, and options. It never reads answers, comments, or
secrets. Each check passes at its own floor. The score is the weakest check:
70 or more means all 7 pass. While the gate is on, a to-do for someone else
that fails a blocking check is refused with each failed check and its hint.
A to-do for yourself is scored but never refused.

| Check | Blocks | Passes when |
|---|---|---|
| `physical_action` | yes | One act a watcher could see: send, pay, upload, call, sign, type a short answer, pick an option. |
| `done_is_obvious` | yes | The doer knows for sure when they are finished. |
| `strong_verb` | no | The title starts with a strong verb: Send, Pay, Reply, Confirm, Upload. |
| `prework_done` | yes | You did the prep. For a send, the draft is in the description, in a code block they can copy. For a choice, the options are listed. |
| `self_contained` | yes | The assignee can start in 10 seconds from the card and their own accounts. |
| `one_outcome` | yes | One sitting, one result. |
| `human_gated` | no | Only a person can do it. |

Check a draft before you file it: `todos-cli tasks check` or the MCP tool
`todos_check_quality`. Fix each failed check with its hint.

## Before you create it

Before `tasks create`, delete or fix:

1. A title whose verb is `Review`, `Handle`, `Look into`, `Think about`, or a
   bare `Decide` with no yes/no.
2. Any sentence about what you did or found.
3. Anything they must open to understand it: a ticket number, a plan path, a
   `file://` link, `as discussed`.
4. Any bare identifier (`A3`, `D12`, `the Wave 1 workbook`, `the existing
   thread`) not inlined or linked with an `https://` URL.
5. Any proper noun a stranger would have to ask about.
6. Any instruction that depends on what a third party has or has not done yet.
7. Any decision you could have made yourself.
8. Any hedge: `might`, `probably`, `you may want to`.
9. Any check that failed in `tasks check` or `todos_check_quality`.

Then check: from the title and first sentence alone, do they know what to
physically do, and where? If not, rewrite it.

## Rewrite examples

**Bad:** `Answer two quick yes/no questions for me`  
**Good:** two todos: `Decide whether to enable S3 versioning on prod-assets
(yes/no)` and `Decide whether to delete unused dev-scratch bucket (yes/no)`.
Each gives the consequences, cost, recommendation, and a yes/no field.

**Bad:** `Run one AWS command and paste what it says`  
**Good:** `Paste aws organizations describe-account output to confirm management
account ID`, with the command, the profile and region, the line that matters,
and why.

**Bad:** `Handle Anthropic billing`  
**Good:** Project outcome "Anthropic account funded with auto-reload on". Todo:
`Put money on the Anthropic account and turn on auto-reload`, with the URL, how
much to add, and where the toggle is.

**Bad:** `Type keep, rebuild, or cut for each Wave 1 exhibit`, body `In Notes,
one line each for A3, B2, D5, D9, D12, D14, D15.`  
**Good:** one todo per exhibit, each with that exhibit's title, what it shows
now, and why it is in question.

**Bad:** `Review items 343, 159, and 1981`  
**Good:** one todo per item, each with that item's title, the one fact that
decides it, and a yes/no or radio field. If they must open the record, link the
exact `https://` URL where they act, not the id.

**Good bar:**

`Claim your Google Business Profile and start verification today`  
`Turn off call routing on the Psychology Today listing`  
`Decide whether to cancel Squarespace once the new site is live and tell me yes or no`

## Agent workflow

When asked to do complex work and add todos for the human parts:

1. Finish everything an agent can do.
2. Group the rest: an Area for the domain or client, a Project for a multi-step
   outcome, atomic todos under it.
3. File fewer, sharper todos. Vague extras steal attention.
4. None of them may need the chat.
5. To ask or tell the person something about a to-do that already exists,
   post a comment on it (`todos-cli tasks comment <id> "TEXT"` or the MCP
   tool `todos_comment`). Do not file a new to-do or rewrite the description
   for that. A comment never changes the status: a to-do in review stays in
   review.
