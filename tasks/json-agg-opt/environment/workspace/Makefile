CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra
agg: $(wildcard *.c)
	$(CC) $(CFLAGS) -o agg $(wildcard *.c)
clean:
	rm -f agg
.PHONY: clean
