package main

// All logs, commands, tool names and messages in these tests are synthetic.
// None is copied from a real session.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var scanStart = time.UnixMilli(1_794_000_000_000)

func ms(offset int64) int64 { return scanStart.UnixMilli() + offset }

// fxLine builds one fx log record. Tool previews and arguments are stored by fx
// as JSON-encoded strings, so nested values are encoded twice.
func fxLine(t *testing.T, fields map[string]any) string {
	t.Helper()
	encoded, err := json.Marshal(fields)
	if err != nil {
		t.Fatal(err)
	}
	return string(encoded)
}

func jsonString(t *testing.T, value any) string {
	t.Helper()
	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return string(encoded)
}

func writeFxLog(t *testing.T, root, id string, lines ...string) string {
	t.Helper()
	dir := filepath.Join(root, id)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "log.jsonl")
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func loadOne(t *testing.T, lines ...string) Session {
	t.Helper()
	root := t.TempDir()
	writeFxLog(t, root, "sess1", lines...)
	sessions, err := LoadFxSessions(root, scanStart)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 1 {
		t.Fatalf("got %d sessions, want 1", len(sessions))
	}
	return sessions[0]
}

func TestLoadFxSessionsReadsSessionIdentity(t *testing.T) {
	root := t.TempDir()
	rootLog := writeFxLog(t, root, "-top",
		fxLine(t, map[string]any{"seq": 1, "ts": ms(0), "kind": "session_created", "id": "-top", "workspace": "/synthetic/project", "role": "root", "host": "app"}))
	writeFxLog(t, root, "child",
		fxLine(t, map[string]any{"seq": 1, "ts": ms(0), "kind": "session_created", "id": "child", "workspace": "/synthetic/project", "role": "child", "host": "child", "parent": "-top"}))

	sessions, err := LoadFxSessions(root, scanStart)
	if err != nil {
		t.Fatal(err)
	}
	byID := map[string]Session{}
	for _, s := range sessions {
		byID[s.ID] = s
	}
	top, child := byID["-top"], byID["child"]
	if top.Workspace != "/synthetic/project" || top.ParentID != "" || top.LogPath != rootLog {
		t.Errorf("top-level session = %+v", top)
	}
	if child.ParentID != "-top" {
		t.Errorf("child parent = %q, want -top", child.ParentID)
	}
}

func TestLoadFxSessionsReadsUserMessagesAndSteering(t *testing.T) {
	s := loadOne(t,
		fxLine(t, map[string]any{"seq": 5, "ts": ms(10), "kind": "item", "turn": 1, "type": "user", "data": map[string]any{"text": "paint the widget"}}),
		fxLine(t, map[string]any{"seq": 9, "ts": ms(20), "kind": "item", "turn": 1, "type": "steering", "data": map[string]any{"text": "what do you mean?"}}),
		fxLine(t, map[string]any{"seq": 10, "ts": ms(30), "kind": "item", "turn": 1, "type": "assistant", "data": map[string]any{"text": "ignored"}}),
	)
	if len(s.Events) != 2 {
		t.Fatalf("got %d events, want 2: %+v", len(s.Events), s.Events)
	}
	first, second := s.Events[0], s.Events[1]
	if first.Kind != UserMessage || first.Text != "paint the widget" || first.Seq != 5 || !first.Time.Equal(time.UnixMilli(ms(10))) {
		t.Errorf("user event = %+v", first)
	}
	if second.Kind != UserMessage || second.Text != "what do you mean?" {
		t.Errorf("steering event = %+v", second)
	}
}

func TestLoadFxSessionsReadsShellCallAndOutput(t *testing.T) {
	envelope := jsonString(t, map[string]any{"session_id": nil, "exit_code": 127, "error": nil, "output_delta": "abc\nbuildtool:1: command not found: _missing_helper\n"})
	s := loadOne(t,
		fxLine(t, map[string]any{"seq": 2, "ts": ms(1), "kind": "item", "type": "tool_call", "data": map[string]any{
			"call_id": "c1", "tool_name": "shell", "arguments_json": jsonString(t, map[string]any{"action": "run", "command": "buildtool test"})}}),
		fxLine(t, map[string]any{"seq": 3, "ts": ms(2), "kind": "item", "type": "tool_result", "data": map[string]any{
			"call_id": "c1", "tool_name": "shell", "status": "failure", "preview": envelope}}),
	)
	call, result := s.Events[0], s.Events[1]
	if call.Kind != ToolCall || call.Tool != "shell" || call.CallID != "c1" || call.Input != "buildtool test" {
		t.Errorf("call = %+v", call)
	}
	if result.Kind != ToolResult || !result.Failed || result.CallID != "c1" || result.ErrorCode != "" {
		t.Errorf("result = %+v", result)
	}
	if result.Output != "abc\nbuildtool:1: command not found: _missing_helper\n" {
		t.Errorf("output = %q", result.Output)
	}
}

