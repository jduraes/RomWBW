/*
;==================================================================================================
;   ROMWBW HBIOS CONFIG TOOL (HBCONFIG)
;   TOOL AUTHOR: MIGUEL D.  SEE RomWBW ISSUE #722 FOR DESIGN SPEC (RULES.MD / SPEC.MD)
;   THIS TOOL WAS DEVELOPED WITH AI ASSISTANCE (CLAUDE), PER WAYNE'S APPROVAL IN ISSUE #722.
;==================================================================================================
*/

/*
 * hbconfig.c - RomWBW HBIOS configuration tool
 *
 * Modes (per SPEC.md section 2):
 *   hbconfig -show  <config-file>            - non-interactive diff report
 *   hbconfig -show  <platform> <config>      - same, locating Config/<plt>_<cfg>.asm
 *   hbconfig -check <config-file>            - verify ;@DEPENDS rules, no menu
 *   hbconfig -check <platform> <config>
 *
 * The cascade (SPEC.md section 3): a config file is read the way the
 * assembler reads it, top to bottom, #INCLUDE expanded in place, last
 * .EQU/.SET of a name wins.  The inherited value of a setting is what the
 * cascade produces with the target file's own .SET lines left out.
 *
 * -show prints every setting whose effective value differs from
 * cfg_MASTER.asm, with the effective value, the master value, and the
 * file that set it.
 *
 * -check evaluates every ;@DEPENDS tag (RULES.md section 4).  On a
 * TRUE/FALSE setting the expression must hold whenever the setting is
 * TRUE; on any other setting it must always hold.  A config that passes
 * the check should build.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>

#define MAXTOK   256

/* forward decls */
static void die(const char *msg);

/*==================================================================================================
 * SETTING RECORD
 *=================================================================================================*/

typedef struct {
    char  *name;        /* setting name (uppercase)          */
    char  *value;       /* value expression, trimmed         */
    char  *comment;     /* help text (after first ';')       */
    char  *file;        /* defining file                     */
    int    line;        /* line number in defining file      */
    int    in_master;   /* record came from the master file  */
    int    in_target;   /* record came from the target file  */
    char **depends;     /* ;@DEPENDS expressions             */
    int    ndep, depcap;
    char  *xhelp;       /* ;@HELP lines, newline-joined      */
} Setting;

typedef struct {
    Setting  *v;
    int       n, cap;
} SList;

typedef struct {
    const char *target_path;    /* file the user named            */
    SList       recs;           /* all .EQU/.SET records in order */
    SList       consts;         /* pick-list constants (std.asm)  */
    char        master_path[1024];
    int         error;
} ParseCtx;

static SList *ctx_consts(ParseCtx *ctx) { return &ctx->consts; }

static char *xstrdup(const char *s)
{
    char *p = malloc(strlen(s) + 1);
    if (!p) die("out of memory");
    strcpy(p, s);
    return p;
}

static void *xmalloc(size_t n)
{
    void *p = malloc(n);
    if (!p) die("out of memory");
    return p;
}

static void slist_push(SList *sl, Setting s)
{
    if (sl->n == sl->cap) {
        sl->cap = sl->cap ? sl->cap * 2 : 64;
        sl->v = realloc(sl->v, sl->cap * sizeof(Setting));
        if (!sl->v) die("out of memory");
    }
    sl->v[sl->n++] = s;
}

static void setting_add_dep(Setting *s, const char *expr)
{
    if (s->ndep == s->depcap) {
        s->depcap = s->depcap ? s->depcap * 2 : 4;
        s->depends = realloc(s->depends, s->depcap * sizeof(char *));
        if (!s->depends) die("out of memory");
    }
    s->depends[s->ndep++] = xstrdup(expr);
}

static void setting_add_help(Setting *s, const char *text)
{
    size_t old = s->xhelp ? strlen(s->xhelp) : 0;
    size_t add = strlen(text);
    s->xhelp = realloc(s->xhelp, old + add + 2);
    if (!s->xhelp) die("out of memory");
    memcpy(s->xhelp + old, text, add);
    s->xhelp[old + add] = '\n';
    s->xhelp[old + add + 1] = '\0';
}

static void die(const char *msg)
{
    fprintf(stderr, "hbconfig: %s\n", msg);
    exit(1);
}

/*==================================================================================================
 * STRING UTILITIES
 *=================================================================================================*/

static char *trim(char *s)
{
    char *e;
    while (isspace((unsigned char)*s)) s++;
    e = s + strlen(s);
    while (e > s && isspace((unsigned char)e[-1])) *--e = '\0';
    return s;
}

/* uppercase in place */
static void upper(char *s)
{
    for (; *s; s++) *s = (char)toupper((unsigned char)*s);
}

/* compare two value expressions: case-insensitive, whitespace-insensitive */
static int value_eq(const char *a, const char *b)
{
    while (*a && *b) {
        while (isspace((unsigned char)*a)) a++;
        while (isspace((unsigned char)*b)) b++;
        if (!*a || !*b) break;
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++; b++;
    }
    while (isspace((unsigned char)*a)) a++;
    while (isspace((unsigned char)*b)) b++;
    return *a == '\0' && *b == '\0';
}

/*==================================================================================================
 * FILE STACK / PARSER
 *=================================================================================================*/

static void check_ascii(const char *line, int lineno, const char *path)
{
    const unsigned char *p = (const unsigned char *)line;
    while (*p) {
        if (*p > 127) {
            fprintf(stderr, "hbconfig: non-ASCII character 0x%02X at %s:%d\n", *p, path, lineno);
            exit(1);
        }
        p++;
    }
}

/* resolve an #INCLUDE name relative to the including file's directory,
 * then the parent directory (RomWBW's Config/ -> HBIOS/ convention),
 * then cwd-relative */
static int resolve_include(char *out, size_t outsz, const char *incname,
                           const char *includer_path)
{
    char tmp[1024];
    const char *slash;

    slash = strrchr(includer_path, '/');
#ifdef _WIN32
    { const char *bs = strrchr(includer_path, '\\');
      if (bs && (!slash || bs > slash)) slash = bs; }
#endif
    if (slash) {
        snprintf(tmp, sizeof(tmp), "%.*s/%s", (int)(slash - includer_path), includer_path, incname);
        FILE *f = fopen(tmp, "r");
        if (f) { fclose(f); snprintf(out, outsz, "%s", tmp); return 1; }
        snprintf(tmp, sizeof(tmp), "%.*s/../%s", (int)(slash - includer_path), includer_path, incname);
        f = fopen(tmp, "r");
        if (f) { fclose(f); snprintf(out, outsz, "%s", tmp); return 1; }
    }
    FILE *f = fopen(incname, "r");
    if (f) { fclose(f); snprintf(out, outsz, "%s", incname); return 1; }
    return 0;
}

static void parse_file(ParseCtx *ctx, const char *path, int depth, int is_target, int is_master);

/* parse the tag region starting at p (text after the point where the help
 * comment was cut at the first ";@").  Handles multiple ;@TAG segments on
 * one line.  Advances nothing; p is a fresh mutable copy. */
static void parse_tag_segment(Setting *s, char *p)
{
    while (p) {
        char *next = strstr(p + 2, ";@");
        if (next) *next = '\0';
        char *body = p + 2;               /* skip ";@" */
        if (strncmp(body, "DEPENDS", 7) == 0 &&
            (body[7] == '\0' || isspace((unsigned char)body[7]))) {
            char *e = trim(body + 7);
            if (*e) setting_add_dep(s, e);
        } else if (strncmp(body, "HELP", 4) == 0 &&
                   (body[4] == '\0' || isspace((unsigned char)body[4]))) {
            setting_add_help(s, trim(body + 4));
        }
        /* unknown tags are ignored for now */
        p = next;
    }
}

