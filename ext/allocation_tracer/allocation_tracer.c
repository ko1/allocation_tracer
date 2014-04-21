/*
 * allocation tracer: adds GC::Tracer::start_allocation_tracing
 *
 * By Koichi Sasada
 * created at Thu Apr 17 03:50:38 2014.
 */

#include "ruby/ruby.h"
#include "ruby/debug.h"
#include <assert.h>

size_t rb_obj_memsize_of(VALUE obj); /* in gc.c */

static VALUE rb_mAllocationTracer;

struct allocation_info {
    struct allocation_info *next;

    /* all of information don't need marking. */
    int living;
    VALUE flags;
    VALUE klass;
    size_t generation;
    size_t memsize;

    /* allocator info */
    const char *path;
    unsigned long line;
};

#define MAX_KEY_DATA 4

#define KEY_PATH    (1<<1)
#define KEY_LINE    (1<<2)
#define KEY_TYPE    (1<<3)
#define KEY_CLASS   (1<<4)

#define MAX_VAL_DATA 6

#define VAL_COUNT     (1<<1)
#define VAL_OLDCOUNT  (1<<2)
#define VAL_TOTAL_AGE (1<<3)
#define VAL_MIN_AGE   (1<<4)
#define VAL_MAX_AGE   (1<<5)
#define VAL_MEMSIZE   (1<<6)

struct traceobj_arg {
    int running;
    int keys, vals;
    st_table *aggregate_table;  /* user defined key -> [count, total_age, max_age, min_age] */
    st_table *object_table;     /* obj (VALUE)      -> allocation_info */
    st_table *str_table;        /* cstr             -> refcount */
    struct allocation_info *freed_allocation_info;
};

static char *
keep_unique_str(st_table *tbl, const char *str)
{
    st_data_t n;

    if (str && st_lookup(tbl, (st_data_t)str, &n)) {
	char *result;

	st_insert(tbl, (st_data_t)str, n+1);
	st_get_key(tbl, (st_data_t)str, (st_data_t *)&result);

	return result;
    }
    else {
	return NULL;
    }
}

static const char *
make_unique_str(st_table *tbl, const char *str, long len)
{
    if (!str) {
	return NULL;
    }
    else {
	char *result;

	if ((result = keep_unique_str(tbl, str)) == NULL) {
	    result = (char *)ruby_xmalloc(len+1);
	    strncpy(result, str, len);
	    result[len] = 0;
	    st_add_direct(tbl, (st_data_t)result, 1);
	}
	return result;
    }
}

static void
delete_unique_str(st_table *tbl, const char *str)
{
    if (str) {
	st_data_t n;

	st_lookup(tbl, (st_data_t)str, &n);
	if (n == 1) {
	    st_delete(tbl, (st_data_t *)&str, 0);
	    ruby_xfree((char *)str);
	}
	else {
	    st_insert(tbl, (st_data_t)str, n-1);
	}
    }
}

struct memcmp_key_data {
    int n;
    st_data_t data[MAX_KEY_DATA];
};

static int
memcmp_hash_compare(st_data_t a, st_data_t b)
{
    struct memcmp_key_data *k1 = (struct memcmp_key_data *)a;
    struct memcmp_key_data *k2 = (struct memcmp_key_data *)b;
    return memcmp(&k1->data[0], &k2->data[0], k1->n * sizeof(st_data_t));
}

static st_index_t
memcmp_hash_hash(st_data_t a)
{
    struct memcmp_key_data *k = (struct memcmp_key_data *)a;
    return rb_memhash(k->data, sizeof(st_data_t) * k->n);
}

static const struct st_hash_type memcmp_hash_type = {
    memcmp_hash_compare, memcmp_hash_hash
};

static struct traceobj_arg *tmp_trace_arg; /* TODO: Do not use global variables */

