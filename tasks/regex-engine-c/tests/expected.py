"""Reference ERE engine — the ground truth for grading.

Returns the expected rgx exit code for a (pattern, string):
  0 = match (unanchored substring search)
  1 = no match
  2 = malformed pattern (syntax error)

This is a recursive-descent parser to an AST plus a backtracking matcher.
It is deliberately independent of Python's `re` so the semantics are exactly
the POSIX ERE subset the task specifies. Only the standard library is used.
"""
from __future__ import annotations


class ParseError(Exception):
    pass


# ---- AST nodes as tuples: (kind, ...) ----
# ('lit', ch) ('dot',) ('class', negated, [(lo,hi),...])
# ('star', node) ('plus', node) ('opt', node) ('rep', node, m, n|None)
# ('seq', [nodes]) ('alt', [branches]) ('bol',) ('eol',)


class Parser:
    def __init__(self, pat: str):
        self.s = pat
        self.i = 0
        self.n = len(pat)

    def peek(self):
        return self.s[self.i] if self.i < self.n else None

    def next(self):
        c = self.s[self.i]
        self.i += 1
        return c

    def parse(self):
        node = self.parse_alt()
        if self.i != self.n:
            raise ParseError(f"trailing input at {self.i}")
        return node

    def parse_alt(self):
        branches = [self.parse_seq()]
        while self.peek() == "|":
            self.next()
            branches.append(self.parse_seq())
        if len(branches) == 1:
            return branches[0]
        return ("alt", branches)

    def parse_seq(self):
        items = []
        while True:
            c = self.peek()
            if c is None or c in "|)":
                break
            items.append(self.parse_quant())
        return ("seq", items)

    def parse_quant(self):
        atom = self.parse_atom()
        c = self.peek()
        if c == "*":
            self.next()
            return self._nostack(("star", atom))
        if c == "+":
            self.next()
            return self._nostack(("plus", atom))
        if c == "?":
            self.next()
            return self._nostack(("opt", atom))
        if c == "{":
            return self.parse_brace(atom)
        return atom

    def _nostack(self, node):
        # Reject a quantifier applied to another quantifier, e.g. a**, a+?.
        c = self.peek()
        if c in ("*", "+", "?", "{"):
            raise ParseError("stacked quantifier")
        return node

    def parse_brace(self, atom):
        # at '{'
        self.next()
        digits1 = ""
        while self.peek() is not None and self.peek().isdigit():
            digits1 += self.next()
        m = None
        n: int | None = None
        if self.peek() == "}":
            self.next()
            if digits1 == "":
                raise ParseError("empty {}")
            m = int(digits1)
            n = m
        elif self.peek() == ",":
            self.next()
            digits2 = ""
            while self.peek() is not None and self.peek().isdigit():
                digits2 += self.next()
            if self.peek() != "}":
                raise ParseError("unterminated {")
            self.next()
            if digits1 == "":
                raise ParseError("missing lower bound")  # {,n} not allowed
            m = int(digits1)
            n = int(digits2) if digits2 != "" else None
        else:
            raise ParseError("bad brace")
        if n is not None and n < m:
            raise ParseError("{m,n} with n<m")
        return self._nostack(("rep", atom, m, n))

    def parse_atom(self):
        c = self.peek()
        if c is None:
            raise ParseError("expected atom")
        if c in ("*", "+", "?"):
            raise ParseError("quantifier with no atom")
        if c == "(":
            self.next()
            inner = self.parse_alt()
            if self.peek() != ")":
                raise ParseError("missing )")
            self.next()
            return inner
        if c == ")":
            raise ParseError("unexpected )")
        if c == "^":
            self.next()
            return ("bol",)
        if c == "$":
            self.next()
            return ("eol",)
        if c == ".":
            self.next()
            return ("dot",)
        if c == "[":
            return self.parse_class()
        if c == "\\":
            self.next()
            e = self.peek()
            if e is None:
                raise ParseError("dangling backslash")
            self.next()
            return ("lit", e)
        if c == "]":
            # a bare ] outside a class is an ordinary literal in ERE
            self.next()
            return ("lit", "]")
        if c == "}":
            self.next()
            return ("lit", "}")
        self.next()
        return ("lit", c)

    def parse_class(self):
        self.next()  # '['
        negated = False
        if self.peek() == "^":
            self.next()
            negated = True
        ranges = []
        first = True
        members = []
        while True:
            c = self.peek()
            if c is None:
                raise ParseError("unterminated class")
            if c == "]" and not first:
                self.next()
                break
            first = False
            self.next()
            members.append(c)
        # resolve ranges from the raw member list
        k = 0
        while k < len(members):
            ch = members[k]
            if k + 2 < len(members) + 0 and k + 1 < len(members) and members[k + 1] == "-" and k + 2 < len(members):
                lo = ch
                hi = members[k + 2]
                if ord(hi) < ord(lo):
                    raise ParseError("bad class range")
                ranges.append((lo, hi))
                k += 3
            else:
                ranges.append((ch, ch))
                k += 1
        if not ranges:
            raise ParseError("empty class")
        return ("class", negated, ranges)


# ---- matcher: returns set of end positions reachable matching node from pos ----
def match_node(node, s, pos):
    kind = node[0]
    if kind == "seq":
        ends = {pos}
        for item in node[1]:
            nxt = set()
            for p in ends:
                nxt |= match_node(item, s, p)
            ends = nxt
            if not ends:
                return set()
        return ends
    if kind == "alt":
        out = set()
        for br in node[1]:
            out |= match_node(br, s, pos)
        return out
    if kind == "lit":
        if pos < len(s) and s[pos] == node[1]:
            return {pos + 1}
        return set()
    if kind == "dot":
        if pos < len(s):
            return {pos + 1}
        return set()
    if kind == "class":
        _, neg, ranges = node
        if pos < len(s):
            ch = s[pos]
            inside = any(lo <= ch <= hi for lo, hi in ranges)
            if inside != neg:
                return {pos + 1}
        return set()
    if kind == "bol":
        return {pos} if pos == 0 else set()
    if kind == "eol":
        return {pos} if pos == len(s) else set()
    if kind == "star":
        return rep_match(node[1], s, pos, 0, None)
    if kind == "plus":
        return rep_match(node[1], s, pos, 1, None)
    if kind == "opt":
        return rep_match(node[1], s, pos, 0, 1)
    if kind == "rep":
        return rep_match(node[1], s, pos, node[2], node[3])
    raise AssertionError(kind)


def rep_match(sub, s, pos, m, n):
    # positions reachable after matching sub between m and n times (n None = inf)
    reachable = set()
    current = {pos}
    count = 0
    if m == 0:
        reachable.add(pos)
    while current:
        nxt = set()
        for p in current:
            nxt |= match_node(sub, s, p)
        # avoid infinite loop on empty matches
        nxt -= current if count > len(s) else set()
        count += 1
        if not nxt:
            break
        if count >= m:
            reachable |= nxt
        current = nxt
        if n is not None and count >= n:
            break
        if count > len(s) + 1:
            break
    return reachable


def expected_exit(pattern: str, string: str) -> int:
    try:
        ast = Parser(pattern).parse()
    except ParseError:
        return 2
    # unanchored: try every start position
    for start in range(len(string) + 1):
        ends = match_node(ast, string, start)
        if ends:
            return 0
        # if pattern begins with ^, only start 0 is meaningful, but trying
        # others is harmless because bol fails there.
    return 1
