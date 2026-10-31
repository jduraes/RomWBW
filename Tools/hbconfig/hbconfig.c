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
    char        master_path[1024];
    int         error;
} ParseCtx;

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
            if (!e->err[0]) snprintf(e->err, sizeof(e->err), "unknown name '%.200s'", tok);
            v.str = "0"; v.num = 0; v.isnum = 1;
            return v;
        }
        v.str = s->value;
        v.isnum = parse_number(s->value, &v.num);
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

static int cmd_write(ParseCtx *ctx, int argc, char **argv, int a0)
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
    for (a = a0; a < argc; a++) {
        char *eq = strchr(argv[a], '=');
        char *name, *val;
        Setting *inh;
        TSet *last = NULL;
        int k;

        if (!eq) { fprintf(stderr, "hbconfig: edit '%s' is not NAME=VALUE\n", argv[a]); return 1; }
        *eq = '\0';
        name = argv[a]; val = eq + 1;
        upper(name);
        check_ascii(name, 0, "argument");
        check_ascii(val, 0, "argument");
        if (*name == '\0' || *val == '\0') { fprintf(stderr, "hbconfig: bad edit '%s'\n", argv[a]); return 1; }

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

/*==================================================================================================
 * MAIN
 *=================================================================================================*/

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
    enum { M_SHOW, M_CHECK, M_WRITE } mode = M_SHOW;
    int a0 = 3;

    memset(&ctx, 0, sizeof(ctx));

    if (argc < 3) usage();
    if (strcmp(argv[1], "-show") == 0) mode = M_SHOW;
    else if (strcmp(argv[1], "-check") == 0) mode = M_CHECK;
    else if (strcmp(argv[1], "-write") == 0) mode = M_WRITE;
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
    if (ctx.error) return 1;

    switch (mode) {
    case M_SHOW:  return cmd_show(&ctx);
    case M_CHECK: return cmd_check(&ctx);
    case M_WRITE: return cmd_write(&ctx, argc, argv, a0);
    }
    return 2;
}
