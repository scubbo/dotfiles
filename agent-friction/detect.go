package main

import (
	"encoding/json"
	"path"
	"regexp"
	"strings"
	"time"
)

// Signal is one observed moment of friction. Signals with the same detector and
// Key describe the same underlying problem.
type Signal struct {
	Key       string
	SessionID string
	Seq       int
	Time      time.Time
	CallID    string
	// Input is what triggered the friction: a shell command, tool arguments, or a human message.
	Input   string
	Excerpt string
}

// Detector finds one kind of friction within a single session.
type Detector struct {
	Name string
	// FixLocation says where a fix for this kind of friction usually belongs.
	FixLocation string
	// FromHuman marks friction that Jack reported in his own words. It costs him
	// more than a failure the agent recovered from, so the digest lists it first.
	FromHuman bool
	Title     func(key string) string
	Detect    func(Session) []Signal
}

var Detectors = []Detector{
	{
		Name:        "missing-command",
		FixLocation: "Shell environment (dotfiles): install the command, or fix how shell startup files define it",
		Title:       func(key string) string { return "Command `" + key + "` is not found in agent shells" },
		Detect:      detectMissingCommand,
	},
	{
		Name:        "zsh-path-clobber",
		FixLocation: "Agent instructions (AGENTS.md)",
		Title: func(string) string {
			return "Agents assign the zsh variable `path`, which empties the command search path"
		},
		Detect: detectPathClobber,
	},
	{
		Name:        "turn-failed",
		FixLocation: "Upstream: fx or the model provider",
		Title:       func(key string) string { return "Turns stop with `" + key + "` before the agent finishes" },
		Detect:      detectTurnFailed,
	},
	{
		Name:        "review-held",
		FixLocation: "fx permission rules, or instructions that steer agents to an allowed approach",
		Title:       reviewHeldTitle,
		Detect:      detectReviewHeld,
	},
	{
		Name:        "tool-error",
		FixLocation: "Depends on the tool: agent instructions, the project, or upstream fx",
		Title: func(key string) string {
			tool, message, _ := strings.Cut(key, ": ")
			return "`" + tool + "` fails: " + message
		},
		Detect: detectToolError,
	},
	phraseDetector("user-confusion",
		"Agent instructions (AGENTS.md): how agents explain their work",
		"Jack did not understand what the agent said",
		`\bi (?:still |really |just )?(?:don['’]?t|do not|didn['’]?t|did not) (?:really |quite |fully )?(?:understand|follow)\b`,
		`\b(?:doesn['’]?t|does not|don['’]?t|do not|didn['’]?t|did not) make (?:any |much )?sense\b`,
		`\bmakes no sense\b`,
		`\bwhat do you mean\b`,
		`\bwhat does (?:that|this|it) mean\b`,
		`\bi['’]?m (?:still |so |a bit |a little |very )?(?:confused|lost)\b`,
		`\b(?:that|this|it)(?:['’]s| is) confusing\b`,
		`\byou(?:['’]ve| have)? lost me\b`,
		`\bexplain\b[^.\n]{0,40}\bsimple-english\b`,
		`\bin (?:plain|simple|simpler) (?:english|terms)\b`,
		`\bwait,? what\b`,
		`\bhuh\?`,
	),
	phraseDetector("user-correction",
		"Agent instructions, or a skill for the task that was corrected",
		"Jack corrected the agent",
		`^\s*(?:no\s*[,.!-]|nope\b|wrong\b)`,
		`\b(?:that['’]?s|that is|this is) not what i\b`,
		`\bnot what i (?:asked|meant|said|wanted)\b`,
		`\bi (?:already |just )?(?:said|told you)\b`,
		`\b(?:as|like) i said\b`,
		`\bi didn['’]?t (?:ask|say|mean|want)\b`,
		`\byou (?:forgot|missed|skipped|ignored)\b`,
		`\byou (?:were|are) supposed to\b`,
		`\byou should(?:n['’]?t| not) have\b`,
		`\bwhy did you\b`,
	),
	phraseDetector("user-frustration",
		"Unknown: read the evidence to find the cause",
		"Jack was frustrated",
		`\b(?:wtf|ffs|ugh+|argh+)\b`,
		`\bfucking\b`,
		`\bwhat the (?:fuck|hell)\b`,
		`\bfor (?:fuck|god)['’]?s sake\b`,
		`\bgoddamn(?:it)?\b`,
	),
}

