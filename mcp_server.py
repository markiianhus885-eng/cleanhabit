"""
CleanHabit MCP Server
Allows Claude Code to interact with a CleanHabit household.

Setup in Claude Code (~/.claude/claude_desktop_config.json or .mcp.json):
{
  "mcpServers": {
    "cleanhabit": {
      "command": "python",
      "args": ["mcp_server.py"],
      "env": {
        "CLEANHABIT_URL": "https://cleanhabit.myroapp.org",
        "CLEANHABIT_USERNAME": "your_username",
        "CLEANHABIT_PASSWORD": "your_password"
      }
    }
  }
}
"""

import os
import sys
import json
import urllib.request
import urllib.parse
import urllib.error
import http.cookiejar

CLEANHABIT_URL = os.environ.get("CLEANHABIT_URL", "https://cleanhabit.myroapp.org")
USERNAME = os.environ.get("CLEANHABIT_USERNAME", "")
PASSWORD = os.environ.get("CLEANHABIT_PASSWORD", "")

# Cookie jar for session
_cookie_jar = http.cookiejar.CookieJar()
_opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(_cookie_jar))
_logged_in = False


def _request(method, path, body=None):
    url = CLEANHABIT_URL.rstrip("/") + path
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    try:
        with _opener.open(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())


def _ensure_logged_in():
    global _logged_in
    if _logged_in:
        return True
    result = _request("POST", "/api/auth/login", {"username": USERNAME, "password": PASSWORD})
    if result.get("ok") or result.get("user"):
        _logged_in = True
        return True
    return False


# ── MCP protocol (stdio JSON-RPC) ─────────────────────────────

TOOLS = [
    {
        "name": "get_data",
        "description": "Get all household data: members, rooms, tasks, leaderboard, goals",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "get_tasks",
        "description": "Get all tasks for the household, optionally filtered by room",
        "inputSchema": {
            "type": "object",
            "properties": {
                "room_name": {"type": "string", "description": "Optional room name to filter tasks"}
            }
        }
    },
    {
        "name": "add_task",
        "description": "Add a new cleaning task to a room",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Task name"},
                "room_name": {"type": "string", "description": "Room name to assign task to"},
                "difficulty": {"type": "string", "enum": ["easy", "medium", "hard"], "description": "Task difficulty"},
                "freq": {"type": "string", "enum": ["daily", "every2", "weekly", "biweekly", "monthly"], "description": "How often the task repeats"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "complete_task",
        "description": "Mark a task as completed by a member",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_name": {"type": "string", "description": "Name of the task to complete"},
                "member_name": {"type": "string", "description": "Name of the member completing the task"}
            },
            "required": ["task_name"]
        }
    },
    {
        "name": "get_leaderboard",
        "description": "Get the family leaderboard with points and rankings",
        "inputSchema": {
            "type": "object",
            "properties": {
                "period": {"type": "string", "enum": ["week", "month", "all"], "description": "Time period"}
            }
        }
    },
    {
        "name": "add_room",
        "description": "Add a new room to the household",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Room name"},
                "emoji": {"type": "string", "description": "Room emoji icon"}
            },
            "required": ["name"]
        }
    },
    {
        "name": "get_members",
        "description": "Get all family members with their points, coins and streaks",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
]


