local P = require'posix'
P.time = require'posix.time'
local U = {}

function U.read(fd, sz)
	local buf, errmsg
	repeat
		local errnum
		buf, errmsg, errnum = P.read(fd, sz)
	until buf or errnum ~= P.EINTR
	assert(buf, errmsg)
	return buf
end

-- keep trying until all of buf is written to the fd
function U.write(fd, buf)
	local written = 0
	while written < #buf do
		local wr, errmsg
		repeat
			local errnum
			wr, errmsg, errnum = P.write(fd, buf:sub(written + 1))
		until wr or errnum ~= P.EINTR
		assert(wr, errmsg)
		written = written + wr
	end
end

-- return master PTY file descriptor, but slave PTY path
function U.make_pty()
	local ptm = P.openpt(P.O_RDWR|P.O_NOCTTY)
	assert(P.grantpt(ptm))
	assert(P.unlockpt(ptm))
	local ptsp = assert(P.ptsname(ptm))
	return ptm, ptsp
end

-- exec child process with stdio connected to a given TTY
function U.child_exec(ptsp, path, args)
	assert(P.setpid('s')) -- setsid()
	local pts = assert(P.open(ptsp, P.O_RDWR)) -- set the controlling TTY
	assert(P.dup2(pts, P.STDIN_FILENO))
	assert(P.dup2(pts, P.STDOUT_FILENO))
	assert(P.dup2(pts, P.STDERR_FILENO))
	assert(P.execp(path, args))
end

-- return termios table modified for raw mode
function U.cfmakeraw(att)
	return {
		cc = att.cc,
		cflag = att.cflag & ~(P.CSIZE | P.PARENB) | P.CS8,
		iflag = att.iflag & ~(
			P.IGNBRK | P.BRKINT | P.PARMRK | P.ISTRIP | P.INLCR
			| P.IGNCR | P.ICRNL | P.IXON
		),
		lflag = att.lflag & ~(
			P.ECHO | P.ECHONL | P.ICANON | P.ISIG | P.IEXTEN
		),
		oflag = att.oflag & ~P.OPOST,
		ispeed = att.ispeed,
		ospeed = att.ospeed
	}
end

-- run fn() when garbage-collecting the return value
function U.guard(fn)
	local ret = {__gc = fn}
	return setmetatable(ret, ret)
end

function U.monotime()
	local t = P.time.clock_gettime(P.CLOCK_MONOTONIC)
	return t.tv_sec + t.tv_nsec/1e9
end

return U
