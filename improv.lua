#!/usr/bin/lua5.3
local P = require'posix'
local W = require'tcwinsize'
local U = require'util'

local config = {
	exec = { argv = {} },
	advance = '\x05', -- ^E
	escape = '\x06', -- ^F
}

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
		U.write(stdout, str)
	end
	local function unprompt()
		U.write(stdout,
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
		U.write(child, ch)
		switch_pump()
	end
	local pump_handlers = {
		[config.advance] = function()
			-- write out next chunk
			U.write(child, config.chunks[pos])
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

	local function cli()
		local buf = U.read(stdin, 512)
		for i = 1,#buf do
			handlers[mode](buf:sub(i,i))
		end
	end

	return function()
		local fds = {
			[stdin] = {events = { IN = true }},
			[child] = {events = { IN = true }},
		}
		while true do
			local ret, _, errnum = P.poll(fds)
			if ret then
				if fds[stdin].revents.IN then
					cli()
				elseif fds[child].revents.IN then
					U.write(P.STDOUT_FILENO, U.read(child, 4096))
				elseif fds[stdin].revents.HUP or fds[child].revents.HUP then
					-- child exiting or terminal closed
					break
				end
			elseif errnum ~= P.EINTR then
				-- failure other than "interrupted by signal we handled"
				break
			end
		end
	end
end

local function parent_loop(ptm, cli)
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

local ptm, ptsp = U.make_pty()
-- must handle terminal resize
local function winch()
	assert(W.setsize(ptm, assert(W.getsize(P.STDIN_FILENO))))
end
winch() -- also set it initially

local pid = assert(P.fork())
if pid == 0 then
	assert(P.close(ptm))
	U.child_exec(ptsp, config.exec.path, config.exec.argv)
end

P.signal(W.SIGWINCH, winch) -- NB: there's no SA_RESTART in POSIX

local att = assert(P.tcgetattr(P.STDIN_FILENO))
-- restore terminal on shutdown
local atexit = U.guard(function()
	assert(P.tcsetattr(P.STDIN_FILENO, P.TCSANOW, att))
end)
assert(P.tcsetattr(P.STDIN_FILENO, P.TCSANOW, U.cfmakeraw(att)))

init_cli(P.STDIN_FILENO, P.STDOUT_FILENO, ptm)()
