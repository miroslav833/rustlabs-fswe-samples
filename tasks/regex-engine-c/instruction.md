# Build a regular-expression engine in C

You are to build a regular-expression matcher from scratch, in C, and the place for it is `/app/regex/`.

The build scaffold is already laid out for you, and your sources and headers all belong under `/app/regex/src/`. When you run `make` in `/app/regex/` it must build the executable `/app/regex/rgx`, so the output path and the target name are to be left as they stand. There is one file, `src/rgx.c`, which sets out the contract but does not build as it is shipped, for it carries an `#error` line; you are to replace the body of that file with a real engine and strike out the `#error` line, and then `make` will build.

## The rgx command

The engine is called as `rgx PATTERN STRING`, and the whole of its behaviour is told through the exit code it returns.

It returns 0 when PATTERN matches somewhere inside STRING, which is to say the search is unanchored, much as `grep -E` would search a single line of input. It returns 1 when the pattern does not match at all. It returns 2 when the pattern is malformed, meaning there is a syntax error in PATTERN, and in that case it prints nothing to stdout. STRING is a single line, and it never carries a newline within it. All matching is over bytes; there is no locale and no Unicode, and the input is to be taken as raw 8-bit characters and nothing more.

## The syntax you must support

There are several constructs to support, and they must all work when combined with one another.

There are literal characters, and `.` for any single character, and the anchors `^` and `$` for the start and the end of the whole string. There are character classes written `[...]`, with ranges such as `[a-z]`, with negation `[^...]`, and with a literal `]` allowed as the first member of a class, as in `[]x]`. There are the quantifiers `*`, `+`, and `?`, each applied to the element before it, and the bounded repetitions `{m}`, `{m,}`, and `{m,n}`. There is grouping with `(...)`, and alternation with `|`. There are backslash escapes for every metacharacter above, such as `\.`, `\*`, `\(`, `\[`, and `\\`.

Matching is only the question of whether the pattern matches; it is not capture. You do not report the contents of any group, only the match or the want of one.

You are not to call out to any outside regex tool, library, or binary, for the engine must be your own code throughout. The machine is offline.

## Notes

`make` must build with the system `cc` or `gcc`. The skeleton will not build until the engine is written, and a workspace that does not build scores zero. The pathological patterns are not graded, so there is no need to guard against a backtracking blow-up; still, each case runs under a short per-case timeout, and an exponential matcher may lose some of them.

Your score is the fraction of the hidden behaviour cases your `rgx` answers rightly, where the answer is match, no-match, or syntax-error, read off from the exit code. A partial engine earns partial credit.