static struct traceobj_arg *
get_traceobj_arg(void)
{
    if (tmp_trace_arg == 0) {
	tmp_trace_arg = ALLOC_N(struct traceobj_arg, 1);
	tmp_trace_arg->running = 0;
	tmp_trace_arg->keys = 0;
	tmp_trace_arg->vals = VAL_COUNT | VAL_OLDCOUNT | VAL_TOTAL_AGE | VAL_MAX_AGE | VAL_MIN_AGE | VAL_MEMSIZE;
	tmp_trace_arg->aggregate_table = st_init_table(&memcmp_hash_type);
	tmp_trace_arg->object_table = st_init_numtable();
	tmp_trace_arg->str_table = st_init_strtable();
	tmp_trace_arg->freed_allocation_info = NULL;
    }
    return tmp_trace_arg;
}

static int
free_keys_i(st_data_t key, st_data_t value, void *data)
{
    ruby_xfree((void *)key);
    return ST_CONTINUE;
}

static int
free_values_i(st_data_t key, st_data_t value, void *data)
{
    ruby_xfree((void *)value);
    return ST_CONTINUE;
}

static int
free_key_values_i(st_data_t key, st_data_t value, void *data)
{
    ruby_xfree((void *)key);
    ruby_xfree((void *)value);
    return ST_CONTINUE;
}

static void
clear_traceobj_arg(void)
{
    struct traceobj_arg * arg = get_traceobj_arg();

    st_foreach(arg->aggregate_table, free_key_values_i, 0);
    st_clear(arg->aggregate_table);
    st_foreach(arg->object_table, free_values_i, 0);
    st_clear(arg->object_table);
    st_foreach(arg->str_table, free_keys_i, 0);
    st_clear(arg->str_table);
}

static struct allocation_info *
create_allocation_info(void)
{
    return (struct allocation_info *)ruby_xmalloc(sizeof(struct allocation_info));
}

static void
free_allocation_info(struct traceobj_arg *arg, struct allocation_info *info)
{
    delete_unique_str(arg->str_table, info->path);
    ruby_xfree(info);
}

static void
newobj_i(VALUE tpval, void *data)
{
    struct traceobj_arg *arg = (struct traceobj_arg *)data;
    struct allocation_info *info;
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    VALUE obj = rb_tracearg_object(tparg);
    VALUE path = rb_tracearg_path(tparg);
    VALUE line = rb_tracearg_lineno(tparg);
    VALUE klass = RBASIC_CLASS(obj);
    const char *path_cstr = RTEST(path) ? make_unique_str(arg->str_table, RSTRING_PTR(path), RSTRING_LEN(path)) : NULL;

    if (st_lookup(arg->object_table, (st_data_t)obj, (st_data_t *)&info)) {
	if (info->living) {
	    /* do nothing. there is possibility to keep living if FREEOBJ events while suppressing tracing */
	}
	/* reuse info */
	delete_unique_str(arg->str_table, info->path);
    }
    else {
	info = create_allocation_info();
    }

    info->next = NULL;
    info->flags = RBASIC(obj)->flags;
    info->living = 1;
    info->memsize = 0;
    info->klass = (RTEST(klass) && !RB_TYPE_P(obj, T_NODE)) ? rb_class_real(klass) : Qnil;
    info->generation = rb_gc_count();

    info->path = path_cstr;
    info->line = NUM2INT(line);

    st_insert(arg->object_table, (st_data_t)obj, (st_data_t)info);
}

/* file, line, type, klass */
#define MAX_KEY_SIZE 4

