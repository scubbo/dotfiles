package main

// All logs, commands, tool names and messages in these tests are synthetic.
// None is copied from a real session.

import (
	"strings"
	"testing"
	"time"
)

func shellCall(callID, command string) Event {
	return Event{Kind: ToolCall, Tool: "shell", CallID: callID, Input: command, Seq: 1, Time: scanStart}
}

func shellResult(callID, output string) Event {
	return Event{Kind: ToolResult, Tool: "shell", CallID: callID, Output: output, Seq: 2, Time: scanStart.Add(time.Second)}
}

func detectorNamed(t *testing.T, name string) Detector {
	t.Helper()
	for _, detector := range Detectors {
		if detector.Name == name {
			return detector
		}
	}
	t.Fatalf("no detector named %q", name)
	return Detector{}
}

func signalKeys(signals []Signal) []string {
	keys := []string{}
	for _, signal := range signals {
		keys = append(keys, signal.Key)
	}
	return keys
}

func assertKeys(t *testing.T, signals []Signal, want ...string) {
	t.Helper()
	got := signalKeys(signals)
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("signal keys = %q, want %q", got, want)
	}
}

func TestMissingCommandReportsTheCommandAndWhereItHappened(t *testing.T) {
	session := Session{ID: "s", Events: []Event{
		shellCall("c1", "buildtool test"),
		shellResult("c1", "abc\nbuildtool:1: command not found: _missing_helper\n"),
	}}
	signals := detectorNamed(t, "missing-command").Detect(session)
	if len(signals) != 1 {
		t.Fatalf("got %d signals, want 1", len(signals))
	}
	got := signals[0]
	if got.Key != "_missing_helper" || got.CallID != "c1" || got.Seq != 2 || got.Input != "buildtool test" ||
		!got.Time.Equal(scanStart.Add(time.Second)) || !strings.Contains(got.Excerpt, "command not found: _missing_helper") {
		t.Errorf("signal = %+v", got)
	}
}

func TestMissingCommandUnderstandsShellErrorFormats(t *testing.T) {
	cases := map[string]string{
		"zsh: command not found: exampletool":                               "exampletool",
		"sh: examplefmt: command not found":                                 "examplefmt",
		"bash: line 1: examplelint: command not found":                      "examplelint",
		"{\"output_delta\":\"ok\nzsh: command not found: exampletool\n cut": "exampletool",
		"buildtool:1: command not found: exampletool\n":                     "exampletool",
		"(eval):3: command not found: exampletool":                          "exampletool",
	}
	for output, want := range cases {
		session := Session{Events: []Event{shellCall("c1", "x"), shellResult("c1", output)}}
		assertKeys(t, detectorNamed(t, "missing-command").Detect(session), want)
	}
}

func TestMissingCommandIgnoresErrorsQuotedInsideOtherOutput(t *testing.T) {
	quoted := []string{
		" 116 buildtool:1: command not found: _missing_helper",
		`{"out":"zsh: command not found: exampletool"}`,
		"=> (eval):1: command not found: sampletool exit=127",
		"the log said sh: examplefmt: command not found yesterday",
	}
	for _, output := range quoted {
		session := Session{Events: []Event{shellCall("c1", "jq -r .out failures.jsonl"), shellResult("c1", output)}}
		assertKeys(t, detectorNamed(t, "missing-command").Detect(session))
	}
}

func TestMissingCommandReportsEachCommandOncePerResult(t *testing.T) {
	session := Session{Events: []Event{
		shellCall("c1", "x"),
		shellResult("c1", "zsh: command not found: a\nzsh: command not found: b\nzsh: command not found: a\n"),
	}}
	assertKeys(t, detectorNamed(t, "missing-command").Detect(session), "a", "b")
}

func TestMissingCommandIgnoresOtherToolsAndPathClobbering(t *testing.T) {
	session := Session{Events: []Event{
		{Kind: ToolResult, Tool: "read_file", CallID: "r1", Output: "echo 'zsh: command not found: foo'"},
		shellCall("c1", `for path in a b; do git show "$path"; done`),
		shellResult("c1", "(eval):1: command not found: git\n"),
	}}
	assertKeys(t, detectorNamed(t, "missing-command").Detect(session))
}

func TestPathClobberNeedsAPathAssignmentAndAMissingCommand(t *testing.T) {
	notFound := "(eval):1: command not found: git\n"
	cases := []struct {
		command string
		output  string
		want    []string
	}{
		{`for path in a b; do git show "$path"; done`, notFound, []string{"path"}},
		{`repo=x; path=/tmp/a; ls $path`, notFound, []string{"path"}},
		{`local path=/tmp/a && git status`, notFound, []string{"path"}},
		{`git ls-files | while read -r path; do stat "$path"; done`, notFound, []string{"path"}},
		{`for path in a b; do print -- "$path"; done`, "a\nb\n", nil},
		{`git log --path=foo`, notFound, nil},
		{`filepath=/tmp/a; git status`, notFound, nil},
	}
	for _, c := range cases {
		session := Session{Events: []Event{shellCall("c1", c.command), shellResult("c1", c.output)}}
		signals := detectorNamed(t, "zsh-path-clobber").Detect(session)
		if strings.Join(signalKeys(signals), "|") != strings.Join(c.want, "|") {
			t.Errorf("%q: keys = %q, want %q", c.command, signalKeys(signals), c.want)
		}
		if len(signals) == 1 && (signals[0].Input != c.command || signals[0].CallID != "c1") {
			t.Errorf("%q: signal = %+v", c.command, signals[0])
		}
	}
}