/* parse one logical position in a line array; consumes the setting line and
 * any immediately following ;@ continuation lines; bumps *pi past them */
static void parse_setting_line(ParseCtx *ctx, char **lines, int *pi, int n,
                               const char *path, int depth, int is_target, int is_master)
{
    char *p = lines[*pi];
    char  name[MAXTOK], directive[MAXTOK];
    int   lineno = *pi + 1;
    int   i;

    while (isspace((unsigned char)*p)) p++;
    if (*p == '\0' || *p == ';') return;

    if (*p == '#') {
        if (sscanf(p, "#%255s", directive) != 1) return;
        upper(directive);
        if (strcmp(directive, "INCLUDE") == 0) {
            char incname[MAXTOK];
            char *q = strchr(p, '"');
            char *r = q ? strchr(q + 1, '"') : NULL;
            if (!q || !r) {
                fprintf(stderr, "hbconfig: malformed #INCLUDE at %s:%d\n", path, lineno);
                ctx->error = 1;
                return;
            }
            snprintf(incname, (size_t)(r - q), "%s", q + 1);
            char resolved[1024];
            if (!resolve_include(resolved, sizeof(resolved), incname, path)) {
                fprintf(stderr, "hbconfig: cannot find include \"%s\" referenced at %s:%d\n",
                        incname, path, lineno);
                ctx->error = 1;
                return;
            }
            int child_master = is_master ||
                (strstr(resolved, "cfg_MASTER.asm") != NULL);
            if (child_master && ctx->master_path[0] == '\0')
                snprintf(ctx->master_path, sizeof(ctx->master_path), "%s", resolved);
            /* is_target does NOT propagate: only lines physically in the
               named file count as the target's own (SPEC.md section 3) */
            parse_file(ctx, resolved, depth + 1, 0, child_master);
        }
        /* #DEFINE lines are not settings; they pass through unchanged (SPEC 7) */
        return;
    }

    /* setting line: NAME [.EQU|.SET] VALUE [; comment] */
    i = 0;
    while (p[i] && !isspace((unsigned char)p[i]) && i < MAXTOK - 1) { name[i] = p[i]; i++; }
    name[i] = '\0';
    p += i;
    while (isspace((unsigned char)*p)) p++;

    i = 0;
    if (*p != '.') return;   /* not a setting line */
    while (p[i] && !isspace((unsigned char)p[i]) && i < MAXTOK - 1) { directive[i] = p[i]; i++; }
    directive[i] = '\0';
    p += i;
    upper(directive);
    if (strcmp(directive, ".EQU") != 0 && strcmp(directive, ".SET") != 0)
        return;             /* e.g. .BYTE/.WORD data lines: not settings */
    while (isspace((unsigned char)*p)) p++;

    {
        char valbuf[1024];
        int vi = 0, inq = 0;
        while (*p && (*p != ';' || inq) && vi < (int)sizeof(valbuf) - 1) {
            if (*p == '"') inq = !inq;
            valbuf[vi++] = *p++;
        }
        valbuf[vi] = '\0';

        Setting s;
        memset(&s, 0, sizeof(s));
        upper(name);
        s.name      = xstrdup(name);
        s.value     = xstrdup(trim(valbuf));
        s.file      = xstrdup(path);
        s.line      = lineno;
        s.in_master = is_master;
        s.in_target = is_target;

        if (*p == ';') {
            p++;
            char *tag = strstr(p, ";@");
            char *tags = NULL;
            if (tag) { tags = xstrdup(tag); *tag = '\0'; }  /* copy BEFORE cutting */
            s.comment = xstrdup(trim(p));
            if (tags) {
                parse_tag_segment(&s, tags);
                free(tags);
            }
        } else {
            s.comment = xstrdup("");
        }

        /* ;@ continuation lines directly below (RULES.md section 4) */
        while (*pi + 1 < n) {
            char *nl = lines[*pi + 1];
            char *t = nl;
            while (*t == ' ' || *t == '\t') t++;
            if (t[0] != ';' || t[1] != '@') break;
            check_ascii(t, *pi + 2, path);
            (*pi)++;
            char *seg = xstrdup(t);
            parse_tag_segment(&s, seg);
            free(seg);
        }

        slist_push(&ctx->recs, s);
    }
}

static void parse_file(ParseCtx *ctx, const char *path, int depth, int is_target, int is_master)
{
    FILE *f;
    char  buf[65536];
    long  sz;
    char *content, **lines;
    int   n = 0, cap = 0, i;

    if (depth > 32) die("include recursion too deep (circular #INCLUDE?)");
    f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "hbconfig: cannot read file: %s\n", path);
        ctx->error = 1;
        return;
    }
    fseek(f, 0, SEEK_END);
    sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0 || sz >= (long)sizeof(buf)) { fclose(f); die("file too large or empty"); }
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) { fclose(f); die("read error"); }
    fclose(f);
    buf[sz] = '\0';

    content = xstrdup(buf);
    lines = NULL;
    {
        char *save = NULL;
        char *ln = strtok_r(content, "\n", &save);
        while (ln) {
            char *cr;
            while ((cr = strchr(ln, '\r')) != NULL) memmove(cr, cr + 1, strlen(cr));
            if (n == cap) { cap = cap ? cap * 2 : 128; lines = realloc(lines, cap * sizeof(char *)); }
            lines[n++] = ln;
            ln = strtok_r(NULL, "\n", &save);
        }
    }

    for (i = 0; i < n; i++)
        parse_setting_line(ctx, lines, &i, n, path, depth, is_target, is_master);

    /* note: lines/content leak per include; fine for a short-lived CLI tool */
}

/*==================================================================================================
 * LOOKUPS
 *==================================================================================================*/

/* last record for name, optionally excluding records from the target file */
static Setting *find_setting(SList *sl, const char *name, int skip_target)
{
    int i;
    for (i = sl->n - 1; i >= 0; i--)
        if (strcmp(sl->v[i].name, name) == 0)
            if (!(skip_target && sl->v[i].in_target))
                return &sl->v[i];
    return NULL;
}

/*==================================================================================================
 * EXPRESSION ENGINE (RULES.md section 4)
 *
 *   expr    := or
 *   or      := and { "||" and }
 *   and     := not { "&&" not }
 *   not     := "!" not | cmp
 *   cmp     := primary { ("="|"!="|"<="|">="|"<"|">") primary }
 *   primary := "(" expr ")" | operand
 *   operand := number | $hex | TRUE | FALSE | NAME
 *
 * Operands resolve to a setting's effective value (or a literal).
 * Comparisons are numeric when both sides parse as numbers, otherwise
 * string equality (= / != only).
 *=================================================================================================*/

typedef struct {
    long        num;       /* numeric value when isnum            */
    const char *str;       /* original value text (setting value) */
    int         isnum;     /* str is a number                     */
} EVal;

typedef struct {
    const char *p;         /* cursor            */
    ParseCtx   *ctx;       /* for name lookup   */
    char        err[256];  /* first error       */
} EState;

static void eset_err(EState *e, const char *msg)
{
    if (!e->err[0]) { strncpy(e->err, msg, sizeof(e->err) - 1); e->err[sizeof(e->err) - 1] = 0; }
}

static void ews(EState *e) { while (isspace((unsigned char)*e->p)) e->p++; }

static int parse_number(const char *s, long *out)
{
    char buf[64];
    char *end;
    size_t n = strlen(s);
    if (n >= sizeof(buf)) return 0;
    strcpy(buf, s);
    upper(buf);
    if (buf[0] == '$') {
        if (!isxdigit((unsigned char)buf[1])) return 0;
        *out = strtol(buf + 1, &end, 16);
        return *end == '\0';
    }
    if (buf[0] == '\0') return 0;
    *out = strtol(buf, &end, 10);
    return *end == '\0';
}

