Improv
======

> The best and most telling speech is not the actual impromptu one, but
> the counterfeit of it ... that speech is most worth listening to which
> has been carefully prepared in private and tried on a plaster cast, or
> an empty chair, or any other appreciative object that will keep quiet,
> until the speaker has got his matter and his delivery limbered up so
> that they will seem impromptu to an audience.

-- [Mark Twain in his speech in New York City, 31 March 1885][Twain1885]

What is it?
-----------

A short summary would be "an interactive counterpart to [Expect]".

If you need to [write some code in a text mode REPL in front of an
audience][Wat] and would like to avoid the embarrassment of dealing with
the typos, remembering the order of the arguments and live-debugging
that one problem you hadn't thought of, you can pre-write that code and
have Improv type it chunk by chunk at a press of a shortcut. On the
other hand, anything else you type into Improv is transparently
forwarded to the child process, leaving you the option to expand or
answer questions on the fly.

What does it work with?
-----------------------

For now, the requirements are:

 * A [POSIX] operating system.
   * On Windows, you can use Cygwin or WSL.
   * Additionally, the OS must support the `WINCH` signal and the
     `TIOCGWINSZ`/`TIOCSWINSZ` `ioctl`s on ttys, which (I think) still
     includes most of them. POSIX [intends to include][POSIX-winsize]
     terminal size support in a future version, but it's not there yet.
 * [Lua] 5.3 with the [posix][luaposix] module.
   * There's no reason for it not to work on Lua 5.4, but I haven't
     tested that.
 * A C compiler to build the C part of the program.
 * The REPL must be a text mode application.

How to use it?
--------------

Create a configuration file (Lua syntax) specifying what to launch and
the text chunks to type inside it. A minimal example would be:

```lua
exec.path = 'lua5.3'
chunks = {
	'P = require"posix"\n', 'print("Hello, world")\n', 'os.exit()\n'
}
```

Pass the configuration file as a command-line parameter to Improv. The
default shortcut to type the next chunk is **Ctrl+E**. If you reach the
last chunk while the child process is still running, it starts again
from the first one.

### Options

 * `exec` must be a table (and is so by default)
   * `exec.path` must be a string containing the name of a program to
     launch as a child process. There is no default, so it must be set.
   * `exec.argv` must be an unnamed table (a sequence in Lua terms)
     containing the arguments to the child process. It defaults to an
     empty table. The table can contain the index `[0]`.
 * `chunks` must be an unnamed table (a sequence) containing the strings
   to type into the child process one by one. Must be set; there's no
   default.
 * `chdir` can be a string to set the working directory before starting
   the child process. Optional parameter.
 * `advance` sets the key code which makes Improv type the next chunk.
   It must be a single-byte string. Defaults to `\x05`, which typically
   corresponds to **Ctrl+E**.
 * `escape` sets the key code which switches Improv into escape mode
   (see below). Defaults to `\x06` (**Ctrl+F**).

### Escape mode

The following key presses are interpreted in the escape mode:

 * Press the `advance` or `escape` shortcut to type it into the child
   process and return to the normal mode.
 * Press **h** or **j** to go back one chunk, or **k** or **l** to go
   one chunk forward, but not enter it yet. This doesn't leave the
   escape mode.
 * Press any other key to go back to the normal mode.

How does it work?
-----------------

The child process is launched with its standard input, output and error
redirected to a pseudoterminal. Improv switches its own terminal into
raw mode and pipes bytes between its standard input and output and the
child running behind the pseudoterminal. Improv also forwards the
terminal window size changes, which requires the non-POSIX features.
Improv recognises certain bytes if entered on its standard input (which
must be carefully chosen not to be part of normal input, e.g. multi-byte
UTF-8 characters or byte sequences representing function key presses in
the terminal) and interprets them as described above.

License
-------

Improv: helper for REPL presentations

Copyright (C) 2021-2022  Ivan Krylov

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

[Twain1885]: http://www.twainquotes.com/Speech.html
[Expect]: https://core.tcl-lang.org/expect/index
[Wat]: https://www.destroyallsoftware.com/talks/wat
[Lua]: https://www.lua.org/
[luaposix]: http://luaposix.github.io/luaposix/
[POSIX]: https://pubs.opengroup.org/onlinepubs/9699919799/
[POSIX-winsize]: https://austingroupbugs.net/view.php?id=1151
