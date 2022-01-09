# only build the module by default
all: tcwinsize.so

LUA_VERSION = 5.3
CFLAGS = -I/usr/include/lua$(LUA_VERSION)
LDFLAGS = -llua$(LUA_VERSION)

LUASTATIC = ~/.luarocks/bin/luastatic

LUASRC = improv.lua
LUAMOD = \
	tcwinsize.a \
	posix/_argcheck.lua posix/compat.lua posix/deprecated.lua \
	posix/init.lua posix/sys.lua posix/util.lua \
	/usr/lib/x86_64-linux-gnu/liblua$(LUA_VERSION)-posix.a -lcrypt \
	/usr/lib/x86_64-linux-gnu/liblua$(LUA_VERSION).a \

posix/%.lua: /usr/share/lua/$(LUA_VERSION)/posix/%.lua
	mkdir -p posix
	ln -s $^ $@

%.so: %.o
	$(LD) $(LDFLAGS) -shared -o $@ $^

%.a: %.o
	$(AR) rs $@ $^

# but make it possible to link a mostly-static binary if needed
improv: $(LUASRC) $(LUAMOD)
	$(LUASTATIC) $(LUASRC) $(LUAMOD) $(CFLAGS)
# avoid confusing Make into building improv.lua from improv.lua.c
	rm improv.lua.c
