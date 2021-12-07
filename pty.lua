#!/usr/bin/lua5.3
local P = require'posix'
local W = require'tcwinsize'

-- doesn't have to send all input, will be called again by the poll loop
local function pump(from, to)
	local buf = assert(P.read(from, 1024))
	local written = 0
	while written < #buf do
		written = written + assert(P.write(to, buf:sub(written+1)))
	end
end

-- return master PTY file descriptor, but slave PTY path
local function make_pty()
	local ptm = P.openpt(P.O_RDWR|P.O_NOCTTY)
	assert(P.grantpt(ptm))
	assert(P.unlockpt(ptm))
	local ptsp = assert(P.ptsname(ptm))
	return ptm, ptsp
end

-- exec child process with stdio connected to a given TTY
local function child_exec(ptsp, path, args)
	assert(P.setpid('s'))
	-- will set the controlling TTY
	local pts = assert(P.open(ptsp, P.O_RDWR))
	assert(P.dup2(pts, P.STDIN_FILENO))
	assert(P.dup2(pts, P.STDOUT_FILENO))
	assert(P.dup2(pts, P.STDERR_FILENO))
	assert(P.execp(path, args))
end

local function clone(x)
	local cpy = {}
	for k,v in pairs(x) do cpy[k] = v end
	return cpy
end

local function cfmakeraw(att)
	att.iflag = att.iflag & ~(
		P.IGNBRK | P.BRKINT | P.PARMRK | P.ISTRIP | P.INLCR | P.IGNCR
		| P.ICRNL | P.IXON
	)
	att.oflag = att.oflag & ~P.OPOST
	att.lflag = att.lflag & ~(
		P.ECHO | P.ECHONL | P.ICANON | P.ISIG | P.IEXTEN
	)
	att.cflag = att.cflag & ~(P.CSIZE | P.PARENB)
	att.cflag = att.cflag | P.CS8
end

-- run fn() when garbage-collecting the return value
local function guard(fn)
	local ret = {__gc = fn}
	return setmetatable(ret, ret)
end

-- pump raw mode stdin to ptm and ptm to stdout
local function parent_loop(ptm)
	local att = assert(P.tcgetattr(P.STDIN_FILENO))
	-- restore terminal on shutdown
	local oatt = clone(att)
	local atexit = guard(function()
		assert(P.tcsetattr(P.STDIN_FILENO, P.TCSANOW, oatt))
	end)
	cfmakeraw(att)
	assert(P.tcsetattr(P.STDIN_FILENO, P.TCSANOW, att))

	local fds = {
		[P.STDIN_FILENO] = { events = { IN = true } },
		[      ptm     ] = { events = { IN = true } },
	}
	repeat
		local ret, _, errnum = P.poll(fds)
		if fds[P.STDIN_FILENO].revents.IN then pump(P.STDIN_FILENO, ptm)
		elseif fds[ptm].revents.IN then pump(ptm, P.STDOUT_FILENO)
		else break end -- must have got a HUP due to child exiting
	until not (
		ret or (errnum == P.EINTR) -- poll always gets interrupted by signals
	)
end

local ptm, ptsp = make_pty()

-- must handle terminal resize
local function winch()
	assert(W.setsize(ptm, assert(W.getsize(P.STDIN_FILENO))))
end
P.signal(W.SIGWINCH, winch, P.SA_RESTART)
winch() -- also set it initially

local pid = assert(P.fork())
if pid > 0 then
	parent_loop(ptm)
else
	assert(P.close(ptm))
	child_exec(ptsp, 'R', {})
end
