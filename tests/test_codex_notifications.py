"""Exercise both notification routes without opening a desktop notification."""

import base64
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import time
import unittest
from unittest.mock import Mock, mock_open, patch

ROOT = Path(__file__).resolve().parents[1]
RELAY = ROOT / "bin/codex-wezterm-notify"
if not RELAY.exists():
    RELAY = ROOT / "scripts/codex-wezterm-notify"

# Codex 0.153.4's hidden request, observed in the local session log. It is a
# separate thread with a valid agent-turn-complete event, not a replay.
TITLE_INSTRUCTIONS = (
    "Generate a concise, single-line task title of at most 36 characters and "
    "under five words where possible. Start with an imperative verb. "
    "Capitalize only the first word unless the user's language, proper nouns, "
    "acronyms, or code terms require otherwise. Preserve ticket references "
    "exactly. Write in the user's language. Do not use quotes, markdown, or "
    "trailing punctuation. Do not answer the request."
)
TITLE_PROMPT = TITLE_INSTRUCTIONS + "\n\nUser prompt:\nFix duplicate notifications"
RENAME_PROMPT = (
    TITLE_INSTRUCTIONS
    + "\nPrioritize the current task and latest substantive user request."
    + "\n\nRecent conversation messages:\n<conversation>\n"
    + '<message role="user">Fix duplicate notifications</message>\n</conversation>'
)


def completion(prompt="Fix duplicate notifications", **overrides):
    payload = {
        "type": "agent-turn-complete",
        "thread-id": "visible-thread",
        "turn-id": "user-turn",
        "cwd": "/work/project",
        "input-messages": [prompt],
        "last-assistant-message": "Fixed and verified.",
    }
    payload.update(overrides)
    return payload


