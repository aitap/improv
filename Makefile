# make it possible to run improv both as a standalone script and a
# semi-static binary
all: tcwinsize.so improv

CFLAGS = -I/usr/include/lua5.3
LDFLAGS = -llua5.3

LUASTATIC = ~/.luarocks/bin/luastatic

LUASRC = improv.lua
LUAMOD = \
	tcwinsize.a \
	posix/_argcheck.lua posix/compat.lua posix/deprecated.lua \
	posix/init.lua posix/sys.lua posix/util.lua \
	/usr/lib/x86_64-linux-gnu/liblua5.3-posix.a -lcrypt \
	/usr/lib/x86_64-linux-gnu/liblua5.3.a \

posix/%.lua: /usr/share/lua/5.3/posix/%.lua
	mkdir -p posix
	ln -s $^ $@

%.so: %.o
	$(LD) $(LDFLAGS) -shared -o $@ $^

%.a: %.o
	$(AR) rs $@ $^

improv: $(LUASRC) $(LUAMOD)
	$(LUASTATIC) $(LUASRC) $(LUAMOD) $(CFLAGS)
# avoid confusing Make into building improv.lua from improv.lua.c
	rm improv.lua.c