/* resolve an operand token to a value: literals first, then the
   setting's effective value from the cascade */
static EVal eval_name(EState *e, const char *tok)
{
    EVal v;
    long n;
    memset(&v, 0, sizeof(v));
    if (strcmp(tok, "TRUE") == 0)  { v.str = "TRUE";  v.num = 1; v.isnum = 1; return v; }
    if (strcmp(tok, "FALSE") == 0) { v.str = "FALSE"; v.num = 0; v.isnum = 1; return v; }
    if (parse_number(tok, &n)) { v.str = tok; v.num = n; v.isnum = 1; return v; }
    {
        Setting *s = find_setting(&e->ctx->recs, tok, 0);
        if (!s) {
            /* std.asm constants are not part of the config cascade; they
               resolve for tag evaluation (RULES.md allows pick options) */
            int i;
            for (i = e->ctx->consts.n - 1; i >= 0; i--)
                if (strcmp(e->ctx->consts.v[i].name, tok) == 0) { s = &e->ctx->consts.v[i]; break; }
        }
        if (!s) {
            if (!e->err[0]) snprintf(e->err, sizeof(e->err), "unknown name '%.200s'", tok);
            v.str = "0"; v.num = 0; v.isnum = 1;
            return v;
        }
        v.str = s->value;
        v.isnum = parse_number(s->value, &v.num);
        /* a setting whose value IS a constant name (CPUFAM = CPU_Z280)
           resolves one level through the constant table for comparison */
        if (!v.isnum && (isalpha((unsigned char)v.str[0]) || v.str[0] == '_')) {
            int k;
            for (k = ctx_consts(e->ctx)->n - 1; k >= 0; k--)
                if (strcmp(ctx_consts(e->ctx)->v[k].name, v.str) == 0) {
                    v.str = ctx_consts(e->ctx)->v[k].value;
                    v.isnum = parse_number(v.str, &v.num);
                    break;
                }
        }
        return v;
    }
}

static EVal eval_or(EState *e);

static EVal eval_primary(EState *e)
{
    ews(e);
    if (*e->p == '(') {
        EVal v;
        e->p++;
        v = eval_or(e);
        ews(e);
        if (*e->p != ')') { eset_err(e, "missing ')'"); e->p++; }
        else e->p++;
        return v;
    }
    {
        char tok[MAXTOK];
        int i = 0;
        if (!(isalnum((unsigned char)*e->p) || *e->p == '_' || *e->p == '$')) {
            eset_err(e, "expected name or number");
            { EVal z; memset(&z, 0, sizeof(z)); z.str = "0"; z.isnum = 1; return z; }
        }
        while ((isalnum((unsigned char)*e->p) || *e->p == '_' || *e->p == '$') && i < MAXTOK - 1)
            tok[i++] = *e->p++;
        tok[i] = '\0';
        upper(tok);
        return eval_name(e, tok);
    }
}

/* boolean context: FALSE literal is 0, numbers by value, other
   non-empty strings TRUE */
static int eval_truth(EVal v)
{
    if (!v.isnum) {
        if (value_eq(v.str, "FALSE")) return 0;
        if (value_eq(v.str, "TRUE"))  return 1;
        return v.str[0] != '\0';
    }
    return v.num != 0;
}

static EVal eval_cmp(EState *e)
{
    EVal l = eval_primary(e);
    for (;;) {
        const char *op;
        EVal r;
        ews(e);
        op = NULL;
        if (strncmp(e->p, "<=", 2) == 0) op = "<=";
        else if (strncmp(e->p, ">=", 2) == 0) op = ">=";
        else if (strncmp(e->p, "!=", 2) == 0) op = "!=";
        else if (strncmp(e->p, "=", 1) == 0) op = "=";
        else if (strncmp(e->p, "<", 1) == 0) op = "<";
        else if (strncmp(e->p, ">", 1) == 0) op = ">";
        if (!op) return l;
        e->p += strlen(op);
        r = eval_primary(e);
        {
            int res;
            if (l.isnum && r.isnum) {
                if (strcmp(op, "=") == 0)  res = (l.num == r.num);
                else if (strcmp(op, "!=") == 0) res = (l.num != r.num);
                else if (strcmp(op, "<") == 0)  res = (l.num < r.num);
                else if (strcmp(op, "<=") == 0) res = (l.num <= r.num);
                else if (strcmp(op, ">") == 0)  res = (l.num > r.num);
                else res = (l.num >= r.num);
            } else {
                /* non-numeric: = / != only, case-insensitive whitespace-insensitive */
                if (strcmp(op, "=") == 0)  res = value_eq(l.str, r.str);
                else if (strcmp(op, "!=") == 0) res = !value_eq(l.str, r.str);
                else {
                    eset_err(e, "ordering comparison on non-numeric value");
                    res = 0;
                }
            }
            l.isnum = 1; l.num = res; l.str = res ? "TRUE" : "FALSE";
        }
    }
}

static EVal eval_not(EState *e)
{
    ews(e);
    if (*e->p == '!') {
        EVal v;
        e->p++;
        v = eval_not(e);
        { int t = !eval_truth(v); v.isnum = 1; v.num = t; v.str = t ? "TRUE" : "FALSE"; }
        return v;
    }
    return eval_cmp(e);
}

static EVal eval_and(EState *e)
{
    EVal v = eval_not(e);
    for (;;) {
        ews(e);
        if (strncmp(e->p, "&&", 2) != 0) return v;
        e->p += 2;
        {
            EVal r = eval_not(e);
            int t = eval_truth(v) && eval_truth(r);
            v.isnum = 1; v.num = t; v.str = t ? "TRUE" : "FALSE";
        }
    }
}

static EVal eval_or(EState *e)
{
    EVal v = eval_and(e);
    for (;;) {
        ews(e);
        if (strncmp(e->p, "||", 2) != 0) return v;
        e->p += 2;
        {
            EVal r = eval_and(e);
            int t = eval_truth(v) || eval_truth(r);
            v.isnum = 1; v.num = t; v.str = t ? "TRUE" : "FALSE";
        }
    }
}

/* evaluate a ;@DEPENDS expression against the cascade */
static int eval_depends(ParseCtx *ctx, const char *expr, char *err, size_t errsz)
{
    EState e;
    EVal v;
    memset(&e, 0, sizeof(e));
    e.p = expr;
    e.ctx = ctx;
    v = eval_or(&e);
    ews(&e);
    if (*e.p != '\0' && !e.err[0]) snprintf(e.err, sizeof(e.err), "trailing garbage at '%.20s'", e.p);
    if (e.err[0]) { snprintf(err, errsz, "%s", e.err); return -1; }
    return eval_truth(v);
}

/*==================================================================================================
 * -show MODE
 *=================================================================================================*/

