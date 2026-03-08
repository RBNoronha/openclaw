"""
a2a_client.py — Cliente Python para o protocolo Agent-to-Agent (A2A)

Uso:
    from a2a_client import A2AClient

    client = A2AClient("https://agente.azurecontainerapps.io")
    card   = client.discover()
    task   = client.send_task("Faça X")
    result = client.wait_for_task(task.task_id, timeout=120)
    print(result.output)
"""

from __future__ import annotations

import time
import urllib.error
import urllib.request
import json
from dataclasses import dataclass, field
from typing import Any


@dataclass
class AgentCard:
    id: str
    name: str
    description: str
    endpoint: str
    skills: list[dict[str, str]] = field(default_factory=list)
    auth: dict[str, str] = field(default_factory=dict)
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass
class A2ATaskHandle:
    task_id: str
    status: str
    base_url: str


@dataclass
class A2ATaskResult:
    task_id: str
    status: str
    output: str | None


class A2AError(Exception):
    pass


class A2AClient:
    def __init__(
        self,
        base_url: str,
        token: str | None = None,
        timeout: int = 30,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout

    def _headers(self) -> dict[str, str]:
        h: dict[str, str] = {"Content-Type": "application/json"}
        if self.token:
            h["Authorization"] = f"Bearer {self.token}"
        return h

    def _get(self, path: str) -> Any:
        url = f"{self.base_url}{path}"
        req = urllib.request.Request(url, headers=self._headers())
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            raise A2AError(f"HTTP {e.code} GET {path}: {body}") from e

    def _post(self, path: str, data: dict[str, Any]) -> Any:
        url = f"{self.base_url}{path}"
        payload = json.dumps(data).encode()
        req = urllib.request.Request(url, data=payload, headers=self._headers(), method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            raise A2AError(f"HTTP {e.code} POST {path}: {body}") from e

    def discover(self) -> AgentCard:
        """Fetch the Agent Card from /.well-known/agent.json."""
        raw = self._get("/.well-known/agent.json")
        return AgentCard(
            id=raw.get("id", ""),
            name=raw.get("name", ""),
            description=raw.get("description", ""),
            endpoint=raw.get("endpoint", f"{self.base_url}/a2a"),
            skills=raw.get("skills", []),
            auth=raw.get("auth", {}),
            raw=raw,
        )

    def send_task(
        self,
        input: str,
        agent_id: str | None = None,
        session_key: str | None = None,
    ) -> A2ATaskHandle:
        """Submit a task to the agent. Returns a handle for status polling."""
        body: dict[str, Any] = {"input": input}
        if agent_id:
            body["agentId"] = agent_id
        if session_key:
            body["sessionKey"] = session_key
        resp = self._post("/a2a", body)
        if not resp.get("ok"):
            raise A2AError(f"Task rejected: {resp.get('error', 'unknown')}")
        return A2ATaskHandle(
            task_id=resp["taskId"],
            status=resp.get("status", "pending"),
            base_url=self.base_url,
        )

    def get_task_status(self, task_id: str) -> A2ATaskResult:
        """Poll task status from /a2a/tasks/:id."""
        resp = self._get(f"/a2a/tasks/{task_id}")
        task = resp.get("task", {})
        return A2ATaskResult(
            task_id=task_id,
            status=task.get("status", "unknown"),
            output=task.get("output"),
        )

    def wait_for_task(
        self,
        task_id: str,
        timeout: int = 300,
        poll_interval: float = 2.0,
    ) -> A2ATaskResult:
        """Poll until task is completed or failed, or timeout is reached."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = self.get_task_status(task_id)
            if result.status in ("completed", "failed"):
                return result
            time.sleep(poll_interval)
        raise A2AError(f"Task {task_id} timed out after {timeout}s")
