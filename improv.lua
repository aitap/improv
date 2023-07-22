#!/usr/bin/lua5.3
if arg then
	-- thanks to David Manura's findbin package for inspiration
	--[[
		Package.config contains the directory separator, path separator,
		and the substitution character to be interpreted in package.c?path.
	]]
	local pkgcfg = {}
	for c in package.config:gmatch('[^\n]+') do
		table.insert(pkgcfg, c)
	end
	local dirsep, pathsep, subst  = table.unpack(pkgcfg) -- the first 3

	--[[
		The script name, including the path it's being launched as, goes
		to the index 0. We assume that by chopping off everything after the
		last directory separator, we get the script path.
	]]
	local selfdir = arg[0]:gsub('[^' .. dirsep .. ']*$', '', 1)
	-- no path means the current directory
	if #selfdir == 0 then selfdir = './' end
	package.path = selfdir .. subst .. '.lua' .. pathsep .. package.path
	package.cpath = selfdir
		--[[
			Here we hopefully get the shared object suffix as the part that
			starts with the substitution character of the last entry.
		]]
		.. package.cpath:match('(%' .. subst .. '[^' .. subst ..  ']*' .. ')$')
		.. pathsep .. package.cpath
end

local P = require'posix'
local W = require'tcwinsize'
local U = require'util'

local config = {
	exec = { argv = {} },
	advance = '\x05', -- ^E
	escape = '\x06', -- ^F
	delay = .025,
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

	local queue = '' -- TODO: making it a table would be faster
	local delay_remaining = -1
	local function enqueue(str)
		queue = queue .. str
	end
	local function dequeue_one()
		U.write(child, queue:sub(1,1))
		queue = queue:sub(2)
		delay_remaining = config.delay
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
			enqueue(config.chunks[pos])
			pos_next()
		end,
		[config.escape] = switch_escape,
	}
	local function escape_prev()
		unprompt()
		pos_prev()
		prompt(('%d/%d[%s]'):format(
			pos, #config.chunks,
			U.excerpt(config.chunks[pos])
		))
	end
	local function escape_next()
		unprompt()
		pos_next()
		prompt(('%d/%d[%s]'):format(
			pos, #config.chunks,
			U.excerpt(config.chunks[pos])
		))
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
			[stdin] = {events = {IN = true}},
			[child] = {events = {IN = true}},
		}
		while true do
			local timeout = (#queue > 0)
				and math.tointeger(delay_remaining * 1000 // 1) or -1
			local dt = U.monotime()
			local ret, _, errnum = P.poll(fds, timeout)
			delay_remaining = delay_remaining - (U.monotime() - dt)
			if ret then
				if ret > 0 then
					if fds[stdin].revents.IN then
						cli()
					elseif fds[child].revents.IN then
						U.write(stdout, U.read(child, 4096))
					elseif fds[stdin].revents.HUP or fds[child].revents.HUP then
						-- child exiting or terminal closed
						break
					end
				end
				if #queue > 0 and delay_remaining <= 0 then dequeue_one() end
			elseif errnum ~= P.EINTR then
				-- failure other than "interrupted by signal we handled"
				break
			end
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

 * chdir:   set the working directory before executing anything
            (can be either a string signifying the desired path or true,
            in which case the destination is dirname(configfile))
 * advance: the key code (as a single byte) to print the next chunk
            (defaults to %q)
 * escape:  the escape key code
            (defaults to %q)
 * delay:   delay between bytes typed into the child process, s
            (defaults to %g)]]):format(
		arg[0], config.advance, config.escape, config.delay
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
		type(config.chdir) == 'nil' or type(config.chdir) == 'string'
		or type(config.chdir) == 'boolean',
		'chdir must be a string or a boolean if set'
	},
	{
		type(config.advance) == 'string' and #config.advance == 1,
		'advance must be a single-byte string'
	},
	{
		type(config.escape) == 'string' and #config.escape == 1,
		'escape must be a single-byte string'
	},
	{
		type(config.delay) == 'number',
		'delay must be a number'
	},
}
do
	assert(p[1], 'config: ' .. p[2])
end

if config.chdir then
	if type(config.chdir) == 'string' then
		assert(P.chdir(config.chdir))
	else
		assert(P.chdir(U.dirname(arg[1])))
	end
end

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
