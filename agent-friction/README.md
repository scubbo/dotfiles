# agent-friction

`agent-friction` reads the session logs of coding agents and looks for friction
that keeps happening: a command that is missing, a tool call that fails the same
way, a turn that dies, or a message where Jack says he does not understand.
It writes a short digest. Jack decides what to do about each finding.

It reads fx session logs. It does not change them, and it does not call a model.

## How it runs

`./setup.sh` builds the program to `~/.local/bin/agent-friction` and adds a
launchd job, `com.scubbo.agent-friction`. The job runs a scan every Monday at
09:00 and shows a notification when the digest is ready. Setup skips this step
on machines without Go or launchd.

To scan now:

```sh
agent-friction scan
```

A scan covers two periods of 7 days. The digest compares the last 7 days
("recent") with the 7 days before ("previous").

## The digest

Each scan writes `~/.local/state/agent-friction/digests/<date>.md`. It has three
parts:

1. **Needs a decision.** New findings. Findings from messages you typed come
   first, then the most widespread. Accept or reject each one with the command
   printed next to it.
2. **Accepted, waiting for a fix.** Findings you accepted and have not fixed.
3. **Fixed: did it work?** Findings you marked fixed, and how often each one has
   happened since.

```sh
agent-friction set <finding-id> accepted
agent-friction set <finding-id> rejected
agent-friction set <finding-id> fixed
```

A rejected finding never appears again. A finding appears only after it has
affected 3 top-level sessions. A top-level session is one you started; its
subagents count as part of it.

## Evidence for a fixing agent

Each finding has a file `~/.local/state/agent-friction/evidence/<finding-id>.json`.
It lists the 25 most recent occurrences. Each occurrence names the log file, the
record number (`seq`) in that file, the tool call, the command or message, and a
short quote. Give this file to an agent and ask it to find the cause and
propose a fix.

The quotes come from transcripts, which can contain text from web pages and
tool output. The file says so, and the fixing agent must treat them as data.

## What it detects

| Detector | What it finds | Where a fix usually belongs |
|---|---|---|
| `missing-command` | A shell printed `command not found` | Shell environment in this repository |
| `zsh-path-clobber` | A command assigned the zsh variable `path`, and then a command was not found | Agent instructions |
| `turn-failed` | A turn stopped with `failed` or `crash` | fx or the model provider |
| `review-held` | The fx safety review held a tool call, grouped by program | fx permission rules or agent instructions |
| `tool-error` | A tool other than the shell failed, grouped by tool and message | Depends on the tool |
| `user-confusion` | Jack wrote that he did not understand, for example "I don't understand" or "what do you mean" | Agent instructions |
| `user-correction` | Jack pushed back, for example "No, ..." or "that's not what I asked" | Agent instructions or a skill |
| `user-frustration` | Jack swore or sighed | Read the evidence |

A shell command that exits with an error is not friction by itself. Failing
tests and type errors are normal work.

The three `user-` detectors read only messages Jack typed. They ignore quoted
lines, code blocks, and text inside quotation marks.

To add a detector, add an entry to `Detectors` in `detect.go`. A detector is a
function from one session to a list of signals. To read logs from another
agent, write a loader that returns `Session` values, like `LoadFxSessions`.

## Files

Everything the program writes is under `~/.local/state/agent-friction`, and only
you can read it. It quotes work transcripts, so it must stay out of this
repository.

| Path | Content |
|---|---|
| `ledger.json` | Every finding, your decision, and the counts from the last scan |
| `digests/` | One digest for each day a scan ran |
| `evidence/` | One evidence file for each finding |
| `logs/` | Output of the scheduled job |

## Limits

- A session that reads old logs or evidence can print an old error on a line of
  its own. The scan then counts it as a new error.
- fx keeps at most 4096 characters of a tool result in the log. An error after
  that point is not seen.
- The phrase lists are in English and match Jack's wording. They do not find
  confusion that he expresses in another way.
- fx writes log timestamps when a turn is saved, so the scan cannot measure how
  long a failure cost.

## Tests

```sh
cd agent-friction && go test ./...
./test-setup.sh
```