func TestLoadFxSessionsKeepsRawArgumentsForOtherTools(t *testing.T) {
	arguments := jsonString(t, map[string]any{"path": "example.json"})
	s := loadOne(t,
		fxLine(t, map[string]any{"seq": 2, "ts": ms(1), "kind": "item", "type": "tool_call", "data": map[string]any{
			"call_id": "c1", "tool_name": "read_file", "arguments_json": arguments}}),
		fxLine(t, map[string]any{"seq": 3, "ts": ms(2), "kind": "item", "type": "tool_result", "data": map[string]any{
			"call_id": "c1", "tool_name": "read_file", "status": "success", "preview": "1\t{}"}}),
	)
	if s.Events[0].Input != arguments {
		t.Errorf("input = %q, want %q", s.Events[0].Input, arguments)
	}
	if s.Events[1].Failed || s.Events[1].Output != "1\t{}" {
		t.Errorf("result = %+v", s.Events[1])
	}
}

func TestLoadFxSessionsReadsErrorEnvelopes(t *testing.T) {
	held := jsonString(t, map[string]any{"error": map[string]any{"type": "tool_review_held", "reason": "review_caution", "advice": "Risky download."}})
	invalid := jsonString(t, map[string]any{"error": map[string]any{"code": "invalid_shell_request", "problems": []string{"yield_time_ms must be between 0 and 30000 for run."}}})
	s := loadOne(t,
		fxLine(t, map[string]any{"seq": 3, "ts": ms(2), "kind": "item", "type": "tool_result", "data": map[string]any{
			"call_id": "c1", "tool_name": "shell", "status": "failure", "preview": held}}),
		fxLine(t, map[string]any{"seq": 4, "ts": ms(3), "kind": "item", "type": "tool_result", "data": map[string]any{
			"call_id": "c2", "tool_name": "shell", "status": "failure", "preview": invalid}}),
	)
	if s.Events[0].ErrorCode != "tool_review_held" || !strings.Contains(s.Events[0].Output, "Risky download.") {
		t.Errorf("held result = %+v", s.Events[0])
	}
	if s.Events[1].ErrorCode != "invalid_shell_request" {
		t.Errorf("invalid result = %+v", s.Events[1])
	}
}

func TestLoadFxSessionsDecodesLineBreaksInATruncatedPreview(t *testing.T) {
	truncated := `{"session_id":null,"output_delta":"ok\nzsh: command not found: exampletool\n and then the preview was cut`
	s := loadOne(t,
		fxLine(t, map[string]any{"seq": 3, "ts": ms(2), "kind": "item", "type": "tool_result", "data": map[string]any{
			"call_id": "c1", "tool_name": "shell", "status": "failure", "preview": truncated}}),
	)
	want := "{\"session_id\":null,\"output_delta\":\"ok\nzsh: command not found: exampletool\n and then the preview was cut"
	if s.Events[0].Output != want {
		t.Errorf("output = %q, want %q", s.Events[0].Output, want)
	}
}

func TestLoadFxSessionsReadsAbortedTurns(t *testing.T) {
	s := loadOne(t,
		fxLine(t, map[string]any{"seq": 7, "ts": ms(5), "kind": "turn_interrupted", "turn": 2, "reason": "failed"}),
	)
	if len(s.Events) != 1 || s.Events[0].Kind != TurnAborted || s.Events[0].Reason != "failed" || s.Events[0].Seq != 7 {
		t.Errorf("events = %+v", s.Events)
	}
}

func TestLoadFxSessionsDropsEventsBeforeTheScanWindow(t *testing.T) {
	s := loadOne(t,
		fxLine(t, map[string]any{"seq": 1, "ts": ms(-5000), "kind": "session_created", "id": "sess1", "workspace": "/w", "role": "root"}),
		fxLine(t, map[string]any{"seq": 2, "ts": ms(-1), "kind": "item", "type": "user", "data": map[string]any{"text": "old"}}),
		fxLine(t, map[string]any{"seq": 3, "ts": ms(1), "kind": "item", "type": "user", "data": map[string]any{"text": "recent"}}),
	)
	if s.Workspace != "/w" {
		t.Errorf("workspace = %q, want /w", s.Workspace)
	}
	if len(s.Events) != 1 || s.Events[0].Text != "recent" {
		t.Errorf("events = %+v", s.Events)
	}
}

func TestLoadFxSessionsSkipsLogsUntouchedSinceTheScanWindow(t *testing.T) {
	root := t.TempDir()
	stale := writeFxLog(t, root, "stale",
		fxLine(t, map[string]any{"seq": 2, "ts": ms(1), "kind": "item", "type": "user", "data": map[string]any{"text": "hi"}}))
	before := scanStart.Add(-time.Hour)
	if err := os.Chtimes(stale, before, before); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "no-log"), 0o700); err != nil {
		t.Fatal(err)
	}

	sessions, err := LoadFxSessions(root, scanStart)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 0 {
		t.Errorf("got %d sessions, want 0", len(sessions))
	}
}

func TestLoadFxSessionsIgnoresAPartiallyWrittenLastLine(t *testing.T) {
	s := loadOne(t,
		fxLine(t, map[string]any{"seq": 2, "ts": ms(1), "kind": "item", "type": "user", "data": map[string]any{"text": "hi"}}),
		`{"seq":3,"ts":`,
	)
	if len(s.Events) != 1 {
		t.Errorf("got %d events, want 1", len(s.Events))
	}
}

func TestLoadFxSessionsFailsWhenTheSessionDirectoryIsMissing(t *testing.T) {
	if _, err := LoadFxSessions(filepath.Join(t.TempDir(), "absent"), scanStart); err == nil {
		t.Error("expected an error for a missing sessions directory")
	}
}