class NotificationTests(unittest.TestCase):
    def setUp(self):
        # Functions retain this dictionary as their globals after run_path.
        self.main = runpy.run_path(str(RELAY))["main"]
        self.namespace = self.main.__globals__
        self.namespace["claim_notification"] = lambda payload: True

    def invoke(self, payload):
        with patch("sys.argv", [str(RELAY), json.dumps(payload)]):
            return self.main()

    def test_title_then_real_completion_notifies_only_once_on_both_routes(self):
        for terminal_available in (True, False):
            with self.subTest(terminal_available=terminal_available):
                with patch.dict(self.namespace), patch("subprocess.Popen") as worker:
                    terminal = Mock(return_value=terminal_available)
                    self.namespace["send_notification_request"] = terminal
                    self.invoke({"type": "task_started"})
                    self.invoke(
                        completion(
                            TITLE_PROMPT,
                            **{
                                "thread-id": "hidden-thread",
                                "turn-id": "hidden-turn",
                                "last-assistant-message": '{"title":"Fix notifications"}',
                            },
                        )
                    )
                    terminal.assert_not_called()
                    worker.assert_not_called()
                    payload = completion()
                    self.invoke(payload)
                    terminal.assert_called_once_with(payload)
                    self.assertEqual(worker.call_count, 0 if terminal_available else 1)

    def test_internal_titles_are_silent_even_without_a_generated_title(self):
        with patch.dict(self.namespace), patch("subprocess.Popen") as worker:
            terminal = Mock()
            self.namespace["send_notification_request"] = terminal
            for prompt in (TITLE_PROMPT, RENAME_PROMPT):
                for reply in (None, "", '{"title":"Fix notifications"}'):
                    self.invoke(completion(prompt, **{"last-assistant-message": reply}))
            terminal.assert_not_called()
            worker.assert_not_called()

    def test_real_title_tasks_and_quoted_internal_prompts_still_notify(self):
        with patch.dict(self.namespace):
            terminal = Mock(return_value=True)
            self.namespace["send_notification_request"] = terminal
            for prompt in (
                "Generate a title for my article as JSON",
                "Explain this internal prompt:\n" + TITLE_PROMPT,
                "Generate a concise, single-line task title of at most 36 characters",
            ):
                self.invoke(
                    completion(
                        prompt,
                        **{
                            "last-assistant-message": '{"title":"An ordinary result"}',
                        },
                    )
                )
            self.assertEqual(terminal.call_count, 3)

    def test_unsupported_events_and_malformed_payloads_are_silent(self):
        with patch.dict(self.namespace), patch("subprocess.Popen") as worker:
            terminal = Mock()
            self.namespace["send_notification_request"] = terminal
            for payload in (
                None,
                [],
                "text",
                1,
                {},
                {"type": "UserPromptSubmit"},
                {"type": "approval-requested"},
            ):
                self.assertEqual(self.invoke(payload), 0)
            with patch("sys.argv", [str(RELAY), "{invalid"]):
                self.assertEqual(self.main(), 0)
            terminal.assert_not_called()
            worker.assert_not_called()

    def test_missing_prompt_metadata_keeps_directory_fallback(self):
        for messages in (None, [], [None, {}]):
            payload = completion(**{"input-messages": messages})
            self.assertFalse(self.namespace["is_internal_title_request"](payload))
            self.assertEqual(self.namespace["task_name"](payload), "project")

    def test_terminal_delivery_preserves_identity_and_clears_request(self):
        for tmux in (False, True):
            with self.subTest(tmux=tmux), patch.dict(self.namespace):
                self.namespace["terminal_path"] = lambda: "/dev/pts/test"
                with patch.dict(
                    os.environ, {"TMUX": "session"} if tmux else {}, clear=True
                ):
                    terminal = mock_open()
                    with patch("builtins.open", terminal):
                        self.assertTrue(
                            self.namespace["send_notification_request"](completion())
                        )
                wire = terminal().write.call_args.args[0]
                if tmux:
                    self.assertEqual(wire.count(b"\x1bPtmux;"), 2)
                prefix = b"SetUserVar=codex_notification_request="
                values = [
                    base64.b64decode(part.split(b"\x07", 1)[0])
                    for part in wire.split(prefix)[1:]
                ]
                self.assertEqual(len(values), 2)
                request = json.loads(values[0])
                self.assertEqual(request["id"], "visible-thread:user-turn")
                self.assertEqual(
                    request["summary"], "Codex finished: Fix duplicate notifications"
                )
                self.assertEqual(request["body"], "Fixed and verified.")
                self.assertEqual(values[1], b"")

    def test_replayed_and_reidentified_completions_are_claimed_only_once(self):
        claim_notification = runpy.run_path(str(RELAY))["claim_notification"]
        namespace = claim_notification.__globals__
        with tempfile.TemporaryDirectory() as directory:
            namespace["DEDUPE_DIR"] = Path(directory) / "notifications"
            payload = completion()
            self.assertTrue(claim_notification(payload))
            self.assertFalse(claim_notification(payload))
            self.assertFalse(
                claim_notification(
                    completion(**{"thread-id": "replayed", "turn-id": "new-id"})
                )
            )
            self.assertTrue(
                claim_notification(
                    completion(
                        "A genuinely new task", **{"turn-id": "next-turn"}
                    )
                )
            )
            later = time.time() + namespace["DEDUPE_WINDOW_SECONDS"]
            with patch("time.time", return_value=later):
                self.assertTrue(
                    claim_notification(
                        completion(
                            **{"thread-id": "later", "turn-id": "later-turn"}
                        )
                    )
                )

    def test_completion_replay_stops_before_both_delivery_routes(self):
        with patch.dict(self.namespace), patch("subprocess.Popen") as worker:
            claim = Mock(side_effect=(True, False))
            terminal = Mock(return_value=False)
            self.namespace["claim_notification"] = claim
            self.namespace["send_notification_request"] = terminal
            payload = completion()
            self.invoke(payload)
            self.invoke(payload)
            self.assertEqual(terminal.call_count, 1)
            self.assertEqual(worker.call_count, 1)

    def test_fallback_timeout_closes_without_resending(self):
        process = Mock()
        process.stdout.readline.return_value = "42\n"
        process.communicate.side_effect = (
            subprocess.TimeoutExpired("notify-send", 3),
            ("", None),
        )
        with patch.dict(self.namespace), patch(
            "shutil.which", return_value="notify-send"
        ), patch("subprocess.Popen", return_value=process) as popen:
            close = Mock()
            self.namespace["close_notification"] = close
            self.namespace["show_host_notification"](
                "Codex finished", "Done", "7", 3000, "wezterm"
            )
        popen.assert_called_once()
        close.assert_called_once_with("42")


if __name__ == "__main__":
    unittest.main()
