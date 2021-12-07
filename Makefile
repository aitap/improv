all: tcwinsize.so

CFLAGS = -I/usr/include/lua5.3

%.so: %.c
	$(CC) $(CFLAGS) $(LDFLAGS) -shared -o $@ $^
