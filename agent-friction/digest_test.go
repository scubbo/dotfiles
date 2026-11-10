package main

// All logs, commands, tool names and messages in these tests are synthetic.
// None is copied from a real session.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func digestInput(entries ...Entry) DigestInput {
	return DigestInput{
		Now:              scanNow,
		Period:           week,
		Sessions:         40,
		TopLevelSessions: 12,
		Entries:          entries,
		EvidenceDir:      "/state/evidence",
		Top:              10,
	}
}

func assertContains(t *testing.T, text string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(text, want) {
			t.Errorf("missing %q in:\n%s", want, text)
		}
	}
}

func TestRenderDigestDescribesAProposedFinding(t *testing.T) {
	input := digestInput(Entry{
		ID: "missing-command-examplefmt-abc123", Title: "Command `examplefmt` is not found in agent shells", FixLocation: "Shell environment",
		Status: Proposed, Sessions: 5, Occurrences: 9, Recent: 6, Previous: 3, LastSeen: yesterday,
	})
	input.Examples = map[string]string{"missing-command-examplefmt-abc123": "sh: examplefmt: command not found\nexit status 127"}

	digest := RenderDigest(input)
	assertContains(t, digest,
		"# Agent friction digest: "+scanNow.Format("2006-01-02"),
		"Scanned 40 sessions (12 started by you) from "+scanNow.Add(-2*week).Format("2006-01-02")+" to "+scanNow.Format("2006-01-02"),
		`"Recent" means the last 7 days`,
		"## Needs a decision (1)",
		"### 1. Command `examplefmt` is not found in agent shells",
		"Seen 9 times in 5 sessions: 6 recent, 3 previous. Last seen "+yesterday.Format("2006-01-02")+".",
		"Where a fix belongs: Shell environment",
		"Evidence for a fixing agent: `/state/evidence/missing-command-examplefmt-abc123.json`",
		"Accept: `agent-friction set missing-command-examplefmt-abc123 accepted`",
		"Reject: `agent-friction set missing-command-examplefmt-abc123 rejected`",
		"    sh: examplefmt: command not found exit status 127\n",
	)
}

func TestRenderDigestRanksProposedFindingsAndCutsTheList(t *testing.T) {
	input := digestInput(
		Entry{ID: "few", Title: "Few", Status: Proposed, Sessions: 3, Occurrences: 30},
		Entry{ID: "many", Title: "Many", Status: Proposed, Sessions: 9, Occurrences: 9},
		Entry{ID: "some", Title: "Some", Status: Proposed, Sessions: 3, Occurrences: 40},
	)
	input.Top = 2

	digest := RenderDigest(input)
	assertContains(t, digest, "## Needs a decision (3)", "### 1. Many", "### 2. Some",
		"1 more finding is not shown. Use `--top` to show more.")
	if strings.Contains(digest, "Few") {
		t.Errorf("the lowest-ranked finding should be cut:\n%s", digest)
	}
}

func TestRenderDigestSeparatesFindingsByDecision(t *testing.T) {
	changed := scanNow.Add(-3 * 24 * time.Hour)
	digest := RenderDigest(digestInput(
		Entry{ID: "todo", Title: "Accepted one", Status: Accepted, Sessions: 4, Occurrences: 6, Recent: 2, Previous: 4, LastSeen: yesterday},
		Entry{ID: "worked", Title: "Fix that worked", Status: Fixed, StatusChanged: changed, Recent: 0, Previous: 7},
		Entry{ID: "failed", Title: "Fix that failed", Status: Fixed, StatusChanged: changed, SinceStatusChange: 3, Recent: 3, Previous: 7},
		Entry{ID: "noise", Title: "Rejected one", Status: Rejected, Sessions: 50, Occurrences: 90},
	))

	assertContains(t, digest,
		"No findings need a decision.",
		"## Accepted, waiting for a fix (1)",
		"### Accepted one",
		"When it is fixed: `agent-friction set todo fixed`",
		"## Fixed: did it work? (2)",
		"- Fix that worked: not seen since it was marked fixed on "+changed.Format("2006-01-02")+" (0 recent, 7 previous).",
		"- Fix that failed: STILL HAPPENING. Seen 3 times since it was marked fixed on "+changed.Format("2006-01-02")+" (3 recent, 7 previous).",
	)
	if strings.Contains(digest, "Rejected one") {
		t.Errorf("rejected findings should not appear:\n%s", digest)
	}
}

