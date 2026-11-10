package main

// All logs, commands, tool names and messages in these tests are synthetic.
// None is copied from a real session.

import (
	"regexp"
	"testing"
	"time"
)

const week = 7 * 24 * time.Hour

var scanNow = scanStart.Add(2 * week)

func missing(command string, at time.Time) []Event {
	return []Event{
		{Kind: ToolCall, Tool: "shell", CallID: "c" + command, Input: command + " --version", Time: at},
		{Kind: ToolResult, Tool: "shell", CallID: "c" + command, Output: "zsh: command not found: " + command, Time: at, Seq: 7},
	}
}

func findingFor(t *testing.T, findings []Finding, key string) Finding {
	t.Helper()
	for _, finding := range findings {
		if finding.Key == key {
			return finding
		}
	}
	t.Fatalf("no finding with key %q in %+v", key, findings)
	return Finding{}
}

func TestBuildFindingsGroupsSignalsAcrossSessions(t *testing.T) {
	lastWeek, thisWeek := scanNow.Add(-10*24*time.Hour), scanNow.Add(-time.Hour)
	sessions := []Session{
		{ID: "a", Events: append(missing("examplefmt", lastWeek), missing("examplefmt", thisWeek)...)},
		{ID: "b", Events: missing("examplefmt", lastWeek)},
	}
	findings := BuildFindings(Detectors, sessions, scanNow, week)
	if len(findings) != 1 {
		t.Fatalf("got %d findings, want 1: %+v", len(findings), findings)
	}
	got := findings[0]
	if got.Detector != "missing-command" || got.Key != "examplefmt" || got.Title != "Command `examplefmt` is not found in agent shells" {
		t.Errorf("finding = %+v", got)
	}
	if got.FixLocation == "" {
		t.Error("finding has no fix location")
	}
	if len(got.Signals) != 3 || got.Sessions != 2 || got.Recent != 1 || got.Previous != 2 {
		t.Errorf("signals=%d sessions=%d recent=%d previous=%d", len(got.Signals), got.Sessions, got.Recent, got.Previous)
	}
	if !got.FirstSeen.Equal(lastWeek) || !got.LastSeen.Equal(thisWeek) {
		t.Errorf("first seen %v, last seen %v", got.FirstSeen, got.LastSeen)
	}
	if !got.Signals[0].Time.Equal(thisWeek) || got.Signals[0].SessionID != "a" {
		t.Errorf("most recent signal should come first: %+v", got.Signals[0])
	}
}

func TestBuildFindingsCountsSubagentsUnderTheirTopLevelSession(t *testing.T) {
	at := scanNow.Add(-time.Hour)
	sessions := []Session{
		{ID: "top"},
		{ID: "child", ParentID: "top", Events: missing("examplefmt", at)},
		{ID: "grandchild", ParentID: "child", Events: missing("examplefmt", at)},
		{ID: "orphan", ParentID: "outside-the-scan", Events: missing("examplefmt", at)},
	}
	got := findingFor(t, BuildFindings(Detectors, sessions, scanNow, week), "examplefmt")
	if got.Sessions != 2 {
		t.Errorf("sessions = %d, want 2 (one top-level session and one orphan)", got.Sessions)
	}
}

func TestBuildFindingsRanksBySessionsThenSignals(t *testing.T) {
	at := scanNow.Add(-time.Hour)
	sessions := []Session{
		{ID: "a", Events: append(append(missing("rare", at), missing("rare", at)...), missing("common", at)...)},
		{ID: "b", Events: append(missing("common", at), missing("middle", at)...)},
		{ID: "c", Events: missing("middle", at)},
		{ID: "d", Events: missing("common", at)},
	}
	findings := BuildFindings(Detectors, sessions, scanNow, week)
	order := []string{}
	for _, finding := range findings {
		order = append(order, finding.Key)
	}
	want := []string{"common", "middle", "rare"}
	for i := range want {
		if i >= len(order) || order[i] != want[i] {
			t.Fatalf("order = %q, want %q", order, want)
		}
	}
}

func TestFindingIDIsStableReadableAndSafeInFileNames(t *testing.T) {
	id := findingID("tool-error", "read_file: Path not found: example.json")
	if id != findingID("tool-error", "read_file: Path not found: example.json") {
		t.Error("the same finding produced two IDs")
	}
	if !regexp.MustCompile(`^tool-error-read-file-path-not-found-example-json-[0-9a-f]{6}$`).MatchString(id) {
		t.Errorf("id = %q", id)
	}
	if findingID("missing-command", "a.b") == findingID("missing-command", "a/b") {
		t.Error("different keys produced the same ID")
	}
	if got := findingID("user-confusion", ""); got != "user-confusion" {
		t.Errorf("id for a detector without keys = %q", got)
	}
	long := findingID("tool-error", "skill: "+string(make([]byte, 300)))
	if len(long) > 80 {
		t.Errorf("id is %d characters long", len(long))
	}
}

func TestBuildFindingsMarksFindingsThatComeFromWhatJackTyped(t *testing.T) {
	at := scanNow.Add(-time.Hour)
	sessions := []Session{{ID: "a", Events: append(missing("examplefmt", at),
		Event{Kind: UserMessage, Text: "I don't understand", Time: at})}}
	findings := BuildFindings(Detectors, sessions, scanNow, week)
	if findingFor(t, findings, "examplefmt").FromHuman {
		t.Error("a missing command is not something Jack typed")
	}
	if !findingFor(t, findings, "").FromHuman {
		t.Error("a statement of confusion is something Jack typed")
	}
}
