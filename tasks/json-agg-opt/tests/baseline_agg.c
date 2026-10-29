/* Log aggregator (BASELINE, correct but intentionally slow).
 *
 * Reads newline-delimited JSON records from stdin:
 *   {"ts": <int>, "user": "<str>", "action": "<str>", "bytes": <int>}
 * Writes a BY_ACTION report (sorted by action asc) and a BY_USER report
 * (sorted by total_bytes desc, then user asc).
 *
 * This is the specification of the output. You may rewrite it entirely for
 * speed as long as the output stays byte-identical.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char *key; long long count; long long bytes; } Agg;

static Agg *acts = NULL; static int nacts = 0;
static Agg *users = NULL; static int nusers = 0;

/* O(n) linear find/insert — slow on purpose. */
static int find_or_add(Agg **arr, int *n, const char *key) {
    for (int i = 0; i < *n; i++) {
        if (strcmp((*arr)[i].key, key) == 0) return i;
    }
    *arr = realloc(*arr, sizeof(Agg) * (*n + 1));
    size_t klen = strlen(key);
    (*arr)[*n].key = malloc(klen + 1);
    memcpy((*arr)[*n].key, key, klen + 1);
    (*arr)[*n].count = 0;
    (*arr)[*n].bytes = 0;
    return (*n)++;
}

/* Read one logical line via getchar() — slow on purpose. Returns -1 at EOF
 * with no data, else the length. */
static int read_line(char *buf, int cap) {
    int len = 0, c;
    while ((c = getchar()) != EOF) {
        if (c == '\n') { buf[len] = 0; return len; }
        if (len < cap - 1) buf[len++] = (char)c;
    }
    if (len == 0) return -1;
    buf[len] = 0;
    return len;
}

/* Extract the string value of a "field":"value" pair. */
static int get_str(const char *line, const char *field, char *out, int cap) {
    char pat[64];
    snprintf(pat, sizeof(pat), "\"%s\"", field);
    const char *p = strstr(line, pat);
    if (!p) return 0;
    p += strlen(pat);
    while (*p == ' ' || *p == ':') p++;
    if (*p != '"') return 0;
    p++;
    int len = 0;
    while (*p && *p != '"' && len < cap - 1) out[len++] = *p++;
    out[len] = 0;
    return 1;
}

static int get_int(const char *line, const char *field, long long *out) {
    char pat[64];
    snprintf(pat, sizeof(pat), "\"%s\"", field);
    const char *p = strstr(line, pat);
    if (!p) return 0;
    p += strlen(pat);
    while (*p == ' ' || *p == ':') p++;
    char *end;
    long long v = strtoll(p, &end, 10);
    if (end == p) return 0;
    *out = v;
    return 1;
}

static int cmp_action(const void *a, const void *b) {
    return strcmp(((const Agg *)a)->key, ((const Agg *)b)->key);
}
static int cmp_user(const void *a, const void *b) {
    const Agg *x = a, *y = b;
    if (x->bytes != y->bytes) return (y->bytes > x->bytes) ? 1 : -1;
    return strcmp(x->key, y->key);
}

int main(void) {
    static char line[65536];
    char user[4096], action[4096];
    long long b;
    int len;
    while ((len = read_line(line, sizeof(line))) != -1) {
        if (len == 0) continue; /* skip blank lines */
        if (!get_str(line, "user", user, sizeof(user))) continue;
        if (!get_str(line, "action", action, sizeof(action))) continue;
        if (!get_int(line, "bytes", &b)) continue;
        int ai = find_or_add(&acts, &nacts, action);
        acts[ai].count++; acts[ai].bytes += b;
        int ui = find_or_add(&users, &nusers, user);
        users[ui].count++; users[ui].bytes += b;
    }
    qsort(acts, nacts, sizeof(Agg), cmp_action);
    qsort(users, nusers, sizeof(Agg), cmp_user);
    /* Build output in a buffer, write once. */
    printf("BY_ACTION\n");
    for (int i = 0; i < nacts; i++)
        printf("%s\t%lld\t%lld\n", acts[i].key, acts[i].count, acts[i].bytes);
    printf("BY_USER\n");
    for (int i = 0; i < nusers; i++)
        printf("%s\t%lld\t%lld\n", users[i].key, users[i].count, users[i].bytes);
    return 0;
}
