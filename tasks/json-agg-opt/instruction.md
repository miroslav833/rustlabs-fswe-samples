# Make a log-aggregation program faster

In `/app/agg/` there is a small C program, `agg`, which reads a stream of newline-delimited JSON records from stdin and prints an aggregation report to stdout. It is correct, but it is slow. Your work is to make it fast, and to leave what it prints untouched.

## Build and run

A `make` in `/app/agg/` builds `/app/agg/agg`, and the target name and the output path are to stay as they are. The program reads stdin through to the end of the input and writes its report to stdout, as in `cat events.jsonl | ./agg`.

## The input

Every input line is a flat JSON object, and it carries these fields, always in this order, with no nested objects and no stray whitespace.

```
{"ts": <integer>, "user": "<string>", "action": "<string>", "bytes": <integer>}
```

The `user` and the `action` are JSON strings, and they hold only ASCII letters, digits, `_` and `-`, so there are no escapes and no spaces within them. The `bytes` is a non-negative integer. There may be blank lines, and there may be a missing trailing newline, and both are to be handled exactly as the reference handles them, which is to say the blank lines are skipped.

## The output, which must match byte for byte

The report comes in two sections, and they come in this order.

First there is the line `BY_ACTION`, and after it one line for each distinct `action`, sorted by the action name ascending in byte order, each line written `<action>\t<count>\t<total_bytes>`. Then there is the line `BY_USER`, and after it one line for each distinct `user`, sorted by total_bytes descending, the ties broken by the user name ascending, each line written `<user>\t<count>\t<total_bytes>`.

The counts and the byte totals are decimal integers with no leading zeros, and there is a single trailing newline at the end of the whole report. The program that is already there prints the correct report, so its exact output is the specification, and you are to treat it so.

## What you must do

Make `agg` faster, and keep its output the same on every input. You may rewrite the program however you please, in its parsing, its data structures, or its I/O, so long as three things hold: it still builds with `make` to `/app/agg/agg`; it reads the same stdin and writes the same report; and it uses only the C standard library and POSIX, with no outside libraries, no network, and no spawning of other processes.

## How you are scored

Your score has two gates, and then a measure of speed.

There is a correctness gate. Your program's output must match the reference output exactly over a battery of hidden inputs, and that battery holds the awkward cases: empty input, a single record, many duplicate keys, large byte values, blank lines, and a missing trailing newline. Any mismatch scores 0.

Then there is speed. Once the output is correct, the score follows how much faster your program runs than the original baseline on a large hidden input, taken as the wall-clock speedup `S = baseline_time / your_time`, best of several runs. An `S` below 2.0 scores 0.0, so a program left unoptimized or barely touched scores zero. An `S` of at least 2.0 scores 0.4, an `S` of at least 4.0 scores 0.7, and an `S` of at least 8.0 scores 1.0.

The baseline time is measured from the original program inside the same verifier run, so it is calibrated to the grading machine and not to your own box.
