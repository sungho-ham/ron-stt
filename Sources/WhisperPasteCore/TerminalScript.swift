import Foundation

enum TerminalScript {
    static let source = #"""
    ObjC.import("Foundation");
    ObjC.import("AppKit");
    function run() {
        var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
        var r = JSON.parse(ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)));
        function fail(code) { throw { bridgeCode: code }; }
        function find(items, key, value) {
            for (var i = 0; i < items.length; i++) if (String(items[i][key]()) === value) return items[i];
            fail("missing");
        }
        function title(value) { return String(value || "").slice(0, 160); }
        function checkForeground() {
            if (r.requireFrontmost && $.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier !== r.processID)
                fail("missing");
        }
        try {
            // A workspace snapshot avoids intermittent empty bundle-specific queries
            // observed when several short-lived automation clients run concurrently.
            var processes = $.NSWorkspace.sharedWorkspace.runningApplications;
            var matched = false;
            for (var i = 0; i < processes.count; i++) {
                var p = processes.objectAtIndex(i);
                if (p.processIdentifier === r.processID && ObjC.unwrap(p.bundleIdentifier) === r.bundleID &&
                    Math.abs(p.launchDate.timeIntervalSince1970 - r.launchedAt) < 0.001) matched = true;
            }
            if (!matched) fail("unavailable");
            checkForeground();
            var a = Application(r.bundleID);
            if (!a.running()) fail("unavailable");
            var w, t, s, tabID = "";
            if (r.windowID) w = find(a.windows(), "id", r.windowID);
            else if (r.kind === "ghostty") w = a.frontWindow();
            else if (r.kind === "iterm2") w = a.currentWindow();
            else { var windows = a.windows(); if (!windows.length) fail("missing"); w = windows[0]; }

            if (r.operation === "capture") {
                if (r.kind === "ghostty") { t = w.selectedTab(); s = t.focusedTerminal(); tabID = String(t.id()); }
                else if (r.kind === "iterm2") { t = w.currentTab(); s = t.currentSession(); }
                else { t = w.selectedTab(); s = t; }
                checkForeground();
                return JSON.stringify({ok:true, target:{
                    windowID:String(w.id()), windowTitle:title(w.name()), tabID:tabID,
                    terminalID:r.kind === "terminal" ? String(s.tty()) : String(s.id()),
                    terminalTitle:r.kind === "terminal" ? title(s.customTitle() || s.tty()) : title(s.name())
                }});
            }

            if (r.kind === "ghostty") {
                t = find(w.tabs(), "id", r.tabID);
                s = find(t.terminals(), "id", r.terminalID);
            } else if (r.kind === "iterm2") {
                var tabs = w.tabs();
                for (var j = 0; j < tabs.length && !s; j++) {
                    var sessions = tabs[j].sessions();
                    for (var k = 0; k < sessions.length; k++) {
                        if (String(sessions[k].id()) === r.terminalID) { s = sessions[k]; t = tabs[j]; break; }
                    }
                }
                if (!s) fail("missing");
            } else { t = find(w.tabs(), "tty", r.terminalID); s = t; }

            if (r.operation === "focus") {
                if (r.kind === "ghostty") { a.focus(s); a.activate(); }
                else if (r.kind === "iterm2") { a.activate(); w.index = 1; t.select(); s.select(); }
                else { t.selected = true; w.index = 1; a.activate(); }
            } else if (r.operation === "send") {
                if (r.kind === "ghostty") a.inputText(r.text, {to:s});
                else if (r.kind === "iterm2" && !/[\r\n\t\u0085\u2028\u2029]/.test(r.text)) {
                    s.write({text:r.text, newline:false});
                } else fail("unsupported");
            } else fail("unsupported");
            return JSON.stringify({ok:true});
        } catch (e) {
            return JSON.stringify({error:e.bridgeCode || (e.errorNumber === -1743 ? "permission" : "failed")});
        }
    }
    """#
}
