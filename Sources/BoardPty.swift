import Darwin
import Foundation

/// One real terminal for a console of the agents board: forkpty gives the command a pseudo-terminal of its own, so
/// Ctrl-C, job control and full-screen TUIs (Claude Code, Codex) behave as in Terminal. Output arrives on a private
/// queue through `onData`; `onExit` gets the exit code. The command runs inside the person's login shell, so the CLIs
/// on their PATH are found even though the app was opened from the Finder.
final class BoardPty {
    let pid: pid_t
    private let master: Int32
    private var read: DispatchSourceRead?
    private var proc: DispatchSourceProcess?
    private let q = DispatchQueue(label: "agentbar.board.pty")
    var onData: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?
    private(set) var exited = false

    enum Fallo: Error { case fork }

    /// `linea` empty opens the login shell itself
    init(linea: String, cwd: String, cols: Int, rows: Int) throws {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let args = linea.isEmpty ? [shell, "-l"] : [shell, "-l", "-c", "exec " + linea]
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"; env["COLORTERM"] = "truecolor"; env["LANG"] = env["LANG"] ?? "es_ES.UTF-8"
        let envList = env.map { "\($0.key)=\($0.value)" }
        // everything the child needs is prepared before fork: after it, only async-signal-safe calls
        var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        var cenv: [UnsafeMutablePointer<CChar>?] = envList.map { strdup($0) } + [nil]
        let cdir = strdup(cwd), cshell = strdup(shell)
        defer { cargs.forEach { free($0) }; cenv.forEach { free($0) }; free(cdir); free(cshell) }
        var ws = winsize(ws_row: UInt16(max(5, rows)), ws_col: UInt16(max(20, cols)), ws_xpixel: 0, ws_ypixel: 0)
        var m: Int32 = 0
        let p = forkpty(&m, nil, nil, &ws)
        if p < 0 { throw Fallo.fork }
        if p == 0 {
            _ = chdir(cdir)
            execve(cshell, &cargs, &cenv)
            _exit(127)
        }
        pid = p; master = m
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        let r = DispatchSource.makeReadSource(fileDescriptor: master, queue: q)
        r.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = Darwin.read(self.master, &buf, buf.count)
            if n > 0 { self.onData?(Data(buf[0..<n])) } else if n == 0 || (errno != EAGAIN && errno != EINTR) { self.read?.cancel() }
        }
        r.resume(); read = r
        let ps = DispatchSource.makeProcessSource(identifier: p, eventMask: .exit, queue: q)
        ps.setEventHandler { [weak self] in
            guard let self else { return }
            // drain what is left, then report
            var buf = [UInt8](repeating: 0, count: 65536)
            while true { let n = Darwin.read(self.master, &buf, buf.count); if n <= 0 { break }; self.onData?(Data(buf[0..<n])) }
            var st: Int32 = 0
            waitpid(self.pid, &st, 0)
            let code: Int32 = (st & 0x7f) == 0 ? (st >> 8) & 0xff : 128 + (st & 0x7f)
            self.exited = true
            self.read?.cancel(); self.proc?.cancel()
            close(self.master)
            self.onExit?(code)
        }
        ps.resume(); proc = ps
    }

    func write(_ data: Data) {
        q.async { [self] in
            guard !exited else { return }
            data.withUnsafeBytes { p in
                var off = 0
                while off < p.count {
                    let n = Darwin.write(master, p.baseAddress! + off, p.count - off)
                    if n > 0 { off += n } else if errno == EAGAIN { usleep(2000) } else { break }
                }
            }
        }
    }
    func resize(cols: Int, rows: Int) {
        q.async { [self] in
            guard !exited else { return }
            var ws = winsize(ws_row: UInt16(max(5, min(200, rows))), ws_col: UInt16(max(20, min(400, cols))), ws_xpixel: 0, ws_ypixel: 0)
            _ = ioctl(master, TIOCSWINSZ, &ws)
        }
    }
    /// hang up the whole session (SIGHUP), SIGKILL 3 s later if it is still there
    func kill() {
        guard !exited else { return }
        _ = Darwin.kill(-pid, SIGHUP); _ = Darwin.kill(pid, SIGHUP)
        let p = pid
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in if self?.exited == false { _ = Darwin.kill(p, SIGKILL) } }
    }
}
