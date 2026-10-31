# RomWBW HBIOS config tool (hbconfig) - single-file C tool.

CC       = gcc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11
TARGET   = hbconfig

all: $(TARGET)

$(TARGET): hbconfig.c
	$(CC) $(CFLAGS) -o $@ hbconfig.c

clean:
	rm -f $(TARGET) $(TARGET).exe

.PHONY: all clean
