CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra
rgx: $(wildcard src/*.c)
	$(CC) $(CFLAGS) -o rgx $(wildcard src/*.c)
clean:
	rm -f rgx
.PHONY: clean
