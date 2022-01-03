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

local function read(fd, sz)
	local buf, errmsg
	repeat
		local errnum
		buf, errmsg, errnum = P.read(fd, sz)
	until buf or errnum ~= P.EINTR
	assert(buf, errmsg)
	return buf
end

-- keep trying until all of buf is written to the fd
local function write(fd, buf)
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

local function cli(stdin, child)
	local buf = read(stdin, 512)
	for i = 1,#buf do
		local ch = buf:sub(i)
		if ch == config.next then
			-- TODO: print next chunk from chunks to the child
		elseif ch == config.menu then
			-- TODO: switch to menu mode
		else
			-- write interactive input byte by byte
			write(child, buf:sub(i,i))
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
		[P.STDIN_FILENO] = { events = { IN = true }, revents = {} },
		[      ptm     ] = { events = { IN = true }, revents = {} },
	}
	while true do
		local ret, _, errnum = P.poll(fds)
		if ret then
			if fds[P.STDIN_FILENO].revents.IN then
				cli(P.STDIN_FILENO, ptm)
			elseif fds[ptm].revents.IN then
				write(P.STDOUT_FILENO, read(ptm, 4096))
			elseif fds[P.STDIN_FILENO].revents.HUP or fds[ptm].revents.HUP then
				-- child exiting or terminal closed
				break
			end
		elseif errnum ~= P.EINTR then
			-- failure other than "interrupted by signal we handled"
			break
		end
	end
end

local ptm, ptsp = make_pty()

-- must handle terminal resize
local function winch()
	assert(W.setsize(ptm, assert(W.getsize(P.STDIN_FILENO))))
end
winch() -- also set it initially

local pid = assert(P.fork())
if pid == 0 then
	if config.chdir then assert(P.chdir(config.chdir)) end
	assert(P.close(ptm))
	child_exec(ptsp, config.exec.path, config.exec.argv)
end

P.signal(W.SIGWINCH, winch) -- NB: there's no SA_RESTART in POSIX
parent_loop(ptm)
