/* Starting skeleton for the regex engine.
 *
 * This file documents the command-line contract but does NOT implement a
 * matcher yet. As shipped it fails to build on purpose: replace the body
 * below with a real regular-expression engine (see /app/regex, the task
 * instructions, and the supported-syntax list) so that `make` produces a
 * working `rgx` at /app/regex/rgx.
 *
 * Contract recap:
 *   rgx PATTERN STRING
 *   exit 0 = PATTERN matches somewhere in STRING (unanchored)
 *   exit 1 = no match
 *   exit 2 = malformed PATTERN (print nothing)
 */
#include <stdio.h>

#error "rgx.c is a skeleton: implement the regex engine, then remove this #error line."

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    /* TODO: parse argv[1] as a POSIX ERE subset and match against argv[2].
     * Return 0 on match, 1 on no match, 2 on a malformed pattern. */
    return 2;
}