func TestTurnFailedReportsFailuresAndCrashesOnly(t *testing.T) {
	session := Session{Events: []Event{
		{Kind: TurnAborted, Reason: "failed", Seq: 4, Time: scanStart},
		{Kind: TurnAborted, Reason: "cancel", Seq: 9},
		{Kind: TurnAborted, Reason: "crash", Seq: 12},
	}}
	signals := detectorNamed(t, "turn-failed").Detect(session)
	assertKeys(t, signals, "failed", "crash")
	if signals[0].Seq != 4 || !signals[0].Time.Equal(scanStart) {
		t.Errorf("signal = %+v", signals[0])
	}
}

func TestReviewHeldGroupsShellCallsByCommand(t *testing.T) {
	held := func(callID, tool string) Event {
		return Event{Kind: ToolResult, Tool: tool, CallID: callID, Failed: true, ErrorCode: "tool_review_held", Output: `{"error":{"advice":"Risky."}}`}
	}
	session := Session{Events: []Event{
		shellCall("c1", "cd /repo && curl -sS https://example.com"),
		held("c1", "shell"),
		shellCall("c2", "/opt/tools/bin/buildtool install\nbuildtool test"),
		held("c2", "shell"),
		{Kind: ToolCall, Tool: "edit_file", CallID: "c3", Input: `{"path":"a.txt"}`},
		held("c3", "edit_file"),
		shellCall("c5", "set -euo pipefail\nAPI_TOKEN=abc node fetch.mjs"),
		held("c5", "shell"),
		shellCall("c6", "set -e; cd /repo && python3 - <<'PY'\nprint(1)\nPY"),
		held("c6", "shell"),
		shellCall("c4", "curl https://example.com"),
		{Kind: ToolResult, Tool: "shell", CallID: "c4", Failed: true, Output: "curl: (6) Could not resolve host"},
	}}
	signals := detectorNamed(t, "review-held").Detect(session)
	assertKeys(t, signals, "shell curl", "shell buildtool", "edit_file", "shell node", "shell python3")
	if signals[0].Input != "cd /repo && curl -sS https://example.com" || signals[0].Excerpt != "Risky." {
		t.Errorf("signal = %+v", signals[0])
	}
}

func TestReviewHeldQuotesTheWholeResultWhenItHasNoAdvice(t *testing.T) {
	session := Session{Events: []Event{
		shellCall("c1", "curl https://example.com"),
		{Kind: ToolResult, Tool: "shell", CallID: "c1", Failed: true, ErrorCode: "tool_review_held", Output: `{"error":{"type":"tool_review_held"`},
	}}
	signals := detectorNamed(t, "review-held").Detect(session)
	if len(signals) != 1 || signals[0].Excerpt != `{"error":{"type":"tool_review_held"` {
		t.Errorf("signals = %+v", signals)
	}
}

func TestToolErrorGroupsFailuresByToolAndMessage(t *testing.T) {
	failed := func(tool, errorCode, output string) Event {
		return Event{Kind: ToolResult, Tool: tool, Failed: true, ErrorCode: errorCode, Output: output}
	}
	session := Session{Events: []Event{
		failed("read_file", "", "Path not found: example.json"),
		failed("edit_file", "", "edit_file failed: old_string is not unique (found 12 occurrences), provide more context\nsecond line"),
		failed("shell", "invalid_shell_request", `{"error":{"code":"invalid_shell_request"}}`),
		failed("skill", "", strings.Repeat("x", 150)),
		failed("shell", "", "FAIL src/app.test.ts"),
		failed("shell", "tool_review_held", `{"error":{"type":"tool_review_held"}}`),
		{Kind: ToolResult, Tool: "read_file", Output: "Path not found: mentioned in a file that was read"},
	}}
	assertKeys(t, detectorNamed(t, "tool-error").Detect(session),
		"read_file: Path not found: example.json",
		"edit_file: edit_file failed: old_string is not unique (found N occurrences), provide more context",
		"shell: invalid_shell_request",
		"skill: "+strings.Repeat("x", 100),
	)
}

func userMessages(texts ...string) Session {
	session := Session{ID: "top"}
	for i, text := range texts {
		session.Events = append(session.Events, Event{Kind: UserMessage, Text: text, Seq: i + 1, Time: scanStart})
	}
	return session
}

func assertPhraseDetector(t *testing.T, name string, matching, ignored []string) {
	t.Helper()
	detector := detectorNamed(t, name)
	for _, text := range matching {
		if got := len(detector.Detect(userMessages(text))); got != 1 {
			t.Errorf("%s: %q produced %d signals, want 1", name, text, got)
		}
	}
	for _, text := range ignored {
		if signals := detector.Detect(userMessages(text)); len(signals) != 0 {
			t.Errorf("%s: %q matched %q, want no signal", name, text, signals[0].Excerpt)
		}
	}
}