static int cmd_show(ParseCtx *ctx)
{
    int printed = 0, i, pass;

    printf("; hbconfig -show: %s\n", ctx->target_path);
    printf("; settings differing from cfg_MASTER.asm\n");
    printf("%-24s %-28s %-28s %s\n", "SETTING", "EFFECTIVE", "MASTER", "SET BY");

    for (pass = 0; pass < 2; pass++) {
        for (i = 0; i < ctx->recs.n; i++) {
            Setting *m, *eff;
            const char *name = ctx->recs.v[i].name;

            if (pass == 0 && !ctx->recs.v[i].in_master) continue;
            if (pass == 1 && ctx->recs.v[i].in_master) continue;
            { int j, seen = 0;
              for (j = 0; j < i; j++)
                  if (strcmp(ctx->recs.v[j].name, name) == 0 &&
                      (!!ctx->recs.v[j].in_master) == (pass == 0)) { seen = 1; break; }
              if (seen) continue; }

            eff = find_setting(&ctx->recs, name, 0);
            { int j; m = NULL;
              for (j = ctx->recs.n - 1; j >= 0; j--)
                  if (ctx->recs.v[j].in_master && strcmp(ctx->recs.v[j].name, name) == 0) {
                      m = &ctx->recs.v[j]; break; } }
            if (!m) continue;
            if (value_eq(eff->value, m->value)) continue;

            { int j; const char *setby = ctx->target_path; int setline = eff->line;
              for (j = ctx->recs.n - 1; j >= 0; j--)
                  if (!ctx->recs.v[j].in_target && strcmp(ctx->recs.v[j].name, name) == 0) {
                      setby = ctx->recs.v[j].file; setline = ctx->recs.v[j].line; break; }
              printf("%-24s %-28s %-28s %s:%d\n", name, eff->value, m->value,
                     setby, setline);
            }
            printed++;
        }
    }
    printf("; %d setting(s) differ\n", printed);
    return 0;
}

/*==================================================================================================
 * -check MODE (SPEC.md section 6)
 *=================================================================================================*/

static int cmd_check(ParseCtx *ctx)
{
    int i, broken = 0, badtags = 0;

    printf("; hbconfig -check: %s\n", ctx->target_path);

    for (i = 0; i < ctx->recs.n; i++) {
        Setting *tagged = &ctx->recs.v[i];
        Setting *eff;
        int j, is_bool, setting_on;

        if (tagged->ndep == 0) continue;

        /* the VALUE that matters is the effective one (last record for the
           name, wherever defined); the tag may sit on any record of it */
        eff = find_setting(&ctx->recs, tagged->name, 0);
        if (!eff) continue;

        is_bool   = value_eq(eff->value, "TRUE") || value_eq(eff->value, "FALSE");
        setting_on = value_eq(eff->value, "TRUE");

        for (j = 0; j < tagged->ndep; j++) {
            char err[256] = "";
            int r = eval_depends(ctx, tagged->depends[j], err, sizeof(err));
            if (r < 0) {
                printf("BAD TAG  %-24s %s:%d  %s\n", tagged->name, tagged->file, tagged->line, err);
                printf("         ;@DEPENDS %s\n", tagged->depends[j]);
                badtags++;
                continue;
            }
            /* TRUE/FALSE setting: rule must hold only when the setting is TRUE */
            if (is_bool && !setting_on) continue;
            if (!r) {
                printf("BROKEN   %-24s %s:%d\n", tagged->name, tagged->file, tagged->line);
                printf("         value = %s\n", eff->value);
                printf("         ;@DEPENDS %s\n", tagged->depends[j]);
                broken++;
            }
        }
    }

    printf("; %d rule(s) broken, %d bad tag(s)\n", broken, badtags);
    return (broken || badtags) ? 1 : 0;
}

/*==================================================================================================
 * -write MODE (SPEC.md section 7)
 *
 * Applies NAME=VALUE edits to the target file only:
 *   - already set by the file: value replaced in its last .SET line, rest
 *     of the line (tabs, comment) untouched
 *   - set back to the inherited value: .SET lines removed, with the
 *     indented "; ..." continuation lines right below them
 *   - not set by the file: appended at the end in the house layout
 *     (name col 0, .SET col 16, value col 24, comment col 40, tabs 8 wide)
 * Every other line stays byte-identical; line endings preserved; the new
 * content is written to a temp file and swapped in.
 *=================================================================================================*/

typedef struct {
    int    idx;          /* line index in the target file          */
    char   name[64];
    size_t vstart, vend; /* value span within the line text        */
    int    removed;      /* line dropped by an edit                */
} TSet;

typedef struct {
    char     **text;     /* line text without EOL                  */
    int        n, cap;
    int        eol_crlf; /* 1 = CRLF, 0 = LF                       */
    TSet      *sets;     /* .SET/.EQU lines physically in the file */
    int        nsets, capsets;
    char      *raw;      /* original file bytes                    */
    size_t     rawlen;
} TFile;

static int target_load(TFile *tf, const char *path)
{
    FILE *f = fopen(path, "rb");
    long sz;
    char *p;

    memset(tf, 0, sizeof(*tf));
    if (!f) return 0;
    fseek(f, 0, SEEK_END); sz = ftell(f); fseek(f, 0, SEEK_SET);
    tf->raw = (char *)xmalloc((size_t)sz + 1);
    if (fread(tf->raw, 1, (size_t)sz, f) != (size_t)sz) { fclose(f); return 0; }
    fclose(f);
    tf->raw[sz] = '\0';
    tf->rawlen = (size_t)sz;

    /* line ending: first CR or LF decides */
    p = tf->raw;
    while (*p && *p != '\r' && *p != '\n') p++;
    tf->eol_crlf = (*p == '\r');

    /* split a COPY into lines WITHOUT dropping empty ones (strtok collapses
       consecutive delimiters, which would eat blank lines); tf->raw stays
       pristine for the byte-identical comparison */
    {
        char *copy = (char *)xmalloc((size_t)sz + 1);
        memcpy(copy, tf->raw, (size_t)sz + 1);
        char *ln = copy;
        char *p = copy;
        while (1) {
            if (*p == '\n' || *p == '\0') {
                int last = (*p == '\0');
                *p = '\0';
                /* strip one trailing CR (CRLF files) */
                {
                    size_t l = strlen(ln);
                    if (l && ln[l - 1] == '\r') ln[l - 1] = '\0';
                }
                /* drop only the synthetic empty line after a final newline;
                   interior empty (blank) lines are kept */
                if (!last || ln[0] != '\0') {
                    if (tf->n == tf->cap) {
                        tf->cap = tf->cap ? tf->cap * 2 : 128;
                        tf->text = realloc(tf->text, tf->cap * sizeof(char *));
                    }
                    tf->text[tf->n++] = ln;
                }
                if (last) break;
                ln = p + 1;
            }
            p++;
        }
    }
    return 1;
}

/* scan the target file's own lines for .SET/.EQU settings (value spans) */
static void target_scan(TFile *tf)
{
    int i;
    for (i = 0; i < tf->n; i++) {
        char *p = tf->text[i];
        char name[64], dir[16];
        int k = 0;
        TSet ts;

        while (*p == ' ' || *p == '\t') p++;
        if (!isalpha((unsigned char)*p) && *p != '_') continue;
        while ((isalnum((unsigned char)*p) || *p == '_') && k < 63) name[k++] = *p++;
        name[k] = '\0';
        while (*p == ' ' || *p == '\t') p++;
        if (*p != '.') continue;
        k = 0;
        while (*p && !isspace((unsigned char)*p) && k < 15) dir[k++] = *p++;
        dir[k] = '\0';
        upper(dir);
        if (strcmp(dir, ".SET") != 0 && strcmp(dir, ".EQU") != 0) continue;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '\0' || *p == ';') continue;

        memset(&ts, 0, sizeof(ts));
        ts.idx = i;
        snprintf(ts.name, sizeof(ts.name), "%s", name);
        upper(ts.name);
        ts.vstart = (size_t)(p - tf->text[i]);
        {
            int inq = 0;
            while (*p && (*p != ';' || inq)) { if (*p == '"') inq = !inq; p++; }
            ts.vend = (size_t)(p - tf->text[i]);
            while (ts.vend > ts.vstart &&
                   isspace((unsigned char)tf->text[i][ts.vend - 1])) ts.vend--;
        }
        if (tf->nsets == tf->capsets) {
            tf->capsets = tf->capsets ? tf->capsets * 2 : 32;
            tf->sets = realloc(tf->sets, tf->capsets * sizeof(TSet));
        }
        tf->sets[tf->nsets++] = ts;
    }
}