static void
aggregate_each_info(struct traceobj_arg *arg, struct allocation_info *info, size_t gc_count)
{
    st_data_t key, val;
    struct memcmp_key_data key_data;
    size_t *val_buff;
    size_t age = (int)(gc_count - info->generation);
    int i = 0;

    if (arg->keys & KEY_PATH) {
	key_data.data[i++] = (st_data_t)info->path;
    }
    if (arg->keys & KEY_LINE) {
	key_data.data[i++] = (st_data_t)info->line;
    }
    if (arg->keys & KEY_TYPE) {
	key_data.data[i++] = (st_data_t)(info->flags & T_MASK);
    }
    if (arg->keys & KEY_CLASS) {
	key_data.data[i++] = info->klass;
    }
    key_data.n = i;
    key = (st_data_t)&key_data;

    if (st_lookup(arg->aggregate_table, key, &val) == 0) {
	struct memcmp_key_data *key_buff = ruby_xmalloc(sizeof(int) + sizeof(st_data_t) * key_data.n);
	key_buff->n = key_data.n;

	for (i=0; i<key_data.n; i++) {
	    key_buff->data[i] = key_data.data[i];
	}
	key = (st_data_t)key_buff;

	/* count, total age, max age, min age */
	val_buff = ALLOC_N(size_t, 6);
	val_buff[0] = val_buff[1] = val_buff[2] = 0;
	val_buff[3] = val_buff[4] = age;
	val_buff[5] = 0;

	if (arg->keys & KEY_PATH) keep_unique_str(arg->str_table, info->path);

	st_insert(arg->aggregate_table, (st_data_t)key_buff, (st_data_t)val_buff);
    }
    else {
	val_buff = (size_t *)val;
    }

    val_buff[0] += 1;
    if (info->flags & FL_PROMOTED) val_buff[1] += 1;
    val_buff[2] += age;
    if (val_buff[3] > age) val_buff[3] = age; /* min */
    if (val_buff[4] < age) val_buff[4] = age; /* max */
    val_buff[5] += info->memsize;
}

static void
aggregate_freed_info(void *data)
{
    size_t gc_count = rb_gc_count();
    struct traceobj_arg *arg = (struct traceobj_arg *)data;
    struct allocation_info *info = arg->freed_allocation_info;

    arg->freed_allocation_info = NULL;

    while (info) {
	struct allocation_info *next_info = info->next;
	aggregate_each_info(arg, info, gc_count);
	free_allocation_info(arg, info);
	info = next_info;
    }
}

static void
move_to_freed_list(struct traceobj_arg *arg, struct allocation_info *info)
{
    info->next = arg->freed_allocation_info;
    arg->freed_allocation_info = info;
}

static void
freeobj_i(VALUE tpval, void *data)
{
    struct traceobj_arg *arg = (struct traceobj_arg *)data;
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    VALUE obj = rb_tracearg_object(tparg);
    struct allocation_info *info;

    if (st_lookup(arg->object_table, (st_data_t)obj, (st_data_t *)&info)) {
	info->flags = RBASIC(obj)->flags;
	info->memsize = rb_obj_memsize_of(obj);
	move_to_freed_list(arg, info);
	st_delete(arg->object_table, (st_data_t *)&obj, (st_data_t *)&info);
	if (arg->freed_allocation_info == NULL) {
	    rb_postponed_job_register_one(0, aggregate_freed_info, arg);
	}
    }
}

static void
enable_newobj_hook(void)
{
    VALUE newobj_hook;

    if ((newobj_hook = rb_ivar_get(rb_mAllocationTracer, rb_intern("newobj_hook"))) == Qnil) {
	rb_raise(rb_eRuntimeError, "not started.");
    }
    if (rb_tracepoint_enabled_p(newobj_hook)) {
	rb_raise(rb_eRuntimeError, "newobj hooks is already enabled.");
    }

    rb_tracepoint_enable(newobj_hook);
}

static void
disable_newobj_hook(void)
{
    VALUE newobj_hook;

    if ((newobj_hook = rb_ivar_get(rb_mAllocationTracer, rb_intern("newobj_hook"))) == Qnil) {
	rb_raise(rb_eRuntimeError, "not started.");
    }
    if (rb_tracepoint_enabled_p(newobj_hook) == Qfalse) {
	rb_raise(rb_eRuntimeError, "newobj hooks is already disabled.");
    }

    rb_tracepoint_disable(newobj_hook);
}

static void
check_tracer_running(void)
{
    struct traceobj_arg * arg = get_traceobj_arg();

    if (!arg->running) {
	rb_raise(rb_eRuntimeError, "not started yet");
    }
}

