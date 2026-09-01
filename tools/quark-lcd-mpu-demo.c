// SPDX-License-Identifier: MIT
/* Quark-N demo: KEY_PROG1 + ST7789 framebuffer + MPU6050 IIO. */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define KEY_CODE KEY_PROG1
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

struct app {
	int fb_fd, key_fd, tty_fd;
	uint8_t *fb;
	size_t fb_len;
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	char iio[256];
	int hold;
};

static volatile sig_atomic_t running = 1;

static void stop(int sig)
{
	(void)sig;
	running = 0;
}

static uint32_t color(const struct app *a, uint8_t r, uint8_t g, uint8_t b)
{
	uint32_t rv = ((uint32_t)r * ((1u << a->var.red.length) - 1) / 255)
		<< a->var.red.offset;
	uint32_t gv = ((uint32_t)g * ((1u << a->var.green.length) - 1) / 255)
		<< a->var.green.offset;
	uint32_t bv = ((uint32_t)b * ((1u << a->var.blue.length) - 1) / 255)
		<< a->var.blue.offset;
	return rv | gv | bv;
}

static void pixel(struct app *a, int x, int y, uint32_t c)
{
	uint8_t *p;
	unsigned int bytes = a->var.bits_per_pixel / 8;

	if (x < 0 || y < 0 || x >= (int)a->var.xres || y >= (int)a->var.yres)
		return;
	p = a->fb + (size_t)y * a->fix.line_length + (size_t)x * bytes;
	if (bytes == 2)
		*(uint16_t *)p = (uint16_t)c;
	else if (bytes == 4)
		*(uint32_t *)p = c;
}

static void rect(struct app *a, int x, int y, int w, int h, uint32_t c)
{
	int xx, yy;
	for (yy = y; yy < y + h; yy++)
		for (xx = x; xx < x + w; xx++)
			pixel(a, xx, yy, c);
}

/* Compact 5x7 glyphs used by this demo. Each byte is one five-bit row. */
static const uint8_t *glyph(char ch)
{
	static const struct { char ch; uint8_t row[7]; } font[] = {
		{' ',{0,0,0,0,0,0,0}}, {'-',{0,0,0,31,0,0,0}},
		{':',{0,4,4,0,4,4,0}}, {'.',{0,0,0,0,0,6,6}},
		{'0',{14,17,19,21,25,17,14}}, {'1',{4,12,4,4,4,4,14}},
		{'2',{14,17,1,2,4,8,31}}, {'3',{30,1,1,14,1,1,30}},
		{'4',{2,6,10,18,31,2,2}}, {'5',{31,16,16,30,1,1,30}},
		{'6',{14,16,16,30,17,17,14}}, {'7',{31,1,2,4,8,8,8}},
		{'8',{14,17,17,14,17,17,14}}, {'9',{14,17,17,15,1,1,14}},
		{'A',{14,17,17,31,17,17,17}}, {'B',{30,17,17,30,17,17,30}},
		{'C',{14,17,16,16,16,17,14}}, {'D',{30,17,17,17,17,17,30}},
		{'E',{31,16,16,30,16,16,31}}, {'F',{31,16,16,30,16,16,16}},
		{'G',{14,17,16,23,17,17,15}}, {'H',{17,17,17,31,17,17,17}},
		{'I',{14,4,4,4,4,4,14}}, {'K',{17,18,20,24,20,18,17}},
		{'L',{16,16,16,16,16,16,31}}, {'M',{17,27,21,21,17,17,17}},
		{'N',{17,25,21,19,17,17,17}}, {'O',{14,17,17,17,17,17,14}},
		{'P',{30,17,17,30,16,16,16}}, {'Q',{14,17,17,17,21,18,13}},
		{'R',{30,17,17,30,20,18,17}}, {'S',{15,16,16,14,1,1,30}},
		{'T',{31,4,4,4,4,4,4}}, {'U',{17,17,17,17,17,17,14}},
		{'V',{17,17,17,17,17,10,4}}, {'X',{17,17,10,4,10,17,17}},
		{'Y',{17,17,10,4,4,4,4}}, {'Z',{31,1,2,4,8,16,31}},
	};
	static const uint8_t unknown[7] = {14,17,1,2,4,0,4};
	size_t i;
	for (i = 0; i < ARRAY_SIZE(font); i++)
		if (font[i].ch == ch)
			return font[i].row;
	return unknown;
}