/* pad with tabs (8-wide stops) up to col, or one space if already past */
static void buf_pad_tab(char *buf, size_t bufsz, int *col, int target)
{
    size_t len = strlen(buf);
    if (*col > target) {
        if (len + 1 < bufsz) { buf[len] = ' '; buf[len + 1] = '\0'; (*col)++; }
        return;
    }
    while (*col < target) {
        if (len + 1 >= bufsz) break;
        buf[len++] = '\t';
        buf[len] = '\0';
        *col = (*col & ~7) + 8;
    }
}

/* find the master comment for a setting (for appended lines) */
static const char *master_comment(ParseCtx *ctx, const char *name)
{
    int i;
    for (i = ctx->recs.n - 1; i >= 0; i--)
        if (ctx->recs.v[i].in_master && strcmp(ctx->recs.v[i].name, name) == 0)
            return ctx->recs.v[i].comment;
    return NULL;
}

typedef struct { char *name; char *val; } Edit;

/* apply a list of edits to the target file (SPEC.md section 7) */
static int apply_edits(ParseCtx *ctx, Edit *edits, int nedit_req)
{
    TFile tf;
    int i, a, nedit = 0, changed = 0;
    char *out, *o;
    const char *eol;
    size_t outsz;
    FILE *f;
    char tmpath[1200];

    if (!target_load(&tf, ctx->target_path)) {
        fprintf(stderr, "hbconfig: cannot read %s\n", ctx->target_path);
        return 1;
    }
    target_scan(&tf);
    eol = tf.eol_crlf ? "\r\n" : "\n";

    /* apply each NAME=VALUE edit */
    for (a = 0; a < nedit_req; a++) {
        char *name = edits[a].name;
        char *val = edits[a].val;
        Setting *inh;
        TSet *last = NULL;
        int k;

        upper(name);
        check_ascii(name, 0, "argument");
        check_ascii(val, 0, "argument");
        if (*name == '\0' || *val == '\0') { fprintf(stderr, "hbconfig: bad edit '%s'\n", name); return 1; }

        /* the setting must exist somewhere in the cascade */
        if (!find_setting(&ctx->recs, name, 0)) {
            fprintf(stderr, "hbconfig: unknown setting '%s'\n", name);
            return 1;
        }
        /* inherited value: cascade without the target's own .SETs */
        inh = find_setting(&ctx->recs, name, 1);

        /* last own .SET line for this name */
        for (k = 0; k < tf.nsets; k++)
            if (strcmp(tf.sets[k].name, name) == 0 && !tf.sets[k].removed)
                last = &tf.sets[k];

        if (inh && value_eq(inh->value, val)) {
            /* back to inherited: remove own .SET lines + continuation comments */
            int removed = 0;
            for (k = 0; k < tf.nsets; k++) {
                if (strcmp(tf.sets[k].name, name) == 0 && !tf.sets[k].removed) {
                    int li = tf.sets[k].idx;
                    tf.text[li] = NULL;      /* mark removed */
                    tf.sets[k].removed = 1;
                    removed++;
                    /* swallow indented "; ..." continuation lines below */
                    while (li + 1 < tf.n) {
                        char *np = tf.text[li + 1];
                        char *t = np;
                        if (t[0] == '\0') break;
                        while (*t == ' ' || *t == '\t') t++;
                        if (*t != ';' || t == np) break;   /* only INDENTED comments */
                        tf.text[++li] = NULL;
                    }
                }
            }
            if (removed) {
                printf("%s: removed (matches inherited value %s)\n", name, inh->value);
                changed = 1; nedit++;
            } else {
                printf("%s: already inherited, no change\n", name);
            }
            continue;
        }

        if (last) {
            /* replace value in the last .SET line, keep the rest */
            char *line = tf.text[last->idx];
            size_t oldlen = strlen(line);
            size_t vlen = strlen(val);
            size_t tail = oldlen - last->vend;
            char *nl = (char *)xmalloc(oldlen + vlen + 1);
            memcpy(nl, line, last->vstart);
            memcpy(nl + last->vstart, val, vlen);
            memcpy(nl + last->vstart + vlen, line + last->vend, tail + 1);
            tf.text[last->idx] = nl;
            printf("%s: %.*s -> %s\n", name,
                   (int)(last->vend - last->vstart), line + last->vstart, val);
            changed = 1; nedit++;
        } else {
            /* append a new .SET line in the house layout */
            char buf[2048];
            int col;
            const char *mc = master_comment(ctx, name);
            snprintf(buf, sizeof(buf), "%s", name);
            col = (int)strlen(buf);
            buf_pad_tab(buf, sizeof(buf), &col, 16);
            strncat(buf, ".SET", sizeof(buf) - strlen(buf) - 1); col += 4;
            buf_pad_tab(buf, sizeof(buf), &col, 24);
            strncat(buf, val, sizeof(buf) - strlen(buf) - 1); col += (int)strlen(val);
            if (mc && *mc) {
                buf_pad_tab(buf, sizeof(buf), &col, 40);
                strncat(buf, "; ", sizeof(buf) - strlen(buf) - 1);
                strncat(buf, mc, sizeof(buf) - strlen(buf) - 1);
            }
            if (tf.n == tf.cap) {
                tf.cap = tf.cap ? tf.cap * 2 : 128;
                tf.text = realloc(tf.text, tf.cap * sizeof(char *));
            }
            tf.text[tf.n++] = xstrdup(buf);
            printf("%s: added = %s\n", name, val);
            changed = 1; nedit++;
        }
    }

    if (!nedit) { printf("; no changes\n"); return 0; }
    if (!changed) { printf("; no changes\n"); return 0; }

    /* assemble the new content */
    outsz = 1;
    for (i = 0; i < tf.n; i++) outsz += tf.text[i] ? strlen(tf.text[i]) + 2 : 2;
    out = (char *)xmalloc(outsz);
    o = out;
    for (i = 0; i < tf.n; i++) {
        if (!tf.text[i]) continue;              /* removed line */
        if (tf.text[i][0] == '\0' && !tf.text[i][1]) continue; /* unused */
        strcpy(o, tf.text[i]); o += strlen(o);
        strcpy(o, eol); o += strlen(eol);
    }
    *o = '\0';

    if (strlen(out) == tf.rawlen && memcmp(out, tf.raw, tf.rawlen) == 0) {
        printf("; no changes\n");
        free(out);
        return 0;
    }

    snprintf(tmpath, sizeof(tmpath), "%s.hbnew", ctx->target_path);
    f = fopen(tmpath, "wb");
    if (!f) { fprintf(stderr, "hbconfig: cannot write %s\n", tmpath); return 1; }
    if (fwrite(out, 1, (size_t)(o - out), f) != (size_t)(o - out)) { fclose(f); return 1; }
    fclose(f);
    remove(ctx->target_path);
    if (rename(tmpath, ctx->target_path) != 0) {
        fprintf(stderr, "hbconfig: cannot rename %s to %s\n", tmpath, ctx->target_path);
        return 1;
    }
    printf("; %s updated\n", ctx->target_path);
    free(out);
    return 0;
}

static int cmd_write(ParseCtx *ctx, int argc, char **argv, int a0)
{
    Edit *edits;
    int a, rc;

    edits = (Edit *)xmalloc(sizeof(Edit) * (size_t)(argc - a0 + 1));
    for (a = a0; a < argc; a++) {
        char *eq = strchr(argv[a], '=');
        if (!eq) { fprintf(stderr, "hbconfig: edit '%s' is not NAME=VALUE\n", argv[a]); free(edits); return 1; }
        *eq = '\0';
        edits[a - a0].name = argv[a];
        edits[a - a0].val = eq + 1;
    }
    rc = apply_edits(ctx, edits, argc - a0);
    free(edits);
    return rc;
}

