#!/usr/bin/env bash
set -eu
# Replace the stub with a full ERE engine, then build it.
cat > /app/regex/src/rgx.c <<'CSRC'
/* Reference ERE-subset engine in C.
 * Recursive-descent parser to an AST + backtracking matcher.
 * Exit 0 = match (unanchored), 1 = no match, 2 = syntax error. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { N_LIT, N_DOT, N_CLASS, N_SEQ, N_ALT, N_STAR, N_PLUS,
               N_OPT, N_REP, N_BOL, N_EOL } Kind;

typedef struct Node Node;
struct Node {
    Kind kind;
    unsigned char ch;           /* N_LIT */
    int neg;                    /* N_CLASS */
    unsigned char cls[256];     /* N_CLASS membership */
    Node **kids; int nkids;     /* N_SEQ, N_ALT */
    Node *sub;                  /* quantifiers */
    int m, n; int n_inf;        /* N_REP: {m,n}; n_inf=1 means unbounded */
};

/* ---- parser ---- */
static const char *P;      /* cursor */
static const char *Pend;
static int parse_error;

static Node *new_node(Kind k){ Node*x=calloc(1,sizeof(Node)); x->kind=k; return x; }
static void add_kid(Node*p, Node*c){ p->kids=realloc(p->kids,sizeof(Node*)*(p->nkids+1)); p->kids[p->nkids++]=c; }

static int peek(void){ return (P<Pend)? (unsigned char)*P : -1; }
static int adv(void){ return (unsigned char)*P++; }

static Node *parse_alt(void);

static Node *parse_class(void){
    /* at '[' */
    adv();
    Node *x=new_node(N_CLASS);
    int neg=0;
    if(peek()=='^'){ adv(); neg=1; }
    x->neg=neg;
    int first=1, any=0;
    unsigned char prev=0; int have_prev=0; int pending_range=0;
    while(1){
        int c=peek();
        if(c==-1){ parse_error=1; return x; }
        if(c==']' && !first){ adv(); break; }
        first=0;
        adv();
        if(c=='-' && have_prev && peek()!=']' && peek()!=-1){
            pending_range=1;
            continue;
        }
        if(pending_range){
            unsigned char lo=prev, hi=(unsigned char)c;
            if(hi<lo){ parse_error=1; return x; }
            for(int i=lo;i<=hi;i++) x->cls[i]=1;
            pending_range=0; have_prev=0; any=1;
            continue;
        }
        x->cls[(unsigned char)c]=1; any=1;
        prev=(unsigned char)c; have_prev=1;
    }
    if(pending_range){ x->cls[(unsigned char)'-']=1; }
    if(!any){ parse_error=1; }
    return x;
}

static Node *parse_atom(void){
    int c=peek();
    if(c==-1){ parse_error=1; return new_node(N_SEQ); }
    if(c=='*'||c=='+'||c=='?'){ parse_error=1; return new_node(N_SEQ); }
    if(c=='('){
        adv();
        Node *inner=parse_alt();
        if(peek()!=')'){ parse_error=1; return inner; }
        adv();
        return inner;
    }
    if(c==')'){ parse_error=1; return new_node(N_SEQ); }
    if(c=='^'){ adv(); return new_node(N_BOL); }
    if(c=='$'){ adv(); return new_node(N_EOL); }
    if(c=='.'){ adv(); return new_node(N_DOT); }
    if(c=='['){ return parse_class(); }
    if(c=='\\'){
        adv();
        if(peek()==-1){ parse_error=1; return new_node(N_SEQ); }
        Node *x=new_node(N_LIT); x->ch=(unsigned char)adv(); return x;
    }
    if(c==']'){ adv(); Node*x=new_node(N_LIT); x->ch=']'; return x; }
    if(c=='}'){ adv(); Node*x=new_node(N_LIT); x->ch='}'; return x; }
    Node *x=new_node(N_LIT); x->ch=(unsigned char)adv(); return x;
}

static void no_stack(void){
    int c=peek();
    if(c=='*'||c=='+'||c=='?'||c=='{'){ parse_error=1; }
}

static Node *parse_brace(Node *atom){
    adv(); /* '{' */
    int c=peek();
    char d1[32]; int l1=0;
    while(peek()>='0'&&peek()<='9'){ if(l1<31) d1[l1++]=(char)adv(); else adv(); }
    d1[l1]=0;
    Node *r=new_node(N_REP); r->sub=atom;
    if(peek()=='}'){
        adv();
        if(l1==0){ parse_error=1; return r; }
        r->m=atoi(d1); r->n=r->m; r->n_inf=0;
    } else if(peek()==','){
        adv();
        char d2[32]; int l2=0;
        while(peek()>='0'&&peek()<='9'){ if(l2<31) d2[l2++]=(char)adv(); else adv(); }
        d2[l2]=0;
        if(peek()!='}'){ parse_error=1; return r; }
        adv();
        if(l1==0){ parse_error=1; return r; }  /* {,n} disallowed */
        r->m=atoi(d1);
        if(l2==0){ r->n_inf=1; } else { r->n=atoi(d2); r->n_inf=0; }
    } else { parse_error=1; return r; }
    if(!r->n_inf && r->n < r->m){ parse_error=1; }
    (void)c;
    no_stack();
    return r;
}