const quoteLimit = 400

var (
	// zsh prints "zsh: command not found: NAME"; sh and bash print "sh: NAME: command not found".
	// Only whole lines match, because agents also print old errors while reading logs,
	// and a quoted error is not a new failure.
	commandNotFound = regexp.MustCompile(`(?m)^\S+: command not found: ([\w.+/-]+)\s*$|^\S*sh: (?:line \d+: )?([\w.+/-]+): command not found\s*$`)
	// zsh ties the array `path` to PATH, so assigning it replaces the command search path.
	pathAssignment = regexp.MustCompile(`(?m)(?:^|[;&|({])\s*(?:(?:local|typeset|export|declare)\s+)?path=|\bfor\s+path\s+in\b|\bread\s+(?:-r\s+)?path\b`)
	// shellPreamble matches setup that comes before the program a command line runs:
	// directory changes, shell options, sourced files and variable assignments.
	shellPreamble = regexp.MustCompile(`^\s*(?:(?:cd|set|export|source|\.)\s+[^;&\n]*(?:&&|;|\n)|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)`)
	// quotedSpan matches text inside quotation marks, where a phrase is mentioned rather than meant.
	quotedSpan = regexp.MustCompile(`"[^"\n]*"|“[^”\n]*”`)
	digits     = regexp.MustCompile(`\d+`)
)

func callInputs(session Session) map[string]string {
	inputs := map[string]string{}
	for _, event := range session.Events {
		if event.Kind == ToolCall {
			inputs[event.CallID] = event.Input
		}
	}
	return inputs
}

func shellResults(session Session) []Event {
	var results []Event
	for _, event := range session.Events {
		if event.Kind == ToolResult && event.Tool == "shell" {
			results = append(results, event)
		}
	}
	return results
}

func signalAt(event Event, key, input, excerpt string) Signal {
	return Signal{
		Key:     key,
		Seq:     event.Seq,
		Time:    event.Time,
		CallID:  event.CallID,
		Input:   truncate(input, quoteLimit),
		Excerpt: truncate(excerpt, quoteLimit),
	}
}

func detectMissingCommand(session Session) []Signal {
	inputs := callInputs(session)
	var signals []Signal
	for _, result := range shellResults(session) {
		input := inputs[result.CallID]
		// A missing command after `path` was assigned is a symptom reported by zsh-path-clobber.
		if pathAssignment.MatchString(input) {
			continue
		}
		reported := map[string]bool{}
		for _, match := range commandNotFound.FindAllStringSubmatchIndex(result.Output, -1) {
			command := submatch(result.Output, match, 1) + submatch(result.Output, match, 2)
			if reported[command] {
				continue
			}
			reported[command] = true
			signals = append(signals, signalAt(result, command, input, surrounding(result.Output, match[0], match[1])))
		}
	}
	return signals
}

func detectPathClobber(session Session) []Signal {
	inputs := callInputs(session)
	var signals []Signal
	for _, result := range shellResults(session) {
		input := inputs[result.CallID]
		match := commandNotFound.FindStringIndex(result.Output)
		if match == nil || !pathAssignment.MatchString(input) {
			continue
		}
		signals = append(signals, signalAt(result, "path", input, surrounding(result.Output, match[0], match[1])))
	}
	return signals
}

func detectTurnFailed(session Session) []Signal {
	var signals []Signal
	for _, event := range session.Events {
		if event.Kind == TurnAborted && (event.Reason == "failed" || event.Reason == "crash") {
			signals = append(signals, signalAt(event, event.Reason, "", ""))
		}
	}
	return signals
}

const reviewHeldCode = "tool_review_held"

func detectReviewHeld(session Session) []Signal {
	inputs := callInputs(session)
	var signals []Signal
	for _, event := range session.Events {
		if event.Kind != ToolResult || event.ErrorCode != reviewHeldCode {
			continue
		}
		input := inputs[event.CallID]
		key := event.Tool
		if command := firstCommandWord(input); event.Tool == "shell" && command != "" {
			key = "shell " + command
		}
		signals = append(signals, signalAt(event, key, input, reviewAdvice(event.Output)))
	}
	return signals
}

