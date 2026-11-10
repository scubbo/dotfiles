package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type fxRecord struct {
	Seq       int             `json:"seq"`
	TS        int64           `json:"ts"`
	Kind      string          `json:"kind"`
	Type      string          `json:"type"`
	Parent    string          `json:"parent"`
	Workspace string          `json:"workspace"`
	Reason    string          `json:"reason"`
	Data      json.RawMessage `json:"data"`
}

type fxItem struct {
	Text          string `json:"text"`
	CallID        string `json:"call_id"`
	ToolName      string `json:"tool_name"`
	ArgumentsJSON string `json:"arguments_json"`
	Status        string `json:"status"`
	Preview       string `json:"preview"`
}

// fxResultEnvelope is the JSON object fx stores as the preview of a shell result
// and of any call that a tool refused or rejected.
type fxResultEnvelope struct {
	OutputDelta *string `json:"output_delta"`
	Error       *struct {
		Type string `json:"type"`
		Code string `json:"code"`
	} `json:"error"`
}

// LoadFxSessions reads every fx session under root that changed at or after since,
// keeping only the events from that time onwards.
func LoadFxSessions(root string, since time.Time) ([]Session, error) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}
	var sessions []Session
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		logPath := filepath.Join(root, entry.Name(), "log.jsonl")
		info, err := os.Stat(logPath)
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, err
		}
		if info.ModTime().Before(since) {
			continue
		}
		session, err := loadFxSession(logPath, entry.Name(), since)
		if err != nil {
			return nil, err
		}
		sessions = append(sessions, session)
	}
	return sessions, nil
}

func loadFxSession(logPath, id string, since time.Time) (Session, error) {
	file, err := os.Open(logPath)
	if err != nil {
		return Session{}, err
	}
	defer file.Close()

	session := Session{ID: id, LogPath: logPath}
	// Records can be several megabytes long, so lines are read without a length limit.
	reader := bufio.NewReaderSize(file, 1<<20)
	for {
		line, err := reader.ReadBytes('\n')
		if len(line) > 0 {
			addFxRecord(&session, line, since)
		}
		if errors.Is(err, io.EOF) {
			return session, nil
		}
		if err != nil {
			return Session{}, err
		}
	}
}

// addFxRecord skips lines that do not parse: fx appends to the log while a session
// is running, so the last line of a live or crashed session can be incomplete.
func addFxRecord(session *Session, line []byte, since time.Time) {
	var record fxRecord
	if err := json.Unmarshal(line, &record); err != nil {
		return
	}
	if record.Kind == "session_created" {
		session.ParentID = record.Parent
		session.Workspace = record.Workspace
		return
	}
	at := time.UnixMilli(record.TS)
	if at.Before(since) {
		return
	}
	event := Event{Seq: record.Seq, Time: at}
	switch {
	case record.Kind == "turn_interrupted":
		event.Kind = TurnAborted
		event.Reason = record.Reason
	case record.Kind == "item" && isFxEventType(record.Type):
		var item fxItem
		if err := json.Unmarshal(record.Data, &item); err != nil {
			return
		}
		fillFxItemEvent(&event, record.Type, item)
	default:
		return
	}
	session.Events = append(session.Events, event)
}

func isFxEventType(itemType string) bool {
	switch itemType {
	case "user", "steering", "tool_call", "tool_result":
		return true
	}
	return false
}

func fillFxItemEvent(event *Event, itemType string, item fxItem) {
	switch itemType {
	case "user", "steering":
		event.Kind = UserMessage
		event.Text = item.Text
	case "tool_call":
		event.Kind = ToolCall
		event.CallID = item.CallID
		event.Tool = item.ToolName
		event.Input = fxCallInput(item)
	case "tool_result":
		event.Kind = ToolResult
		event.CallID = item.CallID
		event.Tool = item.ToolName
		event.Failed = item.Status == "failure"
		event.Output, event.ErrorCode = fxResultOutput(item.Preview)
	}
}

func fxCallInput(item fxItem) string {
	if item.ToolName != "shell" {
		return item.ArgumentsJSON
	}
	var arguments struct {
		Command string `json:"command"`
	}
	if err := json.Unmarshal([]byte(item.ArgumentsJSON), &arguments); err != nil || arguments.Command == "" {
		return item.ArgumentsJSON
	}
	return arguments.Command
}

// fxResultOutput returns the text a tool produced and, when the tool refused or
// rejected the call, the code that says why. fx caps previews, so an envelope
// can be cut short; its escaped line breaks are then decoded so that detectors
// still see the output line by line.
func fxResultOutput(preview string) (output, errorCode string) {
	if !strings.HasPrefix(preview, "{") {
		return preview, ""
	}
	var envelope fxResultEnvelope
	if err := json.Unmarshal([]byte(preview), &envelope); err != nil {
		return strings.ReplaceAll(preview, `\n`, "\n"), ""
	}
	if envelope.Error != nil {
		errorCode = envelope.Error.Type
		if errorCode == "" {
			errorCode = envelope.Error.Code
		}
		return preview, errorCode
	}
	if envelope.OutputDelta != nil {
		return *envelope.OutputDelta, ""
	}
	return preview, ""
}