func TestUserConfusionMatchesStatementsOfNotUnderstanding(t *testing.T) {
	assertPhraseDetector(t, "user-confusion",
		[]string{
			"I don't understand why the teapot needs a lid",
			"i still don't understand how the widget spins",
			"I feel like I don’t understand this recipe",
			"I do not follow",
			"That doesn't make sense",
			"this makes no sense",
			`1. fine 2. What do you mean by "blue widgets"?`,
			"what does that mean?",
			"I'm confused - the teapot _is_ on the shelf",
			"That's confusing - the widget is already painted",
			"you've lost me",
			"Too dense. Please explain it in `simple-english`",
			"say that again in plain English",
			"wait, what?",
		},
		[]string{
			"make the widget smaller and simpler",
			"ask clarifying questions before you paint the widget",
			"does this make sense to you?",
			"isn't that label long and confusing? repaint it",
			"write the recipe using simple-english",
			"try again",
		})
}

func TestUserCorrectionMatchesPushback(t *testing.T) {
	assertPhraseDetector(t, "user-correction",
		[]string{
			"No, paint the other widget",
			"no - keep the blue lid",
			"Nope",
			"That's not what I asked for",
			"I said to leave the teapot alone",
			"As I said, the widgets live on the shelf",
			"I didn't ask for a second lid",
			"you forgot the widgets",
			"Why did you repaint that?",
			"you shouldn't have glued it",
		},
		[]string{
			"no worries, continue",
			"now paint the widgets",
			"nothing else for now",
			"notice the crack in the lid",
			"You should have the paint available now - try again",
		})
}

func TestUserFrustrationMatchesExasperation(t *testing.T) {
	assertPhraseDetector(t, "user-frustration",
		[]string{"ugh, again", "wtf", "for fuck's sake", "this widget is fucking broken"},
		[]string{"go through the list", "that is enough", "the widgets laugh at us", "Fuck yes, paint it"})
}

func TestPhraseDetectorsReportTheMessageAndMatchedPhrase(t *testing.T) {
	long := "What do you mean? " + strings.Repeat("é", 600)
	signals := detectorNamed(t, "user-confusion").Detect(userMessages("fix it", long))
	if len(signals) != 1 {
		t.Fatalf("got %d signals, want 1", len(signals))
	}
	got := signals[0]
	if got.Key != "" || got.Seq != 2 || got.Excerpt != "What do you mean" {
		t.Errorf("signal = %+v", got)
	}
	if !strings.HasPrefix(got.Input, "What do you mean? ééé") || len([]rune(got.Input)) > 401 {
		t.Errorf("input has %d runes: %q", len([]rune(got.Input)), got.Input)
	}
}

func TestPhraseDetectorsIgnoreQuotedTextCodeAndSubagents(t *testing.T) {
	detector := detectorNamed(t, "user-confusion")
	quoted := "> I don't understand the recipe\n\nThat summary is right, go ahead"
	fenced := "Add this label:\n```\nprint('what do you mean')\n```\nthen paint it"
	if signals := detector.Detect(userMessages(quoted, fenced)); len(signals) != 0 {
		t.Errorf("quoted or fenced text matched: %+v", signals)
	}
	delegated := userMessages("I don't understand this widget; inspect it")
	delegated.ParentID = "top"
	if signals := detector.Detect(delegated); len(signals) != 0 {
		t.Errorf("a prompt written by a parent agent matched: %+v", signals)
	}
}

func TestPhraseDetectorsIgnorePhrasesTheHumanOnlyMentions(t *testing.T) {
	detector := detectorNamed(t, "user-confusion")
	mentions := userMessages(
		`Sort replies such as "I don't understand" or "that doesn't make sense" into one pile`,
		"Put “what do you mean” in the same pile",
	)
	if signals := detector.Detect(mentions); len(signals) != 0 {
		t.Errorf("a phrase inside quotation marks matched: %+v", signals)
	}
	used := detector.Detect(userMessages(`What do you mean by "blue widgets"?`))
	if len(used) != 1 || used[0].Excerpt != "What do you mean" {
		t.Errorf("a phrase outside quotation marks should match: %+v", used)
	}
}

func TestPhraseDetectorsCountAResentMessageOnce(t *testing.T) {
	signals := detectorNamed(t, "user-confusion").Detect(userMessages("this makes no sense", "ok", "this makes no sense"))
	if len(signals) != 1 || signals[0].Seq != 1 {
		t.Errorf("signals = %+v, want only the first sending", signals)
	}
}

func TestPhraseDetectorsTrimTheMatchedPhrase(t *testing.T) {
	signals := detectorNamed(t, "user-correction").Detect(userMessages("> glue the lid\n\nNo, paint it first"))
	if len(signals) != 1 || signals[0].Excerpt != "No," {
		t.Errorf("signals = %+v", signals)
	}
}
