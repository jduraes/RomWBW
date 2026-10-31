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
 * M1 scope (per SPEC.md section 2):
 *   hbconfig -show <config-file>            - non-interactive diff report
 *   hbconfig -show <platform> <config>      - same, locating Config/<plt>_<cfg>.asm
 *
 * The cascade (SPEC.md section 3): a config file is read the way the
 * assembler reads it, top to bottom, #INCLUDE expanded in place, last
 * .EQU/.SET of a name wins.  The inherited value of a setting is what the
 * cascade produces with the target file's own .SET lines left out.
 *
 * -show prints every setting whose effective value differs from
 * cfg_MASTER.asm, with the effective value, the master value, and the
 * file that set it.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAXTOK   256
#define MAXFILES 256

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
} Setting;

typedef struct {
    Setting  *v;
    int       n, cap;
} SList;

static char *xstrdup(const char *s)
{
    char *p = malloc(strlen(s) + 1);
    if (!p) die("out of memory");
    strcpy(p, s);
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

typedef struct {
    const char *target_path;    /* file the user named            */
    SList       recs;           /* all .EQU/.SET records in order */
    char        master_path[1024];
    int         error;
} ParseCtx;

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
 * then relative to the directory of the top-level config file's dir parent */
static int resolve_include(char *out, size_t outsz, const char *incname,
                           const char *includer_path)
{
    char tmp[1024];
    const char *slash;

    /* try: directory of the including file */
    slash = strrchr(includer_path, '/');
#ifdef _WIN32
    { const char *bs = strrchr(includer_path, '\\');
      if (bs && (!slash || bs > slash)) slash = bs; }
#endif
    if (slash) {
        snprintf(tmp, sizeof(tmp), "%.*s/%s", (int)(slash - includer_path), includer_path, incname);
        FILE *f = fopen(tmp, "r");
        if (f) { fclose(f); snprintf(out, outsz, "%s", tmp); return 1; }
        /* RomWBW convention: config files in Config/ include platform and
         * master files from the parent (HBIOS) directory */
        snprintf(tmp, sizeof(tmp), "%.*s/../%s", (int)(slash - includer_path), includer_path, incname);
        f = fopen(tmp, "r");
        if (f) { fclose(f); snprintf(out, outsz, "%s", tmp); return 1; }
    }
    /* try: as given (cwd-relative) */
    FILE *f = fopen(incname, "r");
    if (f) { fclose(f); snprintf(out, outsz, "%s", incname); return 1; }
    return 0;
}

static void parse_file(ParseCtx *ctx, const char *path, int depth, int is_target, int is_master);

static void handle_line(ParseCtx *ctx, char *line, int lineno, const char *path,
                        int depth, int is_target, int is_master)
{
    char *p = line;
    char  name[MAXTOK], directive[MAXTOK];

    check_ascii(line, lineno, path);

    /* skip leading whitespace */
    while (isspace((unsigned char)*p)) p++;
    if (*p == '\0' || *p == ';') return;    /* blank or comment line */

    if (*p == '#') {
        /* directive: #DEFINE or #INCLUDE */
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
            /* a file that includes cfg_MASTER.asm (by name) becomes the master root;
               simpler: any file named cfg_MASTER.asm is the master file */
            int child_master = is_master ||
                (strstr(resolved, "cfg_MASTER.asm") != NULL);
            if (child_master && ctx->master_path[0] == '\0')
                snprintf(ctx->master_path, sizeof(ctx->master_path), "%s", resolved);
            parse_file(ctx, resolved, depth + 1, is_target, child_master);
        }
        /* #DEFINE lines are not settings; they pass through unchanged (SPEC 7) */
        return;
    }

    /* setting line: NAME [.EQU|.SET] VALUE [; comment] */
    {
        int i = 0;
        while (p[i] && !isspace((unsigned char)p[i]) && p[i] != '\t' && i < MAXTOK - 1) {
            name[i] = p[i];
            i++;
        }
        name[i] = '\0';
        p += i;
        while (isspace((unsigned char)*p)) p++;

        /* directive token */
        i = 0;
        if (*p != '.') return;   /* not a setting line */
        while (p[i] && !isspace((unsigned char)p[i]) && p[i] != '\t' && i < MAXTOK - 1) {
            directive[i] = p[i];
            i++;
        }
        directive[i] = '\0';
        p += i;
        upper(directive);
        if (strcmp(directive, ".EQU") != 0 && strcmp(directive, ".SET") != 0)
            return;             /* e.g. .BYTE/.WORD data lines: not settings */
        while (isspace((unsigned char)*p)) p++;

        /* value: up to ';' or end of line; respect double quotes */
        {
            char valbuf[1024];
            int vi = 0, inq = 0;
            while (*p && (*p != ';' || inq) && vi < (int)sizeof(valbuf) - 1) {
                if (*p == '"') inq = !inq;
                valbuf[vi++] = *p++;
            }
            valbuf[vi] = '\0';
            char *comment = NULL;
            if (*p == ';') {
                p++;   /* skip the ';' */
                /* tags begin at ";@" - comment text ends there */
                char *tag = strstr(p, ";@");
                if (tag) *tag = '\0';
                comment = xstrdup(trim(p));
            }

            Setting s;
            memset(&s, 0, sizeof(s));
            upper(name);
            s.name      = xstrdup(name);
            s.value     = xstrdup(trim(valbuf));
            s.comment   = comment ? comment : xstrdup("");
            s.file      = xstrdup(path);
            s.line      = lineno;
            s.in_master = is_master;
            s.in_target = is_target;
            slist_push(&ctx->recs, s);
        }
    }
}