def handle_tool(name, args):
    if not _ensure_logged_in():
        return f"Login failed. Check CLEANHABIT_USERNAME and CLEANHABIT_PASSWORD env vars."

    if name == "get_data":
        data = _request("GET", "/api/data")
        members = [f"{m['emoji']} {m['name']} ({m['points']} pts, 🪙{m['coins']})" for m in data.get("members", [])]
        rooms = [f"{r['emoji']} {r['name']} - {r['cleanliness']}% clean" for r in data.get("rooms", [])]
        tasks = data.get("tasks", [])
        return f"Members: {', '.join(members)}\nRooms: {', '.join(rooms)}\nTotal tasks: {len(tasks)}"

    elif name == "get_tasks":
        data = _request("GET", "/api/data")
        tasks = data.get("tasks", [])
        rooms = {r["id"]: r["name"] for r in data.get("rooms", [])}
        room_filter = args.get("room_name", "").lower()
        result = []
        for t in tasks:
            room_name = rooms.get(t.get("room_id"), "?")
            if room_filter and room_filter not in room_name.lower():
                continue
            result.append(f"• {t['name']} [{room_name}] - {t.get('diff','medium')} - {t.get('freq','weekly')}")
        return "\n".join(result) if result else "No tasks found."

    elif name == "add_task":
        data = _request("GET", "/api/data")
        rooms = data.get("rooms", [])
        room_name = args.get("room_name", "")
        room_id = None
        if room_name:
            for r in rooms:
                if room_name.lower() in r["name"].lower():
                    room_id = r["id"]
                    break
        payload = {
            "name": args["name"],
            "room_id": room_id or (rooms[0]["id"] if rooms else None),
            "diff": args.get("difficulty", "medium"),
            "freq": args.get("freq", "weekly"),
            "approval_needed": False,
            "one_time": False
        }
        result = _request("POST", "/api/tasks", payload)
        return f"Task '{args['name']}' added!" if result.get("ok") else f"Error: {result.get('error')}"

    elif name == "complete_task":
        data = _request("GET", "/api/data")
        tasks = data.get("tasks", [])
        members = data.get("members", [])
        task_name = args.get("task_name", "").lower()
        member_name = args.get("member_name", "").lower()
        task = next((t for t in tasks if task_name in t["name"].lower()), None)
        if not task:
            return f"Task '{args['task_name']}' not found."
        member = next((m for m in members if member_name in m["name"].lower()), members[0] if members else None)
        if not member:
            return "No members found."
        result = _request("POST", f"/api/tasks/{task['id']}/complete", {"member_id": member["id"]})
        return f"Task '{task['name']}' completed by {member['name']}! +{result.get('pts', '?')} pts" if result.get("ok") else f"Error: {result.get('error')}"

    elif name == "get_leaderboard":
        period = args.get("period", "week")
        lb = _request("GET", f"/api/leaderboard?period={period}")
        if not isinstance(lb, list):
            return "Could not fetch leaderboard."
        medals = ["🥇", "🥈", "🥉"]
        lines = []
        for i, m in enumerate(lb):
            medal = medals[i] if i < 3 else f"{i+1}."
            lines.append(f"{medal} {m['emoji']} {m['name']} - {m.get('period_pts', 0)} pts this {period} | total: {m['points']} pts | 🪙{m['coins']}")
        return "\n".join(lines) if lines else "No data."

    elif name == "add_room":
        payload = {"name": args["name"], "emoji": args.get("emoji", "🏠")}
        result = _request("POST", "/api/rooms", payload)
        return f"Room '{args['name']}' added!" if result.get("ok") else f"Error: {result.get('error')}"

    elif name == "get_members":
        data = _request("GET", "/api/data")
        lines = []
        for m in data.get("members", []):
            lines.append(f"{m['emoji']} {m['name']} - {m['points']} pts | 🪙{m['coins']} coins | 🔥{m['streak']} streak")
        return "\n".join(lines) if lines else "No members."

    return f"Unknown tool: {name}"


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_id = msg.get("id")
        method = msg.get("method")

        if method == "initialize":
            resp = {
                "jsonrpc": "2.0", "id": msg_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "cleanhabit", "version": "1.0.0"}
                }
            }
        elif method == "tools/list":
            resp = {"jsonrpc": "2.0", "id": msg_id, "result": {"tools": TOOLS}}
        elif method == "tools/call":
            tool_name = msg.get("params", {}).get("name")
            tool_args = msg.get("params", {}).get("arguments", {})
            content = handle_tool(tool_name, tool_args)
            resp = {
                "jsonrpc": "2.0", "id": msg_id,
                "result": {"content": [{"type": "text", "text": content}]}
            }
        elif method == "notifications/initialized":
            continue
        else:
            resp = {
                "jsonrpc": "2.0", "id": msg_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"}
            }

        print(json.dumps(resp), flush=True)


if __name__ == "__main__":
    main()
