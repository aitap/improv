#include <lauxlib.h>
#include <limits.h>
#include <lua.h>
#include <sys/ioctl.h>
#include <termios.h>

/* Hopefully, there will be POSIX functions to do that:
	int tcgetwinsize(int, struct winsize *);
	int tcsetwinsize(int, const struct winsize *);
with struct winsize containing unsigned short ws_row, ws_col
See also: https://austingroupbugs.net/view.php?id=1151 */

static int setsize(int fd, unsigned short nrow, unsigned short ncol) {
	struct winsize ws = { 0, };
	/* most people ignore the pixels, and so do we */
	ws.ws_row = nrow;
	ws.ws_col = ncol;
	return ioctl(fd, TIOCSWINSZ, &ws);
}

static int getsize(int fd, unsigned short * nrow, unsigned short * ncol) {
	struct winsize ws;
	int ret = ioctl(fd, TIOCGWINSZ, &ws);
	if (!ret) {
		*nrow = ws.ws_row;
		*ncol = ws.ws_col;
	}
	return ret;
}

static int Lgetsize(lua_State * L) {
	int n = lua_gettop(L);
	if (n != 1)
		luaL_error(L, "Usage: nrow, ncol or nil, errno = setsize(fd)");
	lua_Integer fd = luaL_checkinteger(L, 1);
	if (fd < 0 || fd > INT_MAX)
		luaL_error(L, "fd must fit in a nonnegative int");

	unsigned short nrow, ncol;
	int ret = getsize((int)fd, &nrow, &ncol);

	if (ret) {
		lua_pushnil(L);
		lua_pushnumber(L, ret);
	} else {
		lua_pushnumber(L, nrow);
		lua_pushnumber(L, ncol);
	}
	return 2;
}

static int Lsetsize(lua_State * L) {
	int n = lua_gettop(L);
	if (n != 3)
		luaL_error(L, "Usage: (0) or (nil, errno) = setsize(fd, nrow, ncol)");
	lua_Integer fd = luaL_checkinteger(L, 1),
		nrow = luaL_checkinteger(L, 2),
		ncol = luaL_checkinteger(L, 3);
	if (fd < 0 || fd > INT_MAX)
		luaL_error(L, "fd must fit in a nonnegative int");
	if (nrow < 0 || nrow > USHRT_MAX)
		luaL_error(L, "nrow must fit in an unsigned short");
	if (ncol < 0 || ncol > USHRT_MAX)
		luaL_error(L, "ncol must fit in an unsigned short");

	int ret = setsize((int)fd, (unsigned short)nrow, (unsigned short)ncol);

	if (ret) {
		lua_pushnil(L);
		lua_pushnumber(L, ret);
		return 2;
	} else {
		lua_pushnumber(L, 0);
		return 1;
	}
}

static luaL_Reg funcs[] = {
	{ "getsize", Lgetsize, },
	{ "setsize", Lsetsize, },
	{ NULL, NULL }
};

int luaopen_tcwinsize(lua_State * L) {
	luaL_newlib(L, funcs);
	return 1;
}