static void parse_file(ParseCtx *ctx, const char *path, int depth, int is_target, int is_master)
{
    FILE *f;
    char  line[2048];
    int   lineno = 0;

    if (depth > 32) die("include recursion too deep (circular #INCLUDE?)");
    f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "hbconfig: cannot read file: %s\n", path);
        ctx->error = 1;
        return;
    }
    while (fgets(line, sizeof(line), f)) {
        lineno++;
        handle_line(ctx, line, lineno, path, depth, is_target, is_master);
    }
    fclose(f);
}

/*==================================================================================================
 * LOOKUPS
 *=================================================================================================*/

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
 * -show MODE
 *=================================================================================================*/

static int cmd_show(ParseCtx *ctx)
{
    /* pass 1: master order; pass 2: extras not in master */
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
            /* only visit each name once: first occurrence in this pass */
            { int j, seen = 0;
              for (j = 0; j < i; j++)
                  if (strcmp(ctx->recs.v[j].name, name) == 0 &&
                      (!!ctx->recs.v[j].in_master) == (pass == 0)) { seen = 1; break; }
              if (seen) continue; }

            m   = find_setting(&ctx->recs, name, 0);
            eff = find_setting(&ctx->recs, name, 0);
            /* master value: last master record for this name */
            { int j; m = NULL;
              for (j = ctx->recs.n - 1; j >= 0; j--)
                  if (ctx->recs.v[j].in_master && strcmp(ctx->recs.v[j].name, name) == 0) {
                      m = &ctx->recs.v[j]; break; } }
            if (!m) continue;   /* not a master setting: skip in -show */
            if (value_eq(eff->value, m->value)) continue;

            /* who set the effective value: last non-target record.  (If no
               non-target record exists the value is inherited and the diff
               would not show, so setline is always nonzero here.) */
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
 * MAIN
 *=================================================================================================*/

static void usage(void)
{
    fprintf(stderr,
        "hbconfig - RomWBW HBIOS configuration tool\n"
        "usage:\n"
        "  hbconfig -show <config-file>\n"
        "  hbconfig -show <platform> <config>\n"
        "    (locates Config/<platform>_<config>.asm relative to cwd)\n");
    exit(2);
}

int main(int argc, char **argv)
{
    ParseCtx ctx;
    char path[1024];

    memset(&ctx, 0, sizeof(ctx));

    if (argc < 3) usage();

    if (strcmp(argv[1], "-show") == 0) {
        if (argc == 3) {
            snprintf(path, sizeof(path), "%s", argv[2]);
        } else if (argc == 4) {
            snprintf(path, sizeof(path), "Config/%s_%s.asm", argv[2], argv[3]);
        } else usage();

        ctx.target_path = xstrdup(path);
        parse_file(&ctx, path, 0, 1, 0);
        if (ctx.error) return 1;
        return cmd_show(&ctx);
    }

    usage();
    return 2;
}