func TestWriteEvidencePointsAFixingAgentAtTheLogs(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "evidence")
	sessions := indexSessions([]Session{
		{ID: "top", Workspace: "/synthetic/project", LogPath: "/fx/top/log.jsonl"},
		{ID: "child", ParentID: "top", Workspace: "/synthetic/project", LogPath: "/fx/child/log.jsonl"},
	})
	finding := Finding{ID: "missing-command-examplefmt-abc123", Detector: "missing-command", Key: "examplefmt", Title: "Command `examplefmt` is not found", FixLocation: "Shell environment"}
	for i := range 30 {
		finding.Signals = append(finding.Signals, Signal{
			SessionID: "child", Seq: 100 - i, CallID: fmt.Sprintf("call-%d", i), Time: yesterday,
			Input: "buildtool lint", Excerpt: "sh: examplefmt: command not found",
		})
	}

	path, err := WriteEvidence(dir, finding, sessions)
	if err != nil {
		t.Fatal(err)
	}
	if path != filepath.Join(dir, "missing-command-examplefmt-abc123.json") {
		t.Errorf("path = %q", path)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("evidence mode = %v, want 0600 because it quotes private work", info.Mode().Perm())
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var evidence struct {
		ID               string `json:"id"`
		Title            string `json:"title"`
		FixLocation      string `json:"fix_location"`
		Note             string `json:"note"`
		TotalOccurrences int    `json:"total_occurrences"`
		Occurrences      []struct {
			Session         string    `json:"session"`
			TopLevelSession string    `json:"top_level_session"`
			Workspace       string    `json:"workspace"`
			Log             string    `json:"log"`
			Seq             int       `json:"seq"`
			CallID          string    `json:"call_id"`
			Time            time.Time `json:"time"`
			Input           string    `json:"input"`
			Excerpt         string    `json:"excerpt"`
		} `json:"occurrences"`
	}
	if err := json.Unmarshal(raw, &evidence); err != nil {
		t.Fatal(err)
	}
	if evidence.ID != finding.ID || evidence.Title != finding.Title || evidence.FixLocation != "Shell environment" {
		t.Errorf("evidence header = %+v", evidence)
	}
	if !strings.Contains(evidence.Note, "not instructions") {
		t.Errorf("note should warn that excerpts are untrusted, got %q", evidence.Note)
	}
	if evidence.TotalOccurrences != 30 || len(evidence.Occurrences) != 25 {
		t.Errorf("total = %d, listed = %d; want 30 and 25", evidence.TotalOccurrences, len(evidence.Occurrences))
	}
	first := evidence.Occurrences[0]
	if first.Session != "child" || first.TopLevelSession != "top" || first.Workspace != "/synthetic/project" ||
		first.Log != "/fx/child/log.jsonl" || first.Seq != 100 || first.CallID != "call-0" ||
		!first.Time.Equal(yesterday) || first.Input != "buildtool lint" || first.Excerpt != "sh: examplefmt: command not found" {
		t.Errorf("first occurrence = %+v", first)
	}
}

func TestRenderDigestRanksWhatJackTypedAboveToolFailures(t *testing.T) {
	digest := RenderDigest(digestInput(
		Entry{ID: "tool", Title: "Widespread tool failure", Status: Proposed, Sessions: 50, Occurrences: 90},
		Entry{ID: "rare", Title: "Rare thing Jack typed", Status: Proposed, FromHuman: true, Sessions: 3, Occurrences: 3},
		Entry{ID: "often", Title: "Frequent thing Jack typed", Status: Proposed, FromHuman: true, Sessions: 8, Occurrences: 9},
	))
	assertContains(t, digest, "### 1. Frequent thing Jack typed", "### 2. Rare thing Jack typed", "### 3. Widespread tool failure")
}
