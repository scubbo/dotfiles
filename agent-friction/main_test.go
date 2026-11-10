package main

// All logs, commands, tool names and messages in these tests are synthetic.
// None is copied from a real session.

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var cliNow = scanStart.Add(time.Hour)

// writeFrictionLogs creates three sessions that each hit a missing command, and
// one in which the human says they do not understand.
func writeFrictionLogs(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	for _, id := range []string{"one", "two", "three"} {
		lines := []string{
			fxLine(t, map[string]any{"seq": 1, "ts": ms(0), "kind": "session_created", "id": id, "workspace": "/synthetic/project", "role": "root", "host": "app"}),
			fxLine(t, map[string]any{"seq": 2, "ts": ms(10), "kind": "item", "type": "tool_call", "data": map[string]any{
				"call_id": "c1", "tool_name": "shell", "arguments_json": jsonString(t, map[string]any{"action": "run", "command": "buildtool lint"})}}),
			fxLine(t, map[string]any{"seq": 3, "ts": ms(20), "kind": "item", "type": "tool_result", "data": map[string]any{
				"call_id": "c1", "tool_name": "shell", "status": "failure",
				"preview": jsonString(t, map[string]any{"exit_code": 127, "error": nil, "output_delta": "sh: examplefmt: command not found\n"})}}),
		}
		if id == "one" {
			lines = append(lines, fxLine(t, map[string]any{"seq": 4, "ts": ms(30), "kind": "item", "type": "user", "data": map[string]any{"text": "I don't understand"}}))
		}
		writeFxLog(t, root, id, lines...)
	}
	return root
}

func runCLI(t *testing.T, args ...string) (string, error) {
	t.Helper()
	var out bytes.Buffer
	err := run(args, &out, cliNow)
	return out.String(), err
}

func TestScanWritesADigestEvidenceAndLedger(t *testing.T) {
	logs, state := writeFrictionLogs(t), filepath.Join(t.TempDir(), "state")

	out, err := runCLI(t, "scan", "--fx-sessions", logs, "--state", state)
	if err != nil {
		t.Fatal(err)
	}
	digestPath := filepath.Join(state, "digests", cliNow.Format("2006-01-02")+".md")
	assertContains(t, out, "1 finding needs a decision", digestPath)

	digest, err := os.ReadFile(digestPath)
	if err != nil {
		t.Fatal(err)
	}
	assertContains(t, string(digest),
		"Scanned 3 sessions (3 started by you)",
		"## Needs a decision (1)",
		"### 1. Command `examplefmt` is not found in agent shells",
		"Seen 3 times in 3 sessions: 3 recent, 0 previous.",
		"    sh: examplefmt: command not found",
	)
	if strings.Contains(string(digest), "did not understand") {
		t.Errorf("a finding seen in one session should stay below the threshold:\n%s", digest)
	}

	ledger, err := LoadLedger(filepath.Join(state, "ledger.json"))
	if err != nil {
		t.Fatal(err)
	}
	if len(ledger.Findings) != 1 {
		t.Fatalf("ledger has %d findings, want 1", len(ledger.Findings))
	}
	for id := range ledger.Findings {
		raw, err := os.ReadFile(filepath.Join(state, "evidence", id+".json"))
		if err != nil {
			t.Fatal(err)
		}
		var evidence struct {
			TotalOccurrences int `json:"total_occurrences"`
		}
		if err := json.Unmarshal(raw, &evidence); err != nil || evidence.TotalOccurrences != 3 {
			t.Errorf("evidence total = %d, err = %v", evidence.TotalOccurrences, err)
		}
	}
}

func TestScanHonoursTheSessionThreshold(t *testing.T) {
	logs, state := writeFrictionLogs(t), filepath.Join(t.TempDir(), "state")

	out, err := runCLI(t, "scan", "--fx-sessions", logs, "--state", state, "--min-sessions", "1")
	if err != nil {
		t.Fatal(err)
	}
	assertContains(t, out, "2 findings need a decision")
	digest, err := os.ReadFile(filepath.Join(state, "digests", cliNow.Format("2006-01-02")+".md"))
	if err != nil {
		t.Fatal(err)
	}
	assertContains(t, string(digest), "### 1. Jack did not understand what the agent said", "    I don't understand",
		"### 2. Command `examplefmt` is not found in agent shells")
}

func TestSetRecordsADecisionThatLaterScansKeep(t *testing.T) {
	logs, state := writeFrictionLogs(t), filepath.Join(t.TempDir(), "state")
	if _, err := runCLI(t, "scan", "--fx-sessions", logs, "--state", state); err != nil {
		t.Fatal(err)
	}
	ledger, err := LoadLedger(filepath.Join(state, "ledger.json"))
	if err != nil {
		t.Fatal(err)
	}
	var id string
	for id = range ledger.Findings {
	}

	out, err := runCLI(t, "set", "--state", state, id, "accepted")
	if err != nil {
		t.Fatal(err)
	}
	assertContains(t, out, "Marked "+id+" as accepted")

	out, err = runCLI(t, "scan", "--fx-sessions", logs, "--state", state)
	if err != nil {
		t.Fatal(err)
	}
	assertContains(t, out, "0 findings need a decision")
	digest, err := os.ReadFile(filepath.Join(state, "digests", cliNow.Format("2006-01-02")+".md"))
	if err != nil {
		t.Fatal(err)
	}
	assertContains(t, string(digest), "## Accepted, waiting for a fix (1)", "When it is fixed: `agent-friction set "+id+" fixed`")
}

func TestCLIReportsMisuse(t *testing.T) {
	state := filepath.Join(t.TempDir(), "state")
	cases := []struct {
		args []string
		want string
	}{
		{nil, "usage: agent-friction"},
		{[]string{"explode"}, "usage: agent-friction"},
		{[]string{"set", "--state", state, "only-an-id"}, "usage: agent-friction set"},
		{[]string{"set", "--state", state, "unknown-id", "fixed"}, `"unknown-id"`},
		{[]string{"scan", "--fx-sessions", filepath.Join(state, "absent"), "--state", state}, "absent"},
		{[]string{"scan", "--no-such-flag"}, "no-such-flag"},
	}
	for _, c := range cases {
		out, err := runCLI(t, c.args...)
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%q: error = %v, want it to mention %q", c.args, err, c.want)
		}
		if out != "" {
			t.Errorf("%q: unexpected output %q", c.args, out)
		}
	}
}
