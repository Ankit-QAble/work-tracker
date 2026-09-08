import AppKit

// Line-buffer stdout so `Log` output shows up promptly in redirected logs / Console,
// not just when the buffer happens to fill or the process exits cleanly.
setvbuf(stdout, nil, _IOLBF, 0)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
