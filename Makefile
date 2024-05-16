.PHONY: all clean linux windows

ZIG = zig
ZFLAGS = -freference-trace

version ?= 0.0.0

linux:
	$(ZIG) build $(ZFLAGS) \
	-Dtarget=x86_64-linux-gnu \
	-Doptimize=ReleaseSmall \
	-Dplatform=x86_64-linux \
	-Drelease_version=$(version)

windows:
	$(ZIG) build $(ZFLAGS) \
	-Dtarget=x86_64-windows-gnu \
	-Doptimize=ReleaseSmall \
	-Dplatform=x86_64-windows \
	-Drelease_version=$(version)

all: linux windows

clean:
	rm -rf zig-out/*
	rm -rf zig-cache/*