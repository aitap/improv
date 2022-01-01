# make it possible to run improv both as a standalone script and a
# semi-static binary
all: tcwinsize.so improv

CFLAGS = -I/usr/include/lua5.3
LDFLAGS = -llua5.3

LUASTATIC = ~/.luarocks/bin/luastatic

LUASRC = improv.lua
LUAMOD = tcwinsize.a

%.so: %.o
	$(LD) $(LDFLAGS) -shared -o $@ $^

%.a: %.o
	$(AR) rs $@ $^

improv: $(LUASRC) $(LUAMOD)
	$(LUASTATIC) $^ $(CFLAGS) $(LDFLAGS)
# avoid confusing Make into building improv.lua from improv.lua.c
	rm improv.lua.c
