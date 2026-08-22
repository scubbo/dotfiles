/**
 * Colony Monitor Plugin for OpenCode
 *
 * Spawns a background watcher process that monitors the agent-community
 * message bus (messages.jsonl) for urgent messages. When a message with
 * urgency >= 3 arrives for the coordinator, it injects an alert into the
 * coordinator's context using `herdr agent prompt`.
 *
 * Installation:
 *   cp plugin/colony-monitor.ts ~/.config/opencode/plugin/
 *
 * Configuration (environment variables):
 *   AGENT_COMMUNITY: Community name (e.g., "robogoat-colony")
 *   COLONY_COMMUNITY_PATH: Direct path to community directory (overrides AGENT_COMMUNITY)
 *   COLONY_COORDINATOR_PANE: Pane ID for coordinator (auto-detected from HERDR_PANE)
 *   COLONY_MIN_URGENCY: Minimum urgency to alert (default: 3)
 *   COLONY_ROLE: "coordinator" or "worker" (default: auto-detect)
 */
import type { Plugin } from "@opencode-ai/plugin";
import { spawn, ChildProcess } from "node:child_process";
import { watch, readFileSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

// Message type from agent-community
interface ColonyMessage {
  id: string;
  ts: string;
  author: string;
  body: string;
  context?: string;
  type?: string;    // heartbeat, progress, question, completed, pr_ready, blocker, failed, steering
  urgency?: number; // 1-5
  to?: string;      // recipient (empty = broadcast)
}

// Watcher state
interface WatcherState {
  communityPath: string;
  messagesPath: string;
  lastOffset: number;
  coordinatorPane: string;
  minUrgency: number;
  coordinatorName: string;
  isCoordinator: boolean;
}

/**
 * Parse JSONL file from a given byte offset, returning new messages
 */
function readNewMessages(path: string, fromOffset: number): { messages: ColonyMessage[]; newOffset: number } {
  if (!existsSync(path)) {
    return { messages: [], newOffset: 0 };
  }

  const stat = statSync(path);
  if (stat.size <= fromOffset) {
    return { messages: [], newOffset: fromOffset };
  }

  const content = readFileSync(path, "utf-8");
  const lines = content.slice(fromOffset).split("\n").filter(line => line.trim());

  const messages: ColonyMessage[] = [];
  for (const line of lines) {
    try {
      const msg = JSON.parse(line) as ColonyMessage;
      messages.push(msg);
    } catch {
      // Skip malformed lines
    }
  }

  return { messages, newOffset: stat.size };
}

/**
 * Check if a message should trigger an alert for the coordinator
 */
function shouldAlert(msg: ColonyMessage, state: WatcherState): boolean {
  // Must meet minimum urgency threshold
  const urgency = msg.urgency ?? 0;
  if (urgency < state.minUrgency) {
    return false;
  }

  // Must be addressed to coordinator (or broadcast)
  if (msg.to && msg.to !== state.coordinatorName && msg.to !== "coordinator") {
    return false;
  }

  // Don't alert on our own messages
  if (msg.author === state.coordinatorName) {
    return false;
  }

  // Don't alert on steering messages (those are FROM coordinator)
  if (msg.type === "steering") {
    return false;
  }

  return true;
}

/**
 * Format an alert message for injection
 */
function formatAlert(msg: ColonyMessage): string {
  const urgencyEmoji = msg.urgency && msg.urgency >= 5 ? "🚨" : msg.urgency && msg.urgency >= 4 ? "⚠️" : "📬";
  const typeLabel = msg.type ? `[${msg.type.toUpperCase()}]` : "";

  return `${urgencyEmoji} COLONY ALERT ${typeLabel} from ${msg.author}: ${msg.body}`;
}

/**
 * Auto-detect pane ID by querying herdr for the focused pane running opencode
 */
async function detectPaneId(): Promise<string | null> {
  return new Promise((resolve) => {
    const proc = spawn("herdr", ["pane", "list"], {
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    proc.on("close", (code) => {
      if (code !== 0) {
        resolve(null);
        return;
      }

      try {
        const result = JSON.parse(stdout);
        const panes = result?.result?.panes || [];

        // Find the focused pane running opencode
        const focusedOpencode = panes.find((p: any) =>
          p.focused && p.agent === "opencode"
        );

        if (focusedOpencode) {
          resolve(focusedOpencode.pane_id);
          return;
        }

        // Fallback: find any working opencode pane
        const workingOpencode = panes.find((p: any) =>
          p.agent === "opencode" && p.agent_status === "working"
        );

        if (workingOpencode) {
          resolve(workingOpencode.pane_id);
          return;
        }

        resolve(null);
      } catch {
        resolve(null);
      }
    });

    proc.on("error", () => {
      resolve(null);
    });

    // Timeout after 3 seconds
    setTimeout(() => {
      proc.kill();
      resolve(null);
    }, 3000);
  });
}

/**
 * Inject alert into coordinator's context via herdr agent prompt
 */
async function injectAlert(alert: string, paneId: string): Promise<boolean> {
  return new Promise((resolve) => {
    const proc = spawn("herdr", ["agent", "prompt", paneId, alert], {
      stdio: ["ignore", "pipe", "pipe"],
    });

    proc.on("close", (code) => {
      resolve(code === 0);
    });

    proc.on("error", () => {
      resolve(false);
    });

    // Timeout after 5 seconds
    setTimeout(() => {
      proc.kill();
      resolve(false);
    }, 5000);
  });
}

/**
 * Main watcher loop - polls for new messages and injects alerts
 */
async function runWatcher(state: WatcherState, log: (msg: string) => void): Promise<void> {
  log(`[colony-monitor] Starting watcher for ${state.messagesPath}`);
  log(`[colony-monitor] Coordinator: ${state.coordinatorName}, Pane: ${state.coordinatorPane}, Min urgency: ${state.minUrgency}`);

  // Initial read to get current offset (don't alert on existing messages)
  const initial = readNewMessages(state.messagesPath, 0);
  state.lastOffset = initial.newOffset;
  log(`[colony-monitor] Starting at offset ${state.lastOffset} (${initial.messages.length} existing messages)`);

  // Watch for file changes
  const watcher = watch(state.communityPath, { persistent: true }, async (eventType, filename) => {
    if (filename !== "messages.jsonl") {
      return;
    }

    const { messages, newOffset } = readNewMessages(state.messagesPath, state.lastOffset);
    state.lastOffset = newOffset;

    for (const msg of messages) {
      if (shouldAlert(msg, state)) {
        const alert = formatAlert(msg);
        log(`[colony-monitor] Alert: ${alert}`);

        const success = await injectAlert(alert, state.coordinatorPane);
        if (!success) {
          log(`[colony-monitor] Failed to inject alert (herdr agent prompt failed)`);
        }
      }
    }
  });

  // Also poll every 2 seconds as backup (fs.watch can miss events)
  const pollInterval = setInterval(async () => {
    const { messages, newOffset } = readNewMessages(state.messagesPath, state.lastOffset);
    state.lastOffset = newOffset;

    for (const msg of messages) {
      if (shouldAlert(msg, state)) {
        const alert = formatAlert(msg);
        log(`[colony-monitor] Alert (poll): ${alert}`);

        const success = await injectAlert(alert, state.coordinatorPane);
        if (!success) {
          log(`[colony-monitor] Failed to inject alert (herdr agent prompt failed)`);
        }
      }
    }
  }, 2000);

  // Keep watcher alive
  process.on("SIGTERM", () => {
    log(`[colony-monitor] Received SIGTERM, shutting down`);
    watcher.close();
    clearInterval(pollInterval);
    process.exit(0);
  });

  process.on("SIGINT", () => {
    log(`[colony-monitor] Received SIGINT, shutting down`);
    watcher.close();
    clearInterval(pollInterval);
    process.exit(0);
  });
}

/**
 * Colony Monitor Plugin
 *
 * Only activates for coordinators. Spawns a background watcher that monitors
 * the message bus and injects alerts for urgent messages.
 */
export const ColonyMonitorPlugin: Plugin = async (ctx) => {
  const { client } = ctx;

  const log = async (message: string) => {
    try {
      await client.app.log({
        body: {
          service: "colony-monitor",
          level: "info",
          message,
        },
      });
    } catch {
      // Fallback to console if SDK logging fails
      console.log(message);
    }
  };

  // Check if we're a coordinator
  const role = process.env.COLONY_ROLE || "auto";
  let paneId = process.env.HERDR_PANE || process.env.COLONY_COORDINATOR_PANE;

  // Auto-detect pane ID if not set
  if (!paneId) {
    paneId = await detectPaneId();
    if (paneId) {
      await log(`[colony-monitor] Auto-detected pane ID: ${paneId}`);
    }
  }

  // Auto-detect: coordinators have pane ID and no COLONY_WORKER marker
  const isCoordinator = role === "coordinator" ||
    (role === "auto" && paneId && !process.env.COLONY_WORKER);

  if (!isCoordinator) {
    await log("[colony-monitor] Not a coordinator, skipping monitor activation");
    return {};
  }

  if (!paneId) {
    await log("[colony-monitor] No pane ID available (HERDR_PANE or COLONY_COORDINATOR_PANE), cannot inject alerts");
    return {};
  }

  // Resolve community path
  // Priority: COLONY_COMMUNITY_PATH > AGENT_COMMUNITY (name lookup) > skip
  let communityPath = process.env.COLONY_COMMUNITY_PATH;

  if (!communityPath && process.env.AGENT_COMMUNITY) {
    // Look up by name in standard location
    communityPath = join(homedir(), ".local", "share", "agent-community", process.env.AGENT_COMMUNITY);
  }

  if (!communityPath) {
    await log("[colony-monitor] No community configured (set AGENT_COMMUNITY or COLONY_COMMUNITY_PATH)");
    return {};
  }

  const messagesPath = join(communityPath, "messages.jsonl");

  // Get coordinator name (for filtering self-messages)
  const coordinatorName = process.env.COLONY_COORDINATOR_NAME ||
    process.env.OPENCODE_AGENT ||
    "coordinator";

  const minUrgency = parseInt(process.env.COLONY_MIN_URGENCY || "3", 10);

  const state: WatcherState = {
    communityPath,
    messagesPath,
    lastOffset: 0,
    coordinatorPane: paneId,
    minUrgency,
    coordinatorName,
    isCoordinator: true,
  };

  // Function to start the watcher (called immediately or after community is created)
  const startMonitoring = () => {
    // All logging goes to the log file, not console
    runWatcher(state, () => {});
  };

  if (!existsSync(communityPath)) {
    await log(`[colony-monitor] Community directory not found yet: ${communityPath}, polling...`);

    // Don't block - poll in background until community is created
    setImmediate(() => {
      const maxWaitMs = 5 * 60 * 1000;
      const startTime = Date.now();

      const checkInterval = setInterval(() => {
        if (existsSync(communityPath)) {
          clearInterval(checkInterval);
          startMonitoring();
        } else if (Date.now() - startTime > maxWaitMs) {
          clearInterval(checkInterval);
        }
      }, 2000);
    });
  } else {
    await log(`[colony-monitor] Initializing for coordinator ${coordinatorName}`);
    setImmediate(startMonitoring);
  }

  return {
    // Hook into session.idle to double-check for missed messages
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        const { messages, newOffset } = readNewMessages(state.messagesPath, state.lastOffset);
        state.lastOffset = newOffset;

        for (const msg of messages) {
          if (shouldAlert(msg, state)) {
            const alert = formatAlert(msg);
            await log(`[colony-monitor] Idle check alert: ${alert}`);
            await injectAlert(alert, state.coordinatorPane);
          }
        }
      }
    },
  };
};

export default ColonyMonitorPlugin;