// reviewAdvice returns the reviewer's explanation of why it held a call, or the
// whole result when the explanation cannot be read.
func reviewAdvice(output string) string {
	var held struct {
		Error struct {
			Advice string `json:"advice"`
		} `json:"error"`
	}
	if err := json.Unmarshal([]byte(output), &held); err != nil || held.Error.Advice == "" {
		return output
	}
	return held.Error.Advice
}

func reviewHeldTitle(key string) string {
	if command, isShell := strings.CutPrefix(key, "shell "); isShell {
		return "Safety review holds `" + command + "` shell commands"
	}
	return "Safety review holds `" + key + "` calls"
}

// firstCommandWord names the program a shell command runs, ignoring the setup
// before it. It returns "" when the input is not a command line.
func firstCommandWord(command string) string {
	for {
		rest := shellPreamble.ReplaceAllString(command, "")
		if rest == command {
			break
		}
		command = rest
	}
	command = strings.TrimSpace(command)
	if strings.HasPrefix(command, "{") {
		return ""
	}
	firstLine, _, _ := strings.Cut(command, "\n")
	words := strings.Fields(firstLine)
	if len(words) == 0 {
		return ""
	}
	return path.Base(words[0])
}

func detectToolError(session Session) []Signal {
	inputs := callInputs(session)
	var signals []Signal
	for _, event := range session.Events {
		if event.Kind != ToolResult || !event.Failed || event.ErrorCode == reviewHeldCode {
			continue
		}
		// A shell command that exits non-zero is ordinary work, such as a failing test.
		if event.Tool == "shell" && event.ErrorCode == "" {
			continue
		}
		reason := event.ErrorCode
		if reason == "" {
			reason = errorSummary(event.Output)
		}
		signals = append(signals, signalAt(event, event.Tool+": "+reason, inputs[event.CallID], event.Output))
	}
	return signals
}

// errorSummary reduces an error message to a form that is equal for repeats of
// the same error, by keeping the first line and masking numbers.
func errorSummary(output string) string {
	firstLine, _, _ := strings.Cut(strings.TrimSpace(output), "\n")
	summary := []rune(digits.ReplaceAllString(firstLine, "N"))
	if len(summary) > 100 {
		summary = summary[:100]
	}
	return string(summary)
}

// phraseDetector reports messages in which the human used one of the phrases.
// It reads top-level sessions only: the "user" of a subagent is another agent.
func phraseDetector(name, fixLocation, title string, phrases ...string) Detector {
	pattern := regexp.MustCompile(`(?i)` + strings.Join(phrases, "|"))
	return Detector{
		Name:        name,
		FixLocation: fixLocation,
		FromHuman:   true,
		Title:       func(string) string { return title },
		Detect: func(session Session) []Signal {
			if session.ParentID != "" {
				return nil
			}
			var signals []Signal
			// A message sent again after a failed turn is the same moment of friction.
			sent := map[string]bool{}
			for _, event := range session.Events {
				if event.Kind != UserMessage || sent[event.Text] {
					continue
				}
				sent[event.Text] = true
				own := ownWords(event.Text)
				if match := pattern.FindStringIndex(own); match != nil {
					signals = append(signals, signalAt(event, "", event.Text, strings.TrimSpace(own[match[0]:match[1]])))
				}
			}
			return signals
		},
	}
}

// ownWords drops quoted lines, code blocks and text in quotation marks, which
// repeat or mention words rather than say them.
func ownWords(text string) string {
	var kept []string
	inCodeBlock := false
	for _, line := range strings.Split(text, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "```") {
			inCodeBlock = !inCodeBlock
			continue
		}
		if inCodeBlock || strings.HasPrefix(trimmed, ">") {
			continue
		}
		kept = append(kept, quotedSpan.ReplaceAllString(line, ""))
	}
	return strings.Join(kept, "\n")
}

func submatch(text string, match []int, group int) string {
	start, end := match[2*group], match[2*group+1]
	if start < 0 {
		return ""
	}
	return text[start:end]
}

// surrounding returns the matched text with some context on both sides.
func surrounding(text string, start, end int) string {
	const context = 120
	start = max(start-context, 0)
	end = min(end+context, len(text))
	return strings.TrimSpace(strings.ToValidUTF8(text[start:end], ""))
}

func truncate(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	return string(runes[:limit]) + "…"
}