static void
start_alloc_hooks(VALUE mod)
{
    VALUE newobj_hook, freeobj_hook;
    struct traceobj_arg *arg = get_traceobj_arg();

    if ((newobj_hook = rb_ivar_get(rb_mAllocationTracer, rb_intern("newobj_hook"))) == Qnil) {
	rb_ivar_set(rb_mAllocationTracer, rb_intern("newobj_hook"), newobj_hook = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_NEWOBJ, newobj_i, arg));
	rb_ivar_set(rb_mAllocationTracer, rb_intern("freeobj_hook"), freeobj_hook = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_FREEOBJ, freeobj_i, arg));
    }
    else {
	freeobj_hook = rb_ivar_get(rb_mAllocationTracer, rb_intern("freeobj_hook"));
    }

    rb_tracepoint_enable(newobj_hook);
    rb_tracepoint_enable(freeobj_hook);
}

static VALUE
stop_alloc_hooks(VALUE self)
{
    struct traceobj_arg * arg = get_traceobj_arg();
    check_tracer_running();

    {
	VALUE newobj_hook = rb_ivar_get(rb_mAllocationTracer, rb_intern("newobj_hook"));
	VALUE freeobj_hook = rb_ivar_get(rb_mAllocationTracer, rb_intern("freeobj_hook"));
	rb_tracepoint_disable(newobj_hook);
	rb_tracepoint_disable(freeobj_hook);

	clear_traceobj_arg();

	arg->running = 0;
    }

    return Qnil;
}

static const char *
type_name(int type)
{
    switch (type) {
#define TYPE_NAME(t) case (t): return #t;
	TYPE_NAME(T_NONE);
	TYPE_NAME(T_OBJECT);
	TYPE_NAME(T_CLASS);
	TYPE_NAME(T_MODULE);
	TYPE_NAME(T_FLOAT);
	TYPE_NAME(T_STRING);
	TYPE_NAME(T_REGEXP);
	TYPE_NAME(T_ARRAY);
	TYPE_NAME(T_HASH);
	TYPE_NAME(T_STRUCT);
	TYPE_NAME(T_BIGNUM);
	TYPE_NAME(T_FILE);
	TYPE_NAME(T_MATCH);
	TYPE_NAME(T_COMPLEX);
	TYPE_NAME(T_RATIONAL);
	TYPE_NAME(T_NIL);
	TYPE_NAME(T_TRUE);
	TYPE_NAME(T_FALSE);
	TYPE_NAME(T_SYMBOL);
	TYPE_NAME(T_FIXNUM);
	TYPE_NAME(T_UNDEF);
	TYPE_NAME(T_NODE);
	TYPE_NAME(T_ICLASS);
	TYPE_NAME(T_ZOMBIE);
	TYPE_NAME(T_DATA);
#undef TYPE_NAME
    }
    return "unknown";
}

struct arg_and_result {
    struct traceobj_arg *arg;
    VALUE result;
};

static int
aggregate_result_i(st_data_t key, st_data_t val, void *data)
{
    struct arg_and_result *aar = (struct arg_and_result *)data;
    struct traceobj_arg *arg = aar->arg;
    VALUE result = aar->result;

    size_t *val_buff = (size_t *)val;
    struct memcmp_key_data *key_buff = (struct memcmp_key_data *)key;
    VALUE v = rb_ary_new3(6,
			  INT2FIX(val_buff[0]), INT2FIX(val_buff[1]),
			  INT2FIX(val_buff[2]), INT2FIX(val_buff[3]),
			  INT2FIX(val_buff[4]), INT2FIX(val_buff[5]));
    VALUE k = rb_ary_new();
    int i = 0;
    static VALUE type_symbols[T_MASK] = {0};

    if (type_symbols[0] == 0) {
	int i;
	for (i=0; i<T_MASK; i++) {
	    type_symbols[i] = ID2SYM(rb_intern(type_name(i)));
	}
    }

    i = 0;
    if (arg->keys & KEY_PATH) {
	const char *path = (const char *)key_buff->data[i++];
	if (path) {
	    rb_ary_push(k, rb_str_new2(path));
	    delete_unique_str(arg->str_table, path);
	}
	else {
	    rb_ary_push(k, Qnil);
	}
    }
    if (arg->keys & KEY_LINE) {
	rb_ary_push(k, INT2FIX((int)key_buff->data[i++]));
    }
    if (arg->keys & KEY_TYPE) {
	int sym_index = key_buff->data[i++];
	assert(T_MASK > sym_index);
	rb_ary_push(k, type_symbols[sym_index]);
    }
    if (arg->keys & KEY_CLASS) {
	VALUE klass = key_buff->data[i++];
	if (RTEST(klass) && BUILTIN_TYPE(klass) == T_CLASS) {
	    klass = rb_class_real(klass);
	    rb_ary_push(k, klass);
	    /* TODO: actually, it is dangerous code because klass can be sweeped */
	    /*       So that class specifier is hidden feature                   */
	}
	else {
	    rb_ary_push(k, Qnil);
	}
    }

    rb_hash_aset(result, k, v);

    return ST_CONTINUE;
}

