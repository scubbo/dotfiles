// agent-friction scans coding-agent session logs for recurring friction and
// writes a digest of findings for Jack to accept, reject, or mark fixed.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

const usage = `usage: agent-friction <command>

  scan [--fx-sessions DIR] [--state DIR] [--period-days N] [--min-sessions N] [--top N]
      Scan agent sessions and write a digest of recurring friction.

  set [--state DIR] <finding-id> <proposed|accepted|rejected|fixed>
      Record a decision about a finding.`

func main() {
	if err := run(os.Args[1:], os.Stdout, time.Now()); err != nil {
		fmt.Fprintln(os.Stderr, "agent-friction:", err)
		os.Exit(1)
	}
}

func run(args []string, out io.Writer, now time.Time) error {
	if len(args) == 0 {
		return errors.New(usage)
	}
	switch args[0] {
	case "scan":
		return runScan(args[1:], out, now)
	case "set":
		return runSet(args[1:], out, now)
	}
	return errors.New(usage)
}

func newFlagSet(name string) (*flag.FlagSet, *string) {
	flags := flag.NewFlagSet(name, flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	state := flags.String("state", defaultStateDir(), "directory for the ledger, digests and evidence")
	return flags, state
}

func runScan(args []string, out io.Writer, now time.Time) error {
	flags, state := newFlagSet("scan")
	fxSessions := flags.String("fx-sessions", defaultFxSessionsDir(), "directory of fx session logs")
	periodDays := flags.Int("period-days", 7, "length in days of the recent period; the scan covers two periods")
	minSessions := flags.Int("min-sessions", 3, "sessions a finding must affect before it is reported")
	top := flags.Int("top", 10, "undecided findings to list in the digest")
	if err := flags.Parse(args); err != nil {
		return err
	}

	period := time.Duration(*periodDays) * 24 * time.Hour
	sessions, err := LoadFxSessions(*fxSessions, now.Add(-2*period))
	if err != nil {
		return fmt.Errorf("reading fx sessions: %w", err)
	}
	findings := BuildFindings(Detectors, sessions, now, period)

	ledgerPath := filepath.Join(*state, "ledger.json")
	ledger, err := LoadLedger(ledgerPath)
	if err != nil {
		return err
	}
	ledger.Update(findings, *minSessions)

	evidenceDir := filepath.Join(*state, "evidence")
	index := indexSessions(sessions)
	examples := map[string]string{}
	for _, finding := range findings {
		entry := ledger.Findings[finding.ID]
		if entry == nil || entry.Status == Rejected {
			continue
		}
		if _, err := WriteEvidence(evidenceDir, finding, index); err != nil {
			return err
		}
		latest := finding.Signals[0]
		examples[finding.ID] = latest.Excerpt
		if latest.Excerpt == "" {
			examples[finding.ID] = latest.Input
		}
	}

	input := DigestInput{
		Now:         now,
		Period:      period,
		Sessions:    len(sessions),
		Examples:    examples,
		EvidenceDir: evidenceDir,
		Top:         *top,
	}
	for _, session := range sessions {
		if session.ParentID == "" {
			input.TopLevelSessions++
		}
	}
	undecided := 0
	for _, entry := range ledger.Findings {
		input.Entries = append(input.Entries, *entry)
		if entry.Status == Proposed {
			undecided++
		}
	}

	digestPath := filepath.Join(*state, "digests", now.Format(dateFormat)+".md")
	if err := writePrivateFile(digestPath, []byte(RenderDigest(input))); err != nil {
		return err
	}
	if err := ledger.Save(ledgerPath); err != nil {
		return err
	}

	verb := "need"
	if undecided == 1 {
		verb = "needs"
	}
	fmt.Fprintf(out, "%s %s a decision.\nDigest: %s\n", plural(undecided, "finding"), verb, digestPath)
	return nil
}

func runSet(args []string, out io.Writer, now time.Time) error {
	flags, state := newFlagSet("set")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 2 {
		return errors.New("usage: agent-friction set [--state DIR] <finding-id> <proposed|accepted|rejected|fixed>")
	}
	id, status := flags.Arg(0), flags.Arg(1)

	ledgerPath := filepath.Join(*state, "ledger.json")
	ledger, err := LoadLedger(ledgerPath)
	if err != nil {
		return err
	}
	if err := ledger.SetStatus(id, status, now); err != nil {
		return err
	}
	if err := ledger.Save(ledgerPath); err != nil {
		return err
	}
	fmt.Fprintf(out, "Marked %s as %s.\n", id, status)
	return nil
}

func defaultFxSessionsDir() string {
	fxHome := os.Getenv("FX_HOME")
	if fxHome == "" {
		fxHome = filepath.Join(homeDir(), ".fx")
	}
	return filepath.Join(fxHome, "sessions", "v2")
}

func defaultStateDir() string {
	stateHome := os.Getenv("XDG_STATE_HOME")
	if stateHome == "" {
		stateHome = filepath.Join(homeDir(), ".local", "state")
	}
	return filepath.Join(stateHome, "agent-friction")
}

func homeDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "."
	}
	return home
}
