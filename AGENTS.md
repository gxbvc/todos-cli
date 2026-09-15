# todos-cli

CRUD todo.gxb.vc boards and tasks with a user or admin API key.
Output is always one JSON line: `{"ok":true,"data":...}` or `{"ok":false,"error":"...","code":"..."}`.

## Commands

```bash
todos-cli me
todos-cli users list
todos-cli users show <id|email>
todos-cli board [--user <id|email>]
todos-cli areas list --user <id|email>
todos-cli areas create --user <id|email> -t TITLE [--position N] [--active true|false]
todos-cli projects list --user <id|email>
todos-cli projects create --user <id|email> -t TITLE [--area ID] [--status active|waiting|someday|completed] [--position N]
todos-cli tasks list [--user <id|email>] [--project ID] [--status open|submitted|approved|canceled]
todos-cli tasks get <id> [--user <id|email>]
todos-cli tasks create --user <id|email> -t TITLE [--project ID] [--description HTML] [--due DATE] [--estimate N] [--source-url URL] [--schema JSON|@file] [--force]
todos-cli tasks update <id> --user <id|email> [--title TITLE] [--project ID] [--description HTML] [--due DATE] [--estimate N] [--source-url URL] [--schema JSON|@file] [--field key=value] [--notes TEXT]
todos-cli tasks destroy <id> --user <id|email>
todos-cli tasks approve <id> --user <id|email>
todos-cli tasks submit <id> [--user <id|email>] [--field key=value]
todos-cli tasks reopen <id> [--user <id|email>] [--note TEXT]
todos-cli tasks cancel <id> [--user <id|email>]
todos-cli tasks respond <id> [--user <id|email>] --field key=value [--field key=value] [--notes TEXT]
```

## Write next actions

Every task must be a next physical action. Rules and examples: `write-human-todos` skill.
`tasks create` warns on stderr (and still creates) for a weak title or empty description. `--force` skips the warn.

## Route rules

- `--user` selects admin cross-user routes; email lookup via `users list` requires an admin key.
- Create, update, destroy, and approve require `--user`.
- Submit uses the admin route with `--user`, otherwise self; `reopen --note` requires `--user`.

Requires a tool-local `.env` with `TODOS_API_KEY` and `TODOS_BASE_URL`; mint keys in todo.gxb.vc Settings, not via this CLI.
