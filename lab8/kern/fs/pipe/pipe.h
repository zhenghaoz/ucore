#ifndef __KERN_FS_PIPE_DEV_H__
#define __KERN_FS_PIPE_DEV_H__

#include <defs.h>

struct inode;
struct iobuf;

#define PIPE_BUFFER_SIZE 4096

struct pipe {
    size_t p_head;
    size_t p_tail;
    wait_queue_t p_read_queue;
    wait_queue_t p_write_queue;
    char * p_buffer;
};

#endif /* !__KERN_FS_PIPE_DEV_H__ */