/*==================================================================================================
 * TUI (SPEC.md sections 4/5) - menuconfig-style console UI
 *
 * Portable console layer: ANSI escape sequences everywhere; on Windows
 * VT processing is enabled on the console first.  Key input: conio on
 * Windows, termios cbreak elsewhere.
 *=================================================================================================*/

#ifdef _WIN32
#include <conio.h>
#include <windows.h>
static void con_init(void)
{
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode;
    if (h != INVALID_HANDLE_VALUE && GetConsoleMode(h, &mode))
        SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
}
static int con_getkey(void) { return _getch(); }
#else
#include <termios.h>
#include <unistd.h>
#include <sys/select.h>
static struct termios saved_tio;
static void con_init(void)
{
    struct termios t;
    if (tcgetattr(0, &saved_tio) == 0) {
        t = saved_tio;
        t.c_lflag &= ~(ICANON | ECHO);
        t.c_cc[VMIN] = 1;
        tcsetattr(0, TCSANOW, &t);
    }
    const char *term = getenv("TERM");
    if (!term) setenv("TERM", "xterm", 1);
}
static void con_done(void)
{
    tcsetattr(0, TCSANOW, &saved_tio);
}
static int con_getkey(void) { return getchar(); }
#endif

#define ESC "\x1b"

typedef enum { TY_BOOL, TY_NUM, TY_HEX, TY_PICK, TY_TEXT } VType;

typedef struct {
    char   name[64];
    VType  type;
    char   value[128];      /* live (session) value        */
    char   orig[128];       /* effective value at start    */
    char   inh[128];        /* inherited value, "" if none */
    char   inhfile[512];    /* where the inherited value comes from */
    int    changed;         /* edited this session         */
    /* pick list */
    char   opts[32][64];
    int    nopts;
    int    range_lo, range_hi;   /* TY_NUM when comment has (N-M) */
    /* help */
    const char *comment;
    const char *xhelp;
    int    master_line;
} Item;

typedef struct {
    char   title[96];
    Item **items;
    int    n, cap;
} Menu;

typedef struct {
    Menu  *menus;
    int    nmenus, capmenus;
    Item  *items;          /* master copy, in master definition order */
    int    nitems;
} Model;

static Menu *model_new_menu(Model *m, const char *title)
{
    if (m->nmenus == m->capmenus) {
        m->capmenus = m->capmenus ? m->capmenus * 2 : 16;
        m->menus = realloc(m->menus, m->capmenus * sizeof(Menu));
    }
    memset(&m->menus[m->nmenus], 0, sizeof(Menu));
    snprintf(m->menus[m->nmenus].title, sizeof(m->menus[m->nmenus].title), "%s", title);
    return &m->menus[m->nmenus++];
}

static void menu_add(Menu *mn, Item *it)
{
    if (mn->n == mn->cap) {
        mn->cap = mn->cap ? mn->cap * 2 : 16;
        mn->items = realloc(mn->items, mn->cap * sizeof(Item *));
    }
    mn->items[mn->n++] = it;
}

/* classify a master value into an editor type, per RULES.md section 2 */
static VType item_type(ParseCtx *ctx, const char *val, Item *it)
{
    const char *p = val;
    if (value_eq(val, "TRUE") || value_eq(val, "FALSE")) return TY_BOOL;
    if (p[0] == '$') return TY_HEX;
    {
        int alldig = 1;
        for (; *p; p++) if (!isdigit((unsigned char)*p)) { alldig = 0; break; }
        if (alldig && p > val) return TY_NUM;
    }
    /* pick list: val names a constant defined in the cascade (std.asm /
       hbios.inc included from master) with same-prefix siblings */
    if (isalpha((unsigned char)val[0]) || val[0] == '_') {
        const char *us = strrchr(val, '_');
        int cnt = 0, i;
        if (us && us[1]) {
            size_t plen = (size_t)(us - val) + 1;
            /* candidates: std.asm constants (scanned separately) plus any
               cascade record that is not a config setting/master line */
            for (i = 0; i < ctx->consts.n + ctx->recs.n && cnt < 32; i++) {
                Setting *s = i < ctx->consts.n ? &ctx->consts.v[i] : &ctx->recs.v[i - ctx->consts.n];
                if (strncmp(s->name, val, plen) != 0) continue;
                /* RULES.md 2: pick-list constants live in std.asm / hbios.inc */
                {
                    const char *b = strrchr(s->file, '/');
                    const char *b2 = strrchr(s->file, '\\');
                    if (b2 && (!b || b2 > b)) b = b2;
                    b = b ? b + 1 : s->file;
                    if (strcmp(b, "std.asm") != 0 && strcmp(b, "hbios.inc") != 0)
                        continue;
                }
                snprintf(it->opts[cnt], sizeof(it->opts[cnt]), "%s", s->name);
                cnt++;
            }
            if (cnt >= 2) {
                it->nopts = cnt;
                return TY_PICK;
            }
        }
    }
    return TY_TEXT;
}

/* inherited value + its source file (SPEC.md section 3) */
static void item_inherited(ParseCtx *ctx, const char *name, Item *it)
{
    Setting *s = find_setting(&ctx->recs, name, 1);
    if (s) {
        snprintf(it->inh, sizeof(it->inh), "%s", s->value);
        snprintf(it->inhfile, sizeof(it->inhfile), "%s", s->file);
    } else {
        it->inh[0] = '\0';
        it->inhfile[0] = '\0';
    }
}

/* (0-N) range from a comment, per RULES.md section 2 */
static void item_range(Item *it)
{
    const char *p = it->comment ? strstr(it->comment, "(0-") : NULL;
    it->range_lo = 0; it->range_hi = -1;
    if (p) {
        int hi = atoi(p + 3);
        if (hi > 0) it->range_hi = hi;
    }
}