static void text(struct app *a, int x, int y, int scale, uint32_t c, const char *s)
{
	for (; *s; s++, x += 6 * scale) {
		const uint8_t *g = glyph(*s >= 'a' && *s <= 'z' ? *s - 32 : *s);
		int row, col;
		for (row = 0; row < 7; row++)
			for (col = 0; col < 5; col++)
				if (g[row] & (1u << (4 - col)))
					rect(a, x + col * scale, y + row * scale,
					     scale, scale, c);
	}
}

static int read_int(const char *dir, const char *name, int *value)
{
	char path[384], buf[64];
	int fd, n;
	snprintf(path, sizeof(path), "%s/%s", dir, name);
	fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return -1;
	buf[n] = 0;
	*value = (int)strtol(buf, NULL, 10);
	return 0;
}

static int find_iio(char *out, size_t len)
{
	DIR *dir = opendir("/sys/bus/iio/devices");
	struct dirent *de;
	if (!dir)
		return -1;
	while ((de = readdir(dir))) {
		char path[320];
		if (strncmp(de->d_name, "iio:device", 10))
			continue;
		snprintf(path, sizeof(path), "/sys/bus/iio/devices/%s", de->d_name);
		if (read_int(path, "in_accel_x_raw", &(int){0}) == 0) {
			size_t path_len = strlen(path);
			if (path_len >= len)
				continue;
			memcpy(out, path, path_len + 1);
			closedir(dir);
			return 0;
		}
	}
	closedir(dir);
	return -1;
}

static int test_bit(const unsigned long *bits, unsigned int bit)
{
	return !!(bits[bit / (8 * sizeof(*bits))] &
		 (1ul << (bit % (8 * sizeof(*bits)))));
}

static int find_key(void)
{
	int i;
	for (i = 0; i < 32; i++) {
		char path[64];
		unsigned long bits[(KEY_MAX + 8 * sizeof(long)) / (8 * sizeof(long))];
		int fd;
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		memset(bits, 0, sizeof(bits));
		if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) >= 0 &&
		    test_bit(bits, KEY_CODE))
			return fd;
		close(fd);
	}
	return -1;
}

static void bar(struct app *a, int y, const char *label, int value, int range,
		uint32_t fg, uint32_t dim, uint32_t white)
{
	char number[24];
	int center = 119, width = value * 70 / range;
	if (width > 70) width = 70;
	if (width < -70) width = -70;
	text(a, 8, y - 2, 1, white, label);
	rect(a, 35, y, 155, 7, dim);
	rect(a, center, y - 1, 1, 9, white);
	if (width >= 0)
		rect(a, center, y, width, 7, fg);
	else
		rect(a, center + width, y, -width, 7, fg);
	snprintf(number, sizeof(number), "%6d", value);
	text(a, 197, y - 2, 1, white, number);
}