static int
aggregate_live_object_i(st_data_t key, st_data_t val, void *data)
{
    VALUE obj = (VALUE)key;
    struct allocation_info *info = (struct allocation_info *)val;
    size_t gc_count = rb_gc_count();
    struct traceobj_arg *arg = (struct traceobj_arg *)data;

    if (BUILTIN_TYPE(obj) == (info->flags & T_MASK)) {
	VALUE klass = RBASIC_CLASS(obj);
	info->flags = RBASIC(obj)->flags;
	info->klass = (RTEST(klass) && !RB_TYPE_P(obj, T_NODE)) ? rb_class_real(klass) : Qnil;
    }

    aggregate_each_info(arg, info, gc_count);

    return ST_CONTINUE;
}

static VALUE
aggregate_result(struct traceobj_arg *arg)
{
    struct arg_and_result aar;
    aar.result = rb_hash_new();
    aar.arg = arg;

    /* aggregated table -> Ruby hash */
    aggregate_freed_info(arg);
    st_foreach(arg->aggregate_table, aggregate_result_i, (st_data_t)&aar);

    /* collect live aggregate table */
    {
	st_table *dead_object_aggregate_table = arg->aggregate_table;

	/* make live object aggregate table */
	arg->aggregate_table = st_init_table(&memcmp_hash_type);
	st_foreach(arg->object_table, aggregate_live_object_i, (st_data_t)arg);

	/* aggregate table -> Ruby hash */
	st_foreach(arg->aggregate_table, aggregate_result_i, (st_data_t)&aar);

	/* remove live object aggregate table */
	st_foreach(arg->aggregate_table, free_key_values_i, 0);
	st_free_table(arg->aggregate_table);

	arg->aggregate_table = dead_object_aggregate_table;
    }
    return aar.result;
}

static VALUE
allocation_tracer_stop(VALUE self)
{
    VALUE result = aggregate_result(get_traceobj_arg());
    stop_alloc_hooks(self);
    return result;
}

static VALUE
allocation_tracer_result(VALUE self)
{
    VALUE result;
    struct traceobj_arg *arg = get_traceobj_arg();

    check_tracer_running();

    disable_newobj_hook();
    result = aggregate_result(arg);
    enable_newobj_hook();
    return result;
}

static VALUE
allocation_tracer_clear(VALUE self)
{
    clear_traceobj_arg();
    return Qnil;
}

static VALUE
allocation_tracer_trace_i(VALUE self)
{
    rb_yield(Qnil);
    return allocation_tracer_result(self);
}

static VALUE
allocation_tracer_trace(VALUE self)
{
    struct traceobj_arg * arg = get_traceobj_arg();

    if (arg->running) {
	rb_raise(rb_eRuntimeError, "can't run recursivly");
    }
    else {
	arg->running = 1;
	if (arg->keys == 0) arg->keys = KEY_PATH | KEY_LINE;
	start_alloc_hooks(rb_mAllocationTracer);

	if (rb_block_given_p()) {
	    return rb_ensure(allocation_tracer_trace_i, self, stop_alloc_hooks, Qnil);
	}
    }

    return Qnil;
}

