package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"time"
)

// Status is the decision Jack has made about a finding.
type Status string

const (
	Proposed Status = "proposed"
	Accepted Status = "accepted"
	Rejected Status = "rejected"
	Fixed    Status = "fixed"
)

// Entry is what the ledger remembers about one finding between scans.
type Entry struct {
	ID            string    `json:"id"`
	Detector      string    `json:"detector"`
	Key           string    `json:"key"`
	Title         string    `json:"title"`
	FixLocation   string    `json:"fix_location"`
	FromHuman     bool      `json:"from_human"`
	Status        Status    `json:"status"`
	StatusChanged time.Time `json:"status_changed,omitzero"`
	FirstSeen     time.Time `json:"first_seen"`
	LastSeen      time.Time `json:"last_seen"`
	// The counts below describe the most recent scan.
	Sessions    int `json:"sessions"`
	Occurrences int `json:"occurrences"`
	Recent      int `json:"recent"`
	Previous    int `json:"previous"`
	// SinceStatusChange shows whether a finding marked fixed has come back.
	SinceStatusChange int `json:"since_status_change"`
}

// Ledger keeps decisions so that rejected findings stay hidden and fixed
// findings can be checked against later scans.
type Ledger struct {
	Findings map[string]*Entry `json:"findings"`
}

// LoadLedger reads the ledger at path. A missing file is an empty ledger.
func LoadLedger(path string) (*Ledger, error) {
	ledger := &Ledger{Findings: map[string]*Entry{}}
	raw, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return ledger, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(raw, ledger); err != nil {
		return nil, fmt.Errorf("reading ledger %s: %w", path, err)
	}
	if ledger.Findings == nil {
		ledger.Findings = map[string]*Entry{}
	}
	return ledger, nil
}

func (ledger *Ledger) Save(path string) error {
	raw, err := json.MarshalIndent(ledger, "", "  ")
	if err != nil {
		return err
	}
	return writePrivateFile(path, append(raw, '\n'))
}

// Update records the counts from a scan. A finding enters the ledger once it has
// affected minSessions sessions; a finding already in the ledger is always counted.
func (ledger *Ledger) Update(findings []Finding, minSessions int) {
	if ledger.Findings == nil {
		ledger.Findings = map[string]*Entry{}
	}
	observed := map[string]bool{}
	for _, finding := range findings {
		entry := ledger.Findings[finding.ID]
		if entry == nil {
			if finding.Sessions < minSessions {
				continue
			}
			entry = &Entry{ID: finding.ID, Status: Proposed, FirstSeen: finding.FirstSeen}
			ledger.Findings[finding.ID] = entry
		}
		observed[finding.ID] = true
		entry.Detector, entry.Key = finding.Detector, finding.Key
		entry.Title, entry.FixLocation, entry.FromHuman = finding.Title, finding.FixLocation, finding.FromHuman
		if entry.FirstSeen.IsZero() || finding.FirstSeen.Before(entry.FirstSeen) {
			entry.FirstSeen = finding.FirstSeen
		}
		entry.LastSeen = finding.LastSeen
		entry.Sessions, entry.Occurrences = finding.Sessions, len(finding.Signals)
		entry.Recent, entry.Previous = finding.Recent, finding.Previous
		entry.SinceStatusChange = 0
		for _, signal := range finding.Signals {
			if signal.Time.After(entry.StatusChanged) {
				entry.SinceStatusChange++
			}
		}
	}
	for id, entry := range ledger.Findings {
		if !observed[id] {
			entry.Sessions, entry.Occurrences, entry.Recent, entry.Previous, entry.SinceStatusChange = 0, 0, 0, 0, 0
		}
	}
}

func (ledger *Ledger) SetStatus(id, status string, now time.Time) error {
	switch Status(status) {
	case Proposed, Accepted, Rejected, Fixed:
	default:
		return fmt.Errorf("unknown status %q: use one of proposed, accepted, rejected, fixed", status)
	}
	entry := ledger.Findings[id]
	if entry == nil {
		return fmt.Errorf("no finding with ID %q", id)
	}
	entry.Status = Status(status)
	entry.StatusChanged = now
	return nil
}

// writePrivateFile replaces path in one step. State files quote private work
// transcripts, so only the owner may read them.
func writePrivateFile(path string, content []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), filepath.Base(path)+".*")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	if _, err := temporary.Write(content); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporary.Name(), path)
}
