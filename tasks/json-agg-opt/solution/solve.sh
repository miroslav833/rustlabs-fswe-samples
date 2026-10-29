#!/usr/bin/env bash
set -eu
# Replace the slow baseline with an optimized, byte-compatible implementation.
cat > /app/agg/agg.c <<'CSRC'
/* Optimized log aggregator: hash tables + buffered block I/O + a hand parser.
 * Output is byte-identical to the baseline. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>

typedef struct Ent {
    char *key; int klen;
    long long count, bytes;
    struct Ent *next;
} Ent;

typedef struct {
    Ent **buckets; size_t nb;
    Ent **items; size_t nitems, cap;
} Table;

static void tab_init(Table *t, size_t nb) {
    t->nb = nb;
    t->buckets = calloc(nb, sizeof(Ent *));
    t->items = NULL; t->nitems = 0; t->cap = 0;
}

static uint64_t fnv(const char *s, int len) {
    uint64_t h = 1469598103934665603ULL;
    for (int i = 0; i < len; i++) { h ^= (unsigned char)s[i]; h *= 1099511628211ULL; }
    return h;
}

static Ent *tab_get(Table *t, const char *k, int klen) {
    uint64_t h = fnv(k, klen) & (t->nb - 1);
    for (Ent *e = t->buckets[h]; e; e = e->next)
        if (e->klen == klen && memcmp(e->key, k, klen) == 0) return e;
    Ent *e = malloc(sizeof(Ent));
    e->key = malloc(klen + 1); memcpy(e->key, k, klen); e->key[klen] = 0;
    e->klen = klen; e->count = 0; e->bytes = 0;
    e->next = t->buckets[h]; t->buckets[h] = e;
    if (t->nitems == t->cap) { t->cap = t->cap ? t->cap * 2 : 1024; t->items = realloc(t->items, t->cap * sizeof(Ent *)); }
    t->items[t->nitems++] = e;
    return e;
}

static Table actions, users;

static int cmp_action(const void *a, const void *b) {
    const Ent *x = *(const Ent **)a, *y = *(const Ent **)b;
    return strcmp(x->key, y->key);
}
static int cmp_user(const void *a, const void *b) {
    const Ent *x = *(const Ent **)a, *y = *(const Ent **)b;
    if (x->bytes != y->bytes) return (y->bytes > x->bytes) ? 1 : -1;
    return strcmp(x->key, y->key);
}

/* Parse one line. Format is fixed-order:
 * {"ts": N, "user": "U", "action": "A", "bytes": N}
 * but we locate fields by key to tolerate spacing like the baseline. */
static const char *find_val(const char *p, const char *end, const char *key, int klen) {
    /* search for "key" */
    for (const char *q = p; q + klen + 2 <= end; q++) {
        if (q[0] == '"' && memcmp(q + 1, key, klen) == 0 && q[1 + klen] == '"')
            return q + klen + 2;
    }
    return NULL;
}

int main(void) {
    tab_init(&actions, 1 << 12);
    tab_init(&users, 1 << 16);

    /* slurp all stdin */
    size_t cap = 1 << 20, len = 0;
    char *buf = malloc(cap);
    ssize_t r;
    while ((r = read(0, buf + len, cap - len)) > 0) {
        len += r;
        if (len == cap) { cap *= 2; buf = realloc(buf, cap); }
    }

    char *p = buf, *bend = buf + len;
    while (p < bend) {
        char *nl = memchr(p, '\n', bend - p);
        char *lstart = p, *lend = nl ? nl : bend;
        p = nl ? nl + 1 : bend;
        if (lend == lstart) continue; /* blank line */

        const char *up = find_val(lstart, lend, "user", 4);
        const char *ap = find_val(lstart, lend, "action", 6);
        const char *bp = find_val(lstart, lend, "bytes", 5);
        if (!up || !ap || !bp) continue;
        while (*up == ' ' || *up == ':') up++;
        if (*up != 0x22) continue;
        up++;
        const char *ue = memchr(up, '"', lend - up); if (!ue) continue;
        while (*ap == ' ' || *ap == ':') ap++;
        if (*ap != '"') continue;
        ap++;
        const char *ae = memchr(ap, '"', lend - ap); if (!ae) continue;
        while (*bp == ' ' || *bp == ':') bp++;
        long long bytes = 0; const char *bq = bp;
        if (bq >= lend || *bq < '0' || *bq > '9') continue;
        while (bq < lend && *bq >= '0' && *bq <= '9') { bytes = bytes * 10 + (*bq - '0'); bq++; }

        Ent *ea = tab_get(&actions, ap, (int)(ae - ap));
        ea->count++; ea->bytes += bytes;
        Ent *eu = tab_get(&users, up, (int)(ue - up));
        eu->count++; eu->bytes += bytes;
    }

    qsort(actions.items, actions.nitems, sizeof(Ent *), cmp_action);
    qsort(users.items, users.nitems, sizeof(Ent *), cmp_user);

    /* buffered output */
    char *out = malloc(1 << 20); size_t ocap = 1 << 20, olen = 0;
    #define EMIT(fmt, ...) do { \
        if (olen + 512 > ocap) { ocap *= 2; out = realloc(out, ocap); } \
        olen += snprintf(out + olen, ocap - olen, fmt, __VA_ARGS__); } while (0)
    if (olen + 16 > ocap) { ocap *= 2; out = realloc(out, ocap); }
    olen += snprintf(out + olen, ocap - olen, "BY_ACTION\n");
    for (size_t i = 0; i < actions.nitems; i++)
        EMIT("%s\t%lld\t%lld\n", actions.items[i]->key, actions.items[i]->count, actions.items[i]->bytes);
    if (olen + 16 > ocap) { ocap *= 2; out = realloc(out, ocap); }
    olen += snprintf(out + olen, ocap - olen, "BY_USER\n");
    for (size_t i = 0; i < users.nitems; i++)
        EMIT("%s\t%lld\t%lld\n", users.items[i]->key, users.items[i]->count, users.items[i]->bytes);
    fwrite(out, 1, olen, stdout);
    return 0;
}

CSRC
cd /app/agg
make >/dev/null 2>&1 || make
printf '{"ts": 1, "user": "u", "action": "a", "bytes": 5}\n' | ./agg >/dev/null && echo "oracle: optimized agg built"
