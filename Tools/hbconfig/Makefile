# RomWBW HBIOS config tool (hbconfig) - single-file C tool.

CC       = gcc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11
TARGET   = hbconfig

all: $(TARGET)

$(TARGET): hbconfig.c
	$(CC) $(CFLAGS) -o $@ hbconfig.c

clean:
	rm -f $(TARGET) $(TARGET).exe

# convenience targets mirroring SPEC.md section 2; they cd into the HBIOS
# directory so Config/<platform>_<config>.asm resolves
ROM_PLATFORM ?=
ROM_CONFIG   ?=
HB := $(abspath $(CURDIR)/../../Source/HBIOS)

config: $(TARGET)
	cd "$(HB)" && "$(CURDIR)/$(TARGET)" -menu $(ROM_PLATFORM) $(ROM_CONFIG)
showconfig: $(TARGET)
	cd "$(HB)" && "$(CURDIR)/$(TARGET)" -show $(ROM_PLATFORM) $(ROM_CONFIG)
checkconfig: $(TARGET)
	cd "$(HB)" && "$(CURDIR)/$(TARGET)" -check $(ROM_PLATFORM) $(ROM_CONFIG)

.PHONY: all clean config showconfig checkconfig
