#!/usr/bin/lua5.3
local P = require'posix'
local W = require'tcwinsize'

local config = {
	chdir = nil,
	exec = { path = 'R', argv = {} },
	chunks = {
		"ls()\n", "?ls\n", "q()\n"
	},
	next = '\x05', -- ^E
	menu = '\x06', -- ^F
}

-- keep trying until all of buf is written to the fd
local function write(fd, buf)
	local written = 0
	while written < #buf do
		written = written + assert(P.write(fd, buf:sub(written+1)))
	end
end

local function cli(stdin, child)
	local buf = assert(P.read(stdin, 512))
	for i = 1,#buf do
		local ch = buf:sub(i)
		if ch == config.next then
			-- TODO: print next chunk from chunks to the child
		elseif ch == config.menu then
			-- TODO: switch to menu mode
		else
			-- write interactive input symbol by symbol
			write(child, buf:sub(i))
		end
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
	assert(P.setpid('s')) -- setsid()
	local pts = assert(P.open(ptsp, P.O_RDWR)) -- set the controlling TTY
	assert(P.dup2(pts, P.STDIN_FILENO))
	assert(P.dup2(pts, P.STDOUT_FILENO))
	assert(P.dup2(pts, P.STDERR_FILENO))
	assert(P.execp(path, args))
end

-- return termios table modified for raw mode
local function cfmakeraw(att)
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
local function guard(fn)
	local ret = {__gc = fn}
	return setmetatable(ret, ret)
end

-- pump raw mode stdin to ptm and ptm to stdout
local function parent_loop(ptm)
	local att = assert(P.tcgetattr(P.STDIN_FILENO))
	-- restore terminal on shutdown
	local atexit = guard(function()
		assert(P.tcsetattr(P.STDIN_FILENO, P.TCSANOW, att))
	end)
	assert(P.tcsetattr(P.STDIN_FILENO, P.TCSANOW, cfmakeraw(att)))

	local fds = {
		[P.STDIN_FILENO] = { events = { IN = true } },
		[      ptm     ] = { events = { IN = true } },
	}
	repeat
		local ret, _, errnum = P.poll(fds)
		if fds[P.STDIN_FILENO].revents.IN then cli(P.STDIN_FILENO, ptm)
		elseif fds[ptm].revents.IN then
			-- doesn't have to send all input, will be called again by
			-- the poll loop; but we do need a buffer large enough for a
			-- typical screenful
			write(P.STDOUT_FILENO, assert(P.read(ptm, 4096)))
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
winch() -- also set it initially

local pid = assert(P.fork())
if pid > 0 then
	P.signal(W.SIGWINCH, winch, P.SA_RESTART)
	parent_loop(ptm)
else
	if config.chdir then assert(P.chdir(config.chdir)) end
	assert(P.close(ptm))
	child_exec(ptsp, config.exec.path, config.exec.argv)
end