static int model_build(ParseCtx *ctx, Model *m)
{
    int i, j;
    Setting *master = NULL;
    int nmaster = 0;

    memset(m, 0, sizeof(*m));

    /* collect master records (definition order) */
    for (i = 0; i < ctx->recs.n; i++) {
        Setting *s = &ctx->recs.v[i];
        int seen = 0;
        if (!s->in_master || strstr(s->file, "cfg_MASTER") == NULL) continue;
        for (j = 0; j < i; j++)
            if (ctx->recs.v[j].in_master && strcmp(ctx->recs.v[j].name, s->name) == 0 &&
                strstr(ctx->recs.v[j].file, "cfg_MASTER")) { seen = 1; break; }
        if (seen) continue;
        master = realloc(master, (nmaster + 1) * sizeof(Setting));
        master[nmaster++] = *s;
    }
    if (!nmaster) { fprintf(stderr, "hbconfig: no master settings found\n"); return 1; }

    m->items = (Item *)calloc((size_t)nmaster, sizeof(Item));
    m->nitems = nmaster;

    for (i = 0; i < nmaster; i++) {
        Setting *eff = find_setting(&ctx->recs, master[i].name, 0);
        Item *it = &m->items[i];
        snprintf(it->name, sizeof(it->name), "%s", master[i].name);
        snprintf(it->value, sizeof(it->value), "%s", eff->value);
        snprintf(it->orig, sizeof(it->orig), "%s", eff->value);
        it->comment = master[i].comment;
        it->xhelp = master[i].xhelp;
        it->master_line = master[i].line;
        it->type = item_type(ctx, master[i].value, it);
        item_range(it);
        item_inherited(ctx, it->name, it);
    }

    /* menus: driver menus from <BASE>ENABLE (RULES.md section 3), longest
       BASE wins; remaining settings grouped into adjacent-line blocks */
    {
        char *menu_of = (char *)calloc((size_t)nmaster, sizeof(char));  /* menu idx+1 or 0 */
        int *assigned = (int *)calloc((size_t)nmaster, sizeof(int));

        /* driver menus, longest BASE first */
        for (;;) {
            int best = -1; size_t bestlen = 0;
            for (i = 0; i < nmaster; i++) {
                size_t nl = strlen(master[i].name);
                if (nl <= 6) continue;
                if (strcmp(master[i].name + nl - 6, "ENABLE") != 0) continue;
                if (menu_of[i]) continue;
                if (nl - 6 > bestlen) { bestlen = nl - 6; best = i; }
            }
            if (best < 0) break;
            {
                size_t bl = bestlen;
                char base[64];
                Menu *mn;
                char title[96];
                snprintf(base, sizeof(base), "%.*s", (int)bl, master[best].name);
                /* title: ENABLE's comment, "BASE: " in front unless already prefixed */
                if (strncmp(master[best].comment, base, bl) == 0)
                    snprintf(title, sizeof(title), "%s", master[best].comment);
                else
                    snprintf(title, sizeof(title), "%s: %s", base, master[best].comment);
                mn = model_new_menu(m, title);
                for (i = 0; i < nmaster; i++) {
                    if (assigned[i]) continue;
                    if (strncmp(master[i].name, base, bl) == 0) {
                        menu_add(mn, &m->items[i]);
                        assigned[i] = 1;
                        menu_of[i] = (char)1;
                    }
                }
            }
        }

        /* remaining: blocks of adjacent master lines (gap == 1 line) */
        i = 0;
        while (i < nmaster) {
            int j2, start = i;
            Menu *mn;
            char title[96];
            while (i + 1 < nmaster && !assigned[i + 1] &&
                   master[i + 1].line == master[i].line + 1 &&
                   strcmp(master[i + 1].file, master[i].file) == 0)
                i++;
            /* block = start..i (only if at least one unassigned; split
               runs containing assigned items) */
            {
                int has = 0;
                for (j2 = start; j2 <= i; j2++) if (!assigned[j2]) has = 1;
                if (has) {
                    /* title: common comment prefix up to ':', else FIRST..LAST */
                    const char *c0 = master[start].comment;
                    const char *col = strchr(c0, ':');
                    if (col && (size_t)(col - c0) < 20)
                        snprintf(title, sizeof(title), "%.*s", (int)(col - c0), c0);
                    else if (start == i)
                        snprintf(title, sizeof(title), "%s", master[start].name);
                    else
                        snprintf(title, sizeof(title), "%s .. %s",
                                 master[start].name, master[i].name);
                    mn = model_new_menu(m, title);
                    for (j2 = start; j2 <= i; j2++)
                        if (!assigned[j2]) { menu_add(mn, &m->items[j2]); assigned[j2] = 1; }
                }
            }
            i++;
        }
        free(menu_of); free(assigned);
    }
    free(master);
    return 0;
}

/* does the std/target file set this setting (own record outside master)? */
static int item_is_local(ParseCtx *ctx, const char *name)
{
    int i;
    for (i = 0; i < ctx->recs.n; i++)
        if (!ctx->recs.v[i].in_master && strcmp(ctx->recs.v[i].name, name) == 0)
            return 1;
    return 0;
}

/* relevant per SPEC.md section 4: local settings, settings in menus of
   enabled drivers, and session-changed settings */
static int menu_relevant(ParseCtx *ctx, Menu *mn, int show_all)
{
    int i, base_ena = -1;
    if (show_all) return 1;
    /* find the menu's ENABLE item: title comment belongs to it; check if
       any item is *ENABLE whose effective value is TRUE */
    for (i = 0; i < mn->n; i++) {
        size_t nl = strlen(mn->items[i]->name);
        if (nl > 6 && strcmp(mn->items[i]->name + nl - 6, "ENABLE") == 0) {
            base_ena = i;
            if (value_eq(mn->items[i]->value, "TRUE")) return 1;
        }
    }
    (void)base_ena;
    for (i = 0; i < mn->n; i++)
        if (mn->items[i]->changed || item_is_local(ctx, mn->items[i]->name))
            return 1;
    return 0;
}

static void ui_clear(void) { fputs(ESC "[2J" ESC "[H", stdout); }
static void ui_status(const char *fmt, ...)
{
    va_list ap;
    fputs(ESC "[" "999;1H" ESC "[2K", stdout);
    va_start(ap, fmt);
    vfprintf(stdout, fmt, ap);
    va_end(ap);
    fflush(stdout);
}

/* one-line editor at the bottom */
static void ui_edit_line(const char *prompt, char *buf, size_t bufsz)
{
    size_t len = strlen(buf);
    int c;
    for (;;) {
        fputs(ESC "[999;1H" ESC "[2K", stdout);
        fprintf(stdout, "%s%s_", prompt, buf);
        fflush(stdout);
        c = con_getkey();
        if (c == '\r' || c == '\n') break;
        if (c == 27) break;
        if (c == '\b' || c == 127 || c == 8) { if (len) buf[--len] = '\0'; continue; }
#ifdef _WIN32
        if (c == 0 || c == 224) { con_getkey(); continue; }  /* swallow fn keys */
#endif
        if (isprint(c) && len + 1 < bufsz) { buf[len++] = (char)c; buf[len] = '\0'; }
    }
    fputs(ESC "[999;1H" ESC "[2K", stdout);
}

static void ui_help(Item *it)
{
    ui_clear();
    printf("HELP: %s\n\n", it->name);
    if (it->comment && *it->comment) printf("%s\n", it->comment);
    if (it->xhelp) {
        const char *p = it->xhelp;
        while (*p) {
            const char *nl = strchr(p, '\n');
            if (nl) { printf("%.*s\n", (int)(nl - p), p); p = nl + 1; }
            else { printf("%s\n", p); break; }
        }
    }
    printf("\n");
    if (it->inh[0])
        printf("inherited: %s  (from %s)\n", it->inh, it->inhfile);
    else
        printf("inherited: (none - master default)\n");
    printf("current:   %s\n", it->value);
    printf("any key to return...");
    fflush(stdout);
    con_getkey();
}

static void item_edit(Item *it)
{
    char buf[128];
    switch (it->type) {
    case TY_BOOL:
        snprintf(it->value, sizeof(it->value), "%s",
                 value_eq(it->value, "TRUE") ? "FALSE" : "TRUE");
        it->changed = !value_eq(it->value, it->orig);
        break;
    case TY_PICK: {
        int i, cur = -1;
        for (i = 0; i < it->nopts; i++)
            if (value_eq(it->value, it->opts[i])) { cur = i; break; }
        cur = (cur + 1) % it->nopts;
        snprintf(it->value, sizeof(it->value), "%s", it->opts[cur]);
        it->changed = !value_eq(it->value, it->orig);
        break;
    }
    case TY_NUM:
    case TY_HEX:
    case TY_TEXT:
    default:
        snprintf(buf, sizeof(buf), "%s", it->value);
        ui_edit_line("new value: ", buf, sizeof(buf));
        if (*buf) {
            if (it->type == TY_NUM) {
                long v = strtol(buf, NULL, 0);
                if (it->range_hi >= 0 && (v < it->range_lo || v > it->range_hi)) {
                    ui_status("value out of range (%d-%d)", it->range_lo, it->range_hi);
                    return;
                }
            }
            snprintf(it->value, sizeof(it->value), "%s", buf);
            it->changed = !value_eq(it->value, it->orig);
        }
        break;
    }
}

