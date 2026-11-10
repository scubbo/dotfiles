package main

import (
	"crypto/sha256"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
)

// Finding is one recurring problem: every signal that shares a detector and key.
type Finding struct {
	ID          string
	Detector    string
	Key         string
	Title       string
	FixLocation string
	FromHuman   bool
	// Signals are ordered from most recent to oldest.
	Signals []Signal
	// Sessions counts distinct top-level sessions, so a burst of subagents counts once.
	Sessions int
	// Recent and Previous count signals in the latest period and the one before it.
	Recent    int
	Previous  int
	FirstSeen time.Time
	LastSeen  time.Time
}

// BuildFindings runs every detector over every session and groups the signals
// into findings, ordered from most to least widespread.
func BuildFindings(detectors []Detector, sessions []Session, now time.Time, period time.Duration) []Finding {
	index := indexSessions(sessions)
	byID := map[string]*Finding{}
	affected := map[string]map[string]bool{}
	for _, detector := range detectors {
		for _, session := range sessions {
			for _, signal := range detector.Detect(session) {
				signal.SessionID = session.ID
				id := findingID(detector.Name, signal.Key)
				finding := byID[id]
				if finding == nil {
					finding = &Finding{
						ID:          id,
						Detector:    detector.Name,
						Key:         signal.Key,
						Title:       detector.Title(signal.Key),
						FixLocation: detector.FixLocation,
						FromHuman:   detector.FromHuman,
					}
					byID[id] = finding
					affected[id] = map[string]bool{}
				}
				finding.Signals = append(finding.Signals, signal)
				affected[id][index.topLevel(session.ID)] = true
			}
		}
	}

	recentStart, previousStart := now.Add(-period), now.Add(-2*period)
	findings := make([]Finding, 0, len(byID))
	for id, finding := range byID {
		sort.SliceStable(finding.Signals, func(i, j int) bool {
			return finding.Signals[i].Time.After(finding.Signals[j].Time)
		})
		finding.Sessions = len(affected[id])
		finding.LastSeen = finding.Signals[0].Time
		finding.FirstSeen = finding.Signals[len(finding.Signals)-1].Time
		for _, signal := range finding.Signals {
			switch {
			case !signal.Time.Before(recentStart):
				finding.Recent++
			case !signal.Time.Before(previousStart):
				finding.Previous++
			}
		}
		findings = append(findings, *finding)
	}
	sort.Slice(findings, func(i, j int) bool {
		a, b := findings[i], findings[j]
		if a.Sessions != b.Sessions {
			return a.Sessions > b.Sessions
		}
		if len(a.Signals) != len(b.Signals) {
			return len(a.Signals) > len(b.Signals)
		}
		return a.ID < b.ID
	})
	return findings
}

type sessionIndex map[string]Session

func indexSessions(sessions []Session) sessionIndex {
	index := sessionIndex{}
	for _, session := range sessions {
		index[session.ID] = session
	}
	return index
}

// topLevel follows parent links to the session a human started. A parent outside
// the scan still identifies the group, so its ID is returned.
func (index sessionIndex) topLevel(id string) string {
	for range len(index) + 1 {
		parent := index[id].ParentID
		if parent == "" {
			return id
		}
		id = parent
	}
	return id
}

var nonSlugCharacters = regexp.MustCompile(`[^a-z0-9]+`)

// findingID names a finding in a form that is readable, safe as a file name, and
// distinct for keys that differ only in punctuation.
func findingID(detector, key string) string {
	if key == "" {
		return detector
	}
	slug := strings.Trim(nonSlugCharacters.ReplaceAllString(strings.ToLower(key), "-"), "-")
	if len(slug) > 40 {
		slug = strings.Trim(slug[:40], "-")
	}
	digest := sha256.Sum256([]byte(key))
	if slug == "" {
		return fmt.Sprintf("%s-%x", detector, digest[:3])
	}
	return fmt.Sprintf("%s-%s-%x", detector, slug, digest[:3])
}
