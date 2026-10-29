#!/usr/bin/env python3
"""Opt-in macOS smoke test. Creates isolated raw-input readers, never sends to existing sessions."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

PROJECT = Path(__file__).resolve().parent.parent


def jxa(source, argument):
    result = subprocess.run(
        ["/usr/bin/osascript", "-l", "JavaScript", "-e", source, json.dumps(argument)],
        capture_output=True, text=True, timeout=35,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


SETUP = r"""
function run(argv) {
    var r = JSON.parse(argv[0]), a = Application(r.bundleID), w, t1, t2, s1, s2;
    if (r.kind === "ghostty") {
        var c1 = a.newSurfaceConfiguration({from:{command:r.first, waitAfterCommand:false}});
        w = a.newWindow({withConfiguration:c1});
        t1 = w.selectedTab(); s1 = t1.focusedTerminal();
        var id1 = s1.id(), tab1 = t1.id();
        var c2 = a.newSurfaceConfiguration({from:{command:r.second, waitAfterCommand:false}});
        t2 = a.newTab({in:w, withConfiguration:c2}); s2 = t2.focusedTerminal();
        a.selectTab(t2);
        w = a.frontWindow();
        return JSON.stringify({windowID:String(w.id()), terminalID:String(s2.id()),
            previousTerminalID:String(id1), previousTabID:String(tab1)});
    } else if (r.kind === "iterm2") {
        w = a.createWindowWithDefaultProfile({command:r.first});
        s1 = w.currentSession();
        var id1 = s1.id();
        t2 = w.createTabWithDefaultProfile({command:r.second}); s2 = t2.currentSession();
        s2.select();
        return JSON.stringify({windowID:String(w.id()), terminalID:String(s2.id()),
            previousTerminalID:String(id1), previousTabID:""});
    } else {
        function windowForTTY(value) {
            var windows=a.windows();
            for(var i=0;i<windows.length;i++) {
                var tabs=windows[i].tabs();
                for(var j=0;j<tabs.length;j++) if(String(tabs[j].tty())===value) return windows[i];
            }
            throw new Error("Created Terminal TTY not found");
        }
        t1 = a.doScript(r.first);
        var id1 = t1.tty(), wid1 = String(windowForTTY(id1).id());
        t2 = a.doScript(r.second);
        var id2=t2.tty(), secondWindow=windowForTTY(id2), wid2=String(secondWindow.id());
        secondWindow.index=1; a.activate();
        return JSON.stringify({windowID:wid2, terminalID:String(id2),
            previousTerminalID:String(id1), previousTabID:"", previousWindowID:wid1});
    }
}
"""

READER = r"""
import os, pathlib, select, sys, termios, tty
output = pathlib.Path(sys.argv[1])
stop = pathlib.Path(sys.argv[2])
previous = termios.tcgetattr(0)
try:
    tty.setraw(0)
    os.write(1, b"\x1b[?2004h")
    output.write_bytes(b"")
    output.with_suffix(".ready").touch()
    with output.open("ab", buffering=0) as stream:
        while not stop.exists():
            if select.select([0], [], [], 0.1)[0]:
                chunk = os.read(0, 65536)
                if not chunk: break
                stream.write(chunk)
finally:
    os.write(1, b"\x1b[?2004l")
    termios.tcsetattr(0, termios.TCSANOW, previous)
"""


def main():
    with tempfile.TemporaryDirectory(prefix="whisper-paste-terminal-test-") as name:
        root = Path(name)
        reader, stop = root / "reader.py", root / "stop"
        reader.write_text(READER)
        fixtures = []
        try:
            for kind, bundle, app_path in [
                ("ghostty", "com.mitchellh.ghostty", "/Applications/Ghostty.app"),
                ("iterm2", "com.googlecode.iterm2", "/Applications/iTerm.app"),
                ("terminal", "com.apple.Terminal", "/System/Applications/Utilities/Terminal.app"),
            ]:
                if not Path(app_path).exists():
                    continue
                first, second = root / (kind + "-a.bin"), root / (kind + "-b.bin")
                # Generated paths contain no user-controlled shell syntax.
                import shlex
                command = lambda output: shlex.join(["/usr/bin/python3", str(reader), str(output), str(stop)])
                entry = jxa(SETUP, {"kind": kind, "bundleID": bundle,
                                    "first": command(first), "second": command(second)})
                entry.update(bundleID=bundle, output=str(second), previousOutput=str(first), kind=kind)
                fixtures.append(entry)
            if not fixtures:
                raise RuntimeError("Install Ghostty or iTerm2 before running this test")
            deadline = time.monotonic() + 15
            while not all(Path(f[key]).with_suffix(".ready").exists()
                          for f in fixtures for key in ["output", "previousOutput"]):
                if time.monotonic() > deadline:
                    raise RuntimeError("Isolated input readers did not become ready")
                time.sleep(0.1)
            fixture = root / "fixtures.json"
            fixture.write_text(json.dumps(fixtures))
            environment = dict(os.environ, WHISPER_PASTE_TERMINAL_FIXTURE=str(fixture))
            subprocess.run(["swift", "test", "--filter", "TerminalIntegrationTests"],
                           cwd=PROJECT, env=environment, check=True, timeout=150)
        finally:
            stop.touch()
            time.sleep(1)
            for entry in fixtures:
                # Only windows created above are eligible for cleanup.
                try:
                    jxa(r"""
                    function run(argv) {
                        var r=JSON.parse(argv[0]), a=Application(r.bundleID);
                        if (!a.running()) return "true";
                        var windows=a.windows();
                        for (var i=windows.length-1;i>=0;i--) if (
                            String(windows[i].id())===r.windowID || String(windows[i].id())===r.previousWindowID) {
                            if(r.kind==="ghostty") a.closeWindow(windows[i]);
                            else if(r.kind==="terminal") windows[i].close({saving:"no"});
                            else windows[i].close();
                        }
                        return "true";
                    }
                    """, entry)
                except Exception:
                    pass


if __name__ == "__main__":
    main()
