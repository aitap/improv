#!/usr/bin/lua5.3
local P = require'posix'
local W = require'tcwinsize'

local config = {
	exec = { argv = {} },
	advance = '\x05', -- ^E
	escape = '\x06', -- ^F
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

local function init_cli(stdin, stdout, child)
	-- state
	local mode = 'pump'

	local pos = 1
	local function pos_next()
		-- restart at 1 after last chunk
		pos = (pos % #config.chunks) + 1
	end
	local function pos_prev()
		pos = pos - 1
		-- restart at N after first chunk
		if pos == 0 then pos = #config.chunks end
	end

	local n_prompt = 0
	local function prompt(str)
		n_prompt = n_prompt + #str
		write(stdout, str)
	end
	local function unprompt()
		write(stdout,
			('\b'):rep(n_prompt)
			.. (' '):rep(n_prompt)
			.. ('\b'):rep(n_prompt)
		)
		n_prompt = 0
	end

	local function switch_escape()
		prompt('?')
		mode = 'escape'
	end
	local function switch_pump()
		unprompt()
		mode = 'pump'
	end

	-- events for both modes
	local function pump_ch(ch)
		write(child, ch)
		switch_pump()
	end
	local pump_handlers = {
		[config.advance] = function()
			-- write out next chunk
			write(child, config.chunks[pos])
			pos_next()
		end,
		[config.escape] = switch_escape,
	}
	local function escape_prev()
		unprompt()
		pos_prev()
		prompt(('%d/%d'):format(pos, #config.chunks))
	end
	local function escape_next()
		unprompt()
		pos_next()
		prompt(('%d/%d'):format(pos, #config.chunks))
	end
	local escape_handlers = {
		[config.advance] = pump_ch,
		[config.escape] = pump_ch,
		h = escape_prev,
		j = escape_prev,
		k = escape_next,
		l = escape_next,
	}
	local handlers = {
		pump = function(ch)
			(pump_handlers[ch] or pump_ch)(ch)
		end,
		escape = function(ch)
			local f = escape_handlers[ch]
			if f then f(ch) else switch_pump() end
		end,
	}

	return function()
		local buf = read(stdin, 512)
		for i = 1,#buf do
			handlers[mode](buf:sub(i,i))
		end
	end
end

local function parent_loop(ptm, cli)
	local fds = {
		[P.STDIN_FILENO] = {events = { IN = true }},
		[      ptm     ] = {events = { IN = true }},
	}
	while true do
		local ret, _, errnum = P.poll(fds)
		if ret then
			if fds[P.STDIN_FILENO].revents.IN then
				cli()
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

if #arg ~= 1 then
	print(([[Usage: %s config.lua

The config file must assign the following variables:

 * exec:    a table of the following structure:
   { path = 'command', argv = { [0] = 'argv0', 'arg1', 'arg2', ... } }
   (exec.argv defaults to an empty table, but path isn't set at all)
 * chunks:  a table containing pre-programmed chunks to enter

Additionally, you can set the following parameters:

 * chdir:   set the working directoru before executing anything
 * advance: the key code (as a single byte) to print the next chunk
            (defaults to %q)
 * escape:  the escape key code
            (defaults to %q)]]):format(
		arg[0], config.advance, config.escape
	))
	os.exit(1)
end

assert(loadfile(arg[1], 'bt', config))()
for _,p in ipairs{
	{ type(config.exec) == 'table', 'exec must be a table' },
	{ type(config.exec.path) == 'string', 'exec.path must be a string' },
	{ type(config.exec.argv) == 'table', 'exec.argv must be a table' },
	{
		type(config.chunks) == 'table' and #config.chunks > 0,
		'chunks must be a non-empty sequence'
	},
	{
		type(config.chdir) == 'nil' or type(config.chdir) == 'string',
		'chdir must be a string if set'
	},
	{
		type(config.advance) == 'string' and #config.advance == 1,
		'advance must be a single-byte string'
	},
	{
		type(config.escape) == 'string' and #config.escape == 1,
		'escape must be a single-byte string'
	}
}
do
	assert(p[1], 'config: ' .. p[2])
end

if config.chdir then assert(P.chdir(config.chdir)) end

local ptm, ptsp = make_pty()
-- must handle terminal resize
local function winch()
	assert(W.setsize(ptm, assert(W.getsize(P.STDIN_FILENO))))
end
winch() -- also set it initially

local pid = assert(P.fork())
if pid == 0 then
	assert(P.close(ptm))
	child_exec(ptsp, config.exec.path, config.exec.argv)
end

P.signal(W.SIGWINCH, winch) -- NB: there's no SA_RESTART in POSIX

local att = assert(P.tcgetattr(P.STDIN_FILENO))
-- restore terminal on shutdown
local atexit = guard(function()
	assert(P.tcsetattr(P.STDIN_FILENO, P.TCSANOW, att))
end)
assert(P.tcsetattr(P.STDIN_FILENO, P.TCSANOW, cfmakeraw(att)))

parent_loop(ptm, init_cli(P.STDIN_FILENO, P.STDOUT_FILENO, ptm))