static int cmd_menu(ParseCtx *ctx)
{
    Model m;
    int mi = 0, si = 0, show_all = 0, quit = 0, saved = 0;

    if (model_build(ctx, &m)) return 1;

#ifndef _WIN32
    atexit(con_done);
#endif
    con_init();
    ui_clear();

    while (!quit) {
        Menu *mn = &m.menus[mi];
        int vis_n = 0, i, row = 3;
        /* count visible items */
        if (!menu_relevant(ctx, mn, show_all)) {
            /* skip empty menu */
            mi = (mi + 1) % m.nmenus;
            continue;
        }
        printf(ESC "[H" ESC "[2K");
        printf("hbconfig  %s   [menu %d/%d]  keys: " \
               "up/dn=move pgup/pgdn=menu enter=edit h=help a=all s=save q=quit\n",
               ctx->target_path, mi + 1, m.nmenus);
        printf(ESC "[1;33m%s" ESC "[0m\n\n", mn->title);
        for (i = 0; i < mn->n && row < 40; i++) {
            Item *it = mn->items[i];
            int local = item_is_local(ctx, it->name);
            const char *mark = it->changed ? "*" : (local ? "+" : " ");
            printf(ESC "[%d;1H" ESC "[2K", row);
            if (i == si) fputs(ESC "[7m", stdout);
            printf("%s %-22s %-26s ", mark, it->name, it->value);
            if (it->comment && *it->comment)
                printf(ESC "[2m%.40s" ESC "[0m", it->comment);
            if (i == si) fputs(ESC "[0m", stdout);
            row++;
            vis_n++;
        }
        (void)vis_n;
        fflush(stdout);

        {
            int c = con_getkey();
            switch (c) {
            case 'q': case 'Q': quit = 1; break;
            case 'a': case 'A': show_all = !show_all; break;
            case 'h': case 'H': ui_help(mn->items[si]); break;
            case 's': case 'S': {
                /* collect session changes vs original effective values */
                Edit *edits = (Edit *)xmalloc(sizeof(Edit) * (size_t)m.nitems);
                int ne = 0, k, rc;
                for (k = 0; k < m.nitems; k++)
                    if (m.items[k].changed &&
                        !value_eq(m.items[k].value, m.items[k].orig)) {
                        edits[ne].name = m.items[k].name;
                        edits[ne].val = m.items[k].value;
                        ne++;
                    }
                /* leave raw mode so apply_edits' reports print cleanly */
#ifdef _WIN32
                printf("\n");
#else
                con_done();
#endif
                if (ne == 0) printf("; no changes\n");
                else {
                    ui_clear();
                    rc = apply_edits(ctx, edits, ne);
                    saved = (rc == 0);
                }
                free(edits);
                /* re-read the cascade: effective values changed on disk */
                {
                    ParseCtx nctx;
                    memset(&nctx, 0, sizeof(nctx));
                    nctx.target_path = ctx->target_path;
                    parse_file(&nctx, ctx->target_path, 0, 1, 0);
                    for (k = 0; k < m.nitems; k++) {
                        Setting *e = find_setting(&nctx.recs, m.items[k].name, 0);
                        if (e) {
                            snprintf(m.items[k].value, sizeof(m.items[k].value), "%s", e->value);
                            snprintf(m.items[k].orig, sizeof(m.items[k].orig), "%s", e->value);
                            m.items[k].changed = 0;
                            item_inherited(&nctx, m.items[k].name, &m.items[k]);
                        }
                    }
                    /* nctx leaks; short-lived session tool */
                }
#ifndef _WIN32
                con_init();
#endif
                ui_status("saved. any key...");
                con_getkey();
                break;
            }
            case '\r': case '\n': case ' ':
                item_edit(mn->items[si]);
                break;
#ifdef _WIN32
            case 0: case 224: {
                int k2 = con_getkey();
                if (k2 == 72) { if (si > 0) si--; }              /* up */
                else if (k2 == 80) { if (si < mn->n - 1) si++; } /* down */
                else if (k2 == 73) { mi = (mi + m.nmenus - 1) % m.nmenus; si = 0; }
                else if (k2 == 81) { mi = (mi + 1) % m.nmenus; si = 0; }
                break;
            }
#else
            case 27: {
                int c2 = con_getkey();
                if (c2 != '[') break;
                c2 = con_getkey();
                if (c2 == 'A') { if (si > 0) si--; }
                else if (c2 == 'B') { if (si < mn->n - 1) si++; }
                else if (c2 == 'I') { mi = (mi + m.nmenus - 1) % m.nmenus; si = 0; }
                else if (c2 == 'V' || c2 == '6') { mi = (mi + 1) % m.nmenus; si = 0; }
                break;
            }
#endif
            }
        }
    }

    ui_clear();
#ifndef _WIN32
    con_done();
#endif
    return saved ? 0 : 0;
}

static void usage(void)
{
    fprintf(stderr,
        "hbconfig - RomWBW HBIOS configuration tool\n"
        "usage:\n"
        "  hbconfig -show  <config-file>\n"
        "  hbconfig -show  <platform> <config>\n"
        "  hbconfig -check <config-file>\n"
        "  hbconfig -check <platform> <config>\n"
        "  hbconfig -write <config-file> NAME=VALUE [NAME=VALUE ...]\n"
        "  hbconfig -write <platform> <config> NAME=VALUE [NAME=VALUE ...]\n"
        "    (platform/config form locates Config/<platform>_<config>.asm)\n");
    exit(2);
}

int main(int argc, char **argv)
{
    ParseCtx ctx;
    char path[1024];
    enum { M_SHOW, M_CHECK, M_WRITE, M_MENU } mode = M_SHOW;
    int a0 = 3;

    memset(&ctx, 0, sizeof(ctx));

    if (argc < 3) usage();
    if (strcmp(argv[1], "-show") == 0) mode = M_SHOW;
    else if (strcmp(argv[1], "-check") == 0) mode = M_CHECK;
    else if (strcmp(argv[1], "-write") == 0) mode = M_WRITE;
    else if (strcmp(argv[1], "-menu") == 0) mode = M_MENU;
    else usage();

    /* config-file vs platform+config: a path separator or .asm suffix
       means a file; otherwise the next arg is the config name */
    if (strchr(argv[2], '/') || strchr(argv[2], '\\') ||
        strstr(argv[2], ".asm") || strstr(argv[2], ".ASM")) {
        snprintf(path, sizeof(path), "%s", argv[2]);
    } else {
        if (argc < 4) usage();
        snprintf(path, sizeof(path), "Config/%s_%s.asm", argv[2], argv[3]);
        a0 = 4;
    }

    ctx.target_path = xstrdup(path);
    parse_file(&ctx, path, 0, 1, 0);
    /* std.asm is not #included by the config chain, but its constants
       define the pick lists and resolve tag names (RULES.md section 2) */
    if (ctx.master_path[0]) {
        char stdpath[1200];
        const char *slash = strrchr(ctx.master_path, '/');
#ifdef _WIN32
        { const char *bs = strrchr(ctx.master_path, '\\');
          if (bs && (!slash || bs > slash)) slash = bs; }
#endif
        if (slash) {
            ParseCtx cctx;
            memset(&cctx, 0, sizeof(cctx));
            snprintf(stdpath, sizeof(stdpath), "%.*s/std.asm",
                     (int)(slash - ctx.master_path), ctx.master_path);
            parse_file(&cctx, stdpath, 0, 0, 0);
            ctx.consts = cctx.recs;
        }
    }
    if (ctx.error) return 1;

    switch (mode) {
    case M_SHOW:  return cmd_show(&ctx);
    case M_CHECK: return cmd_check(&ctx);
    case M_WRITE: return cmd_write(&ctx, argc, argv, a0);
    case M_MENU:  return cmd_menu(&ctx);
    }
    return 2;
}
