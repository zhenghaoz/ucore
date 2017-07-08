#ifndef __KERN_MM_KMALLOC_H__
#define __KERN_MM_KMALLOC_H__

#if 0

#include <defs.h>

#define KMALLOC_MAX_ORDER       10

void kmalloc_init(void);

void *kmalloc(size_t n);
void kfree(void *objp);

#endif

#endif /* !__KERN_MM_KMALLOC_H__ */

