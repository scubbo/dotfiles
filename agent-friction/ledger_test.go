package main

// All logs, commands, tool names and messages in these tests are synthetic.
// None is copied from a real session.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func findingWith(id string, sessions int, times ...time.Time) Finding {
	finding := Finding{ID: id, Detector: "missing-command", Key: id, Title: "Title of " + id, FixLocation: "Somewhere", Sessions: sessions, FromHuman: true}
	for _, at := range times {
		finding.Signals = append(finding.Signals, Signal{Time: at})
		if !at.Before(scanNow.Add(-week)) {
			finding.Recent++
		} else {
			finding.Previous++
		}
	}
	if len(times) > 0 {
		finding.LastSeen, finding.FirstSeen = times[0], times[len(times)-1]
	}
	return finding
}

var (
	yesterday  = scanNow.Add(-24 * time.Hour)
	tenDaysAgo = scanNow.Add(-10 * 24 * time.Hour)
)

func TestLedgerUpdateProposesFindingsThatAreWidespreadEnough(t *testing.T) {
	ledger := &Ledger{}
	ledger.Update([]Finding{
		findingWith("widespread", 3, yesterday, tenDaysAgo),
		findingWith("one-off", 2, yesterday),
	}, 3)

	if _, found := ledger.Findings["one-off"]; found {
		t.Error("a finding below the session threshold entered the ledger")
	}
	got := ledger.Findings["widespread"]
	if got == nil {
		t.Fatal("widespread finding is missing")
	}
	if got.Status != Proposed || got.Title != "Title of widespread" || got.FixLocation != "Somewhere" ||
		got.Detector != "missing-command" || got.Key != "widespread" || !got.FromHuman {
		t.Errorf("entry = %+v", got)
	}
	if got.Sessions != 3 || got.Occurrences != 2 || got.Recent != 1 || got.Previous != 1 {
		t.Errorf("counts = %+v", got)
	}
	if !got.FirstSeen.Equal(tenDaysAgo) || !got.LastSeen.Equal(yesterday) {
		t.Errorf("first seen %v, last seen %v", got.FirstSeen, got.LastSeen)
	}
}

func TestLedgerUpdateKeepsDecisionsAndHistory(t *testing.T) {
	longAgo := scanNow.Add(-60 * 24 * time.Hour)
	ledger := &Ledger{Findings: map[string]*Entry{
		"known": {ID: "known", Status: Accepted, FirstSeen: longAgo, LastSeen: tenDaysAgo},
	}}
	ledger.Update([]Finding{findingWith("known", 1, yesterday)}, 3)

	got := ledger.Findings["known"]
	if got.Status != Accepted {
		t.Errorf("status = %q, want accepted", got.Status)
	}
	if got.Occurrences != 1 || got.Sessions != 1 {
		t.Errorf("a known finding below the threshold should still be counted: %+v", got)
	}
	if !got.FirstSeen.Equal(longAgo) || !got.LastSeen.Equal(yesterday) {
		t.Errorf("first seen %v, last seen %v", got.FirstSeen, got.LastSeen)
	}
}

func TestLedgerUpdateZeroesFindingsThatStoppedHappening(t *testing.T) {
	ledger := &Ledger{Findings: map[string]*Entry{
		"gone": {ID: "gone", Status: Fixed, LastSeen: tenDaysAgo, Sessions: 4, Occurrences: 9, Recent: 5, Previous: 4, SinceStatusChange: 2},
	}}
	ledger.Update(nil, 3)

	got := ledger.Findings["gone"]
	if got.Sessions != 0 || got.Occurrences != 0 || got.Recent != 0 || got.Previous != 0 || got.SinceStatusChange != 0 {
		t.Errorf("counts = %+v", got)
	}
	if !got.LastSeen.Equal(tenDaysAgo) || got.Status != Fixed {
		t.Errorf("entry = %+v", got)
	}
}

func TestLedgerUpdateCountsOccurrencesSinceTheStatusChanged(t *testing.T) {
	ledger := &Ledger{Findings: map[string]*Entry{
		"fixed": {ID: "fixed", Status: Fixed, StatusChanged: scanNow.Add(-3 * 24 * time.Hour)},
	}}
	ledger.Update([]Finding{findingWith("fixed", 2, yesterday, tenDaysAgo)}, 3)

	if got := ledger.Findings["fixed"].SinceStatusChange; got != 1 {
		t.Errorf("since status change = %d, want 1", got)
	}
}

func TestLedgerSetStatus(t *testing.T) {
	ledger := &Ledger{Findings: map[string]*Entry{"known": {ID: "known", Status: Proposed}}}

	if err := ledger.SetStatus("known", "accepted", scanNow); err != nil {
		t.Fatal(err)
	}
	if got := ledger.Findings["known"]; got.Status != Accepted || !got.StatusChanged.Equal(scanNow) {
		t.Errorf("entry = %+v", got)
	}
	if err := ledger.SetStatus("known", "maybe", scanNow); err == nil || !strings.Contains(err.Error(), "proposed, accepted, rejected, fixed") {
		t.Errorf("error for an invalid status = %v", err)
	}
	if err := ledger.SetStatus("unknown", "fixed", scanNow); err == nil || !strings.Contains(err.Error(), `"unknown"`) {
		t.Errorf("error for an unknown finding = %v", err)
	}
}

func TestLedgerSurvivesSavingAndLoading(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state", "ledger.json")
	empty, err := LoadLedger(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(empty.Findings) != 0 {
		t.Errorf("a missing ledger file should load as empty, got %+v", empty.Findings)
	}

	empty.Update([]Finding{findingWith("widespread", 3, yesterday)}, 3)
	if err := empty.SetStatus("widespread", "rejected", scanNow); err != nil {
		t.Fatal(err)
	}
	if err := empty.Save(path); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("ledger mode = %v, want 0600 because it describes private work", info.Mode().Perm())
	}

	loaded, err := LoadLedger(path)
	if err != nil {
		t.Fatal(err)
	}
	got := loaded.Findings["widespread"]
	if got == nil || got.Status != Rejected || !got.StatusChanged.Equal(scanNow) || !got.LastSeen.Equal(yesterday) || got.Sessions != 3 {
		t.Errorf("loaded entry = %+v", got)
	}
}

func TestLoadLedgerRefusesAnUnreadableLedger(t *testing.T) {
	path := filepath.Join(t.TempDir(), "ledger.json")
	if err := os.WriteFile(path, []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadLedger(path); err == nil {
		t.Error("expected an error, so that decisions are not silently discarded")
	}
}
