package main

import "time"

// EventKind names the parts of an agent conversation that detectors inspect.
type EventKind string

const (
	// UserMessage is text the human typed, either as a prompt or while the agent was working.
	UserMessage EventKind = "user_message"
	ToolCall    EventKind = "tool_call"
	ToolResult  EventKind = "tool_result"
	// TurnAborted marks a turn that stopped before the agent finished it.
	TurnAborted EventKind = "turn_aborted"
)

// Event is one harness-independent record from a conversation log.
// Only the fields relevant to its Kind are set.
type Event struct {
	Kind EventKind
	Seq  int
	Time time.Time

	// Text is the human's message for a UserMessage.
	Text string

	// CallID pairs a ToolCall with its ToolResult.
	CallID string
	Tool   string
	// Input is the shell command for a shell ToolCall and the raw arguments for other tools.
	Input string

	Failed bool
	// ErrorCode is the machine-readable reason a tool refused or rejected a call.
	ErrorCode string
	Output    string

	// Reason says why a TurnAborted turn stopped, for example "failed" or "cancel".
	Reason string
}

// Session is one agent conversation. Subagent sessions name the session that started them.
type Session struct {
	ID        string
	ParentID  string
	Workspace string
	LogPath   string
	Events    []Event
}