static void draw(struct app *a, const int v[6], int sensor_ok)
{
	uint32_t bg = color(a, 7, 12, 20), white = color(a, 230, 238, 245);
	uint32_t cyan = color(a, 30, 210, 220), orange = color(a, 255, 150, 45);
	uint32_t dim = color(a, 30, 45, 58), green = color(a, 70, 220, 110);

	rect(a, 0, 0, a->var.xres, a->var.yres, bg);
	text(a, 7, 5, 2, cyan, "QUARK SENSOR");
	text(a, 180, 7, 1, a->hold ? orange : green, a->hold ? "HOLD" : "LIVE");
	if (!sensor_ok) {
		text(a, 55, 55, 2, orange, "NO MPU");
	} else {
		bar(a, 34, "AX", v[0], 16384, cyan, dim, white);
		bar(a, 49, "AY", v[1], 16384, cyan, dim, white);
		bar(a, 64, "AZ", v[2], 16384, cyan, dim, white);
		bar(a, 82, "GX", v[3], 2000, orange, dim, white);
		bar(a, 97, "GY", v[4], 2000, orange, dim, white);
		bar(a, 112, "GZ", v[5], 2000, orange, dim, white);
	}
	text(a, 7, 126, 1, white, "KEY: LIVE - HOLD");
}

static int open_fb(struct app *a)
{
	a->fb_fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
	if (a->fb_fd < 0 || ioctl(a->fb_fd, FBIOGET_FSCREENINFO, &a->fix) < 0 ||
	    ioctl(a->fb_fd, FBIOGET_VSCREENINFO, &a->var) < 0)
		return -1;
	if (a->var.bits_per_pixel != 16 && a->var.bits_per_pixel != 32) {
		errno = ENOTSUP;
		return -1;
	}
	a->fb_len = a->fix.smem_len;
	a->fb = mmap(NULL, a->fb_len, PROT_READ | PROT_WRITE, MAP_SHARED, a->fb_fd, 0);
	return a->fb == MAP_FAILED ? -1 : 0;
}

int main(void)
{
	struct app a = {.fb_fd = -1, .key_fd = -1, .tty_fd = -1};
	const char *attrs[] = {"in_accel_x_raw", "in_accel_y_raw", "in_accel_z_raw",
		"in_anglvel_x_raw", "in_anglvel_y_raw", "in_anglvel_z_raw"};
	int values[6] = {0}, shown[6] = {0}, sensor_ok = 0;
	struct pollfd pfd;

	signal(SIGINT, stop);
	signal(SIGTERM, stop);
	if (open_fb(&a) < 0) {
		perror("open /dev/fb0");
		return 1;
	}
	a.tty_fd = open("/dev/tty0", O_RDWR | O_CLOEXEC);
	if (a.tty_fd >= 0)
		ioctl(a.tty_fd, KDSETMODE, KD_GRAPHICS);
	if (find_iio(a.iio, sizeof(a.iio)) < 0)
		fprintf(stderr, "warning: MPU6050 IIO device not found\n");
	a.key_fd = find_key();
	if (a.key_fd < 0)
		fprintf(stderr, "warning: KEY_PROG1 input device not found\n");
	pfd.fd = a.key_fd;
	pfd.events = POLLIN;

	while (running) {
		int i, ready;
		if (a.iio[0] && !a.hold) {
			sensor_ok = 1;
			for (i = 0; i < 6; i++)
				if (read_int(a.iio, attrs[i], &values[i]) < 0)
					sensor_ok = 0;
			if (sensor_ok)
				memcpy(shown, values, sizeof(shown));
		}
		draw(&a, shown, sensor_ok);
		ready = poll(&pfd, a.key_fd >= 0 ? 1 : 0, 100);
		if (ready > 0 && (pfd.revents & POLLIN)) {
			struct input_event ev[8];
			ssize_t n = read(a.key_fd, ev, sizeof(ev));
			for (i = 0; n > 0 && i < n / (ssize_t)sizeof(ev[0]); i++)
				if (ev[i].type == EV_KEY && ev[i].code == KEY_CODE && ev[i].value == 1)
					a.hold = !a.hold;
		}
	}

	rect(&a, 0, 0, a.var.xres, a.var.yres, color(&a, 0, 0, 0));
	if (a.tty_fd >= 0) {
		ioctl(a.tty_fd, KDSETMODE, KD_TEXT);
		close(a.tty_fd);
	}
	munmap(a.fb, a.fb_len);
	close(a.fb_fd);
	if (a.key_fd >= 0) close(a.key_fd);
	return 0;
}