static Node *parse_quant(void){
    Node *atom=parse_atom();
    int c=peek();
    if(c=='*'){ adv(); no_stack(); Node*x=new_node(N_STAR); x->sub=atom; return x; }
    if(c=='+'){ adv(); no_stack(); Node*x=new_node(N_PLUS); x->sub=atom; return x; }
    if(c=='?'){ adv(); no_stack(); Node*x=new_node(N_OPT); x->sub=atom; return x; }
    if(c=='{'){ return parse_brace(atom); }
    return atom;
}

static Node *parse_seq(void){
    Node *s=new_node(N_SEQ);
    while(1){
        int c=peek();
        if(c==-1||c=='|'||c==')') break;
        add_kid(s, parse_quant());
    }
    return s;
}

static Node *parse_alt(void){
    Node *first=parse_seq();
    if(peek()!='|') return first;
    Node *a=new_node(N_ALT);
    add_kid(a, first);
    while(peek()=='|'){ adv(); add_kid(a, parse_seq()); }
    return a;
}

/* ---- matcher: continuation-passing backtracker ----
 * match(node, s, len, pos, cont) tries to match node starting at pos,
 * calling cont(end) for each possible end; returns 1 if any cont succeeds. */
typedef struct { const char *s; int len; } Ctx;

static int match_node(Node*, Ctx*, int, int (*)(int,void*), void*);

typedef struct { Node **kids; int nk; int idx; int (*cont)(int,void*); void*ca; Ctx*ctx; } SeqK;

static int seq_cont(int pos, void *arg){
    SeqK *k=arg;
    if(k->idx==k->nk) return k->cont(pos, k->ca);
    SeqK next=*k; next.idx=k->idx+1;
    return match_node(k->kids[k->idx], k->ctx, pos, seq_cont, &next);
}

typedef struct { Node *sub; int min, max; int inf; int (*cont)(int,void*); void*ca; Ctx*ctx; } RepK;


typedef struct { RepK *rk; int count; int startpos; } RepState;

static int rep_try(RepK *rk, int count, int pos);

static int rep_more_cont(int pos, void *arg){
    RepState *st=arg;
    /* matched one more instance of sub, now at pos; guard empty-match loops */
    if(pos==st->startpos) return 0; /* empty progress, stop expanding */
    return rep_try(st->rk, st->count+1, pos);
}

static int rep_try(RepK *rk, int count, int pos){
    /* Greedy: if we can take more (within max), try that first; then accept. */
    int can_more = rk->inf ? 1 : (count < rk->max);
    if(count >= rk->min){
        /* also allow stopping here, but greedy => try more first */
    }
    if(can_more){
        RepState st; st.rk=rk; st.count=count; st.startpos=pos;
        if(match_node(rk->sub, rk->ctx, pos, rep_more_cont, &st)) return 1;
    }
    if(count >= rk->min){
        if(rk->cont(pos, rk->ca)) return 1;
    }
    return 0;
}

static int match_node(Node *nd, Ctx *ctx, int pos, int (*cont)(int,void*), void *ca){
    switch(nd->kind){
    case N_LIT:
        if(pos<ctx->len && (unsigned char)ctx->s[pos]==nd->ch) return cont(pos+1, ca);
        return 0;
    case N_DOT:
        if(pos<ctx->len) return cont(pos+1, ca);
        return 0;
    case N_CLASS:
        if(pos<ctx->len){
            int in=nd->cls[(unsigned char)ctx->s[pos]];
            if(in != nd->neg) return cont(pos+1, ca);
        }
        return 0;
    case N_BOL:
        if(pos==0) return cont(pos, ca);
        return 0;
    case N_EOL:
        if(pos==ctx->len) return cont(pos, ca);
        return 0;
    case N_SEQ: {
        SeqK k; k.kids=nd->kids; k.nk=nd->nkids; k.idx=0; k.cont=cont; k.ca=ca; k.ctx=ctx;
        return seq_cont(pos, &k);
    }
    case N_ALT:
        for(int i=0;i<nd->nkids;i++)
            if(match_node(nd->kids[i], ctx, pos, cont, ca)) return 1;
        return 0;
    case N_STAR: { RepK rk={nd->sub,0,0,1,cont,ca,ctx}; return rep_try(&rk,0,pos); }
    case N_PLUS: { RepK rk={nd->sub,1,0,1,cont,ca,ctx}; return rep_try(&rk,0,pos); }
    case N_OPT:  { RepK rk={nd->sub,0,1,0,cont,ca,ctx}; return rep_try(&rk,0,pos); }
    case N_REP:  { RepK rk={nd->sub,nd->m,nd->n,nd->n_inf,cont,ca,ctx}; return rep_try(&rk,0,pos); }
    }
    return 0;
}

static int accept_cont(int pos, void *arg){ (void)pos; (void)arg; return 1; }

int main(int argc, char **argv){
    if(argc!=3) return 2;
    const char *pat=argv[1];
    const char *str=argv[2];
    P=pat; Pend=pat+strlen(pat); parse_error=0;
    Node *ast=parse_alt();
    if(parse_error || P!=Pend) return 2;
    Ctx ctx; ctx.s=str; ctx.len=(int)strlen(str);
    for(int start=0; start<=ctx.len; start++){
        if(match_node(ast, &ctx, start, accept_cont, NULL)) return 0;
    }
    return 1;
}

CSRC
cd /app/regex
make >/dev/null 2>&1 || make
./rgx "abc" "abc" >/dev/null 2>&1 && echo "oracle: rgx built and matches sample"