static VALUE
allocation_tracer_pause(VALUE self)
{
    check_tracer_running();
    disable_newobj_hook();
    return Qnil;
}

static VALUE
allocation_tracer_resume(VALUE self)
{
    check_tracer_running();
    enable_newobj_hook();
    return Qnil;
}

static VALUE
allocation_tracer_setup(int argc, VALUE *argv, VALUE self)
{
    struct traceobj_arg * arg = get_traceobj_arg();

    if (arg->running) {
	rb_raise(rb_eRuntimeError, "can't change configuration during running");
    }
    else {
	if (argc >= 1) {
	    int i;
	    VALUE ary = rb_check_array_type(argv[0]);

	    arg->keys = 0;

	    for (i=0; i<(int)RARRAY_LEN(ary); i++) {
		if (RARRAY_AREF(ary, i) == ID2SYM(rb_intern("path"))) arg->keys |= KEY_PATH;
		else if (RARRAY_AREF(ary, i) == ID2SYM(rb_intern("line"))) arg->keys |= KEY_LINE;
		else if (RARRAY_AREF(ary, i) == ID2SYM(rb_intern("type"))) arg->keys |= KEY_TYPE;
		else if (RARRAY_AREF(ary, i) == ID2SYM(rb_intern("class"))) arg->keys |= KEY_CLASS;
		else {
		    rb_raise(rb_eArgError, "not supported key type");
		}
	    }
	}
    }

    if (argc == 0) {
	arg->keys = KEY_PATH | KEY_LINE;
    }
    return Qnil;
}

VALUE
allocation_tracer_header(VALUE self)
{
    VALUE ary = rb_ary_new();
    struct traceobj_arg * arg = get_traceobj_arg();

    if (arg->keys & KEY_PATH) rb_ary_push(ary, ID2SYM(rb_intern("path")));
    if (arg->keys & KEY_LINE) rb_ary_push(ary, ID2SYM(rb_intern("line")));
    if (arg->keys & KEY_TYPE) rb_ary_push(ary, ID2SYM(rb_intern("type")));
    if (arg->keys & KEY_CLASS) rb_ary_push(ary, ID2SYM(rb_intern("class")));

    if (arg->vals & VAL_COUNT) rb_ary_push(ary, ID2SYM(rb_intern("count")));
    if (arg->vals & VAL_OLDCOUNT) rb_ary_push(ary, ID2SYM(rb_intern("old_count")));
    if (arg->vals & VAL_TOTAL_AGE) rb_ary_push(ary, ID2SYM(rb_intern("total_age")));
    if (arg->vals & VAL_MIN_AGE) rb_ary_push(ary, ID2SYM(rb_intern("min_age")));
    if (arg->vals & VAL_MAX_AGE) rb_ary_push(ary, ID2SYM(rb_intern("max_age")));
    if (arg->vals & VAL_MEMSIZE) rb_ary_push(ary, ID2SYM(rb_intern("total_memsize")));
    return ary;
}

void
Init_allocation_tracer(void)
{
    VALUE rb_mObjSpace = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
    VALUE mod = rb_mAllocationTracer = rb_define_module_under(rb_mObjSpace, "AllocationTracer");

    /* allocation tracer methods */
    rb_define_module_function(mod, "trace", allocation_tracer_trace, 0);
    rb_define_module_function(mod, "start", allocation_tracer_trace, 0);
    rb_define_module_function(mod, "stop", allocation_tracer_stop, 0);
    rb_define_module_function(mod, "pause", allocation_tracer_pause, 0);
    rb_define_module_function(mod, "resume", allocation_tracer_resume, 0);

    rb_define_module_function(mod, "result", allocation_tracer_result, 0);
    rb_define_module_function(mod, "clear", allocation_tracer_clear, 0);
    rb_define_module_function(mod, "setup", allocation_tracer_setup, -1);
    rb_define_module_function(mod, "header", allocation_tracer_header, 0);
}
