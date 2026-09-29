# todos-cli

CRUD todo.gxb.vc boards and tasks with a user or admin API key.
Output is always one JSON line: `{"ok":true,"data":...}` or `{"ok":false,"error":"...","code":"..."}`.

## Commands

```bash
todos-cli me
todos-cli users list
todos-cli users show <id|email>
todos-cli users remind <id|email>
todos-cli board [--user <id|email>]
todos-cli areas list --user <id|email>
todos-cli areas create --user <id|email> -t TITLE [--position N] [--active true|false]
todos-cli projects list --user <id|email>
todos-cli projects create --user <id|email> -t TITLE [--area ID] [--status active|waiting|someday|completed] [--position N]
todos-cli projects create -t TITLE [--area ID]
todos-cli projects invite <id> --email EMAIL
todos-cli invites list
todos-cli invites accept <id> [--area ID]
todos-cli tasks list [--user <id|email>] [--project ID] [--status open|submitted|approved|canceled]
todos-cli tasks get|show <id> [--user <id|email>]
todos-cli tasks check -t TITLE [--description HTML] [--schema JSON|@file]
todos-cli tasks create -t TITLE --project ID [--assignee EMAIL] [--description HTML] [--due DATE] [--schema JSON|@file] [--star]
todos-cli tasks create --user <id|email> -t TITLE [--project ID] [--description HTML] [--due DATE] [--estimate N] [--source-url URL] [--schema JSON|@file] [--star]
todos-cli tasks update <id> --user <id|email> [--title TITLE] [--project ID] [--description HTML] [--due DATE] [--estimate N] [--source-url URL] [--schema JSON|@file] [--field key=value] [--notes TEXT]
todos-cli tasks destroy <id> --user <id|email>
todos-cli tasks approve <id> [--user <id|email>]
todos-cli tasks send-back <id> --note TEXT
todos-cli tasks star <id> [--off] [--user <id|email>]
todos-cli tasks submit <id> [--user <id|email>] [--field key=value]
todos-cli tasks reopen <id> [--user <id|email>] [--note TEXT]
todos-cli tasks cancel <id> [--user <id|email>]
todos-cli tasks remind <id> --user <id|email>
todos-cli tasks respond <id> [--user <id|email>] --field key=value [--field key=value] [--notes TEXT]
```

`tasks remind` re-sends mail for one open to-do; `users remind` sends one email covering everything open on that user's board. Both are a re-send, not a new assignment — they never touch a to-do's assigned/pending state, so they cannot suppress a later real assignment email. Admin key required for both.

## Write next actions

Every task must be a next physical action. Rules and examples: `write-human-todos` skill.

The server scores every task on 7 checks (Jev). `tasks create`, `tasks get`/`show`, and `tasks check` print the score and each check on stderr, with the hint for each fail. The JSON has the whole `quality` object. Run `tasks check` on a draft first. While the gate is on, a task for someone else that fails a blocking check is refused: exit 1, `code` `HTTP_422`, the failed checks on stderr, and `quality` in the envelope. There is no flag that skips the check.

## Route rules

- `--user` selects admin cross-user routes; email lookup via `users list` requires an admin key.
- `tasks create` without `--user` is the member route (`POST /tasks.json`): a task in one of my projects, for me or for `--assignee EMAIL` (an active member of that project). `--project` is required on this route, so a forgotten `--user` fails. `--estimate` and `--source-url` need `--user`.
- `projects create` without `--user` is the member route (`POST /projects.json`): a project I own, in one of my own areas. It prints "No --user: making the project in your own board." on stderr, so a forgotten `--user` is seen. `projects invite <id> --email EMAIL` is the owner's invite (`POST /projects/:id/invites.json`); a refusal exits 1 with the server's reason.
- `invites list` shows the project invites sent to my own account email (`GET /invites.json`). `invites accept <id> [--area ID]` joins one (`POST /invites/:id/accept.json`, id like `project-4`), filed in one of my areas or my Shared area. Any invite I cannot accept is `HTTP_404`. Only accept an invite the user asked you to. An invited project is not on my board until I accept, so `board` and `tasks list` print `You have N open invites. Run: todos-cli invites list` on stderr when there are any.
- Update and destroy require `--user`.
- `approve` and `star` use my own route without `--user` (I am the reviewer, or for `star` the assignee) and the admin route with it. `send-back` is the reviewer's route only; the admin equivalent is `reopen --user --note`.
- Submit uses the admin route with `--user`, otherwise self; `reopen --note` requires `--user`.

Requires a tool-local `.env` with `TODOS_API_KEY` and `TODOS_BASE_URL`; mint keys in todo.gxb.vc Settings, not via this CLI.

The skill in `skills/write-human-todos/SKILL.md` is also served by chat as the MCP resource `gxb://todos/write-human-todos`. After editing it, copy it to `~/projects/chat/app/views/mcp/skills/write_human_todos.md` (chat's `Mcp::ResourcesTest` checks that the two match). `~/.pi/agent/skills/write-human-todos` is a symlink to this folder.
