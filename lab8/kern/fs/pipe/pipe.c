#include <defs.h>
#include <stdio.h>
#include <wait.h>
#include <sync.h>
#include <proc.h>
#include <sched.h>
#include <dev.h>
#include <vfs.h>
#include <iobuf.h>
#include <inode.h>
#include <unistd.h>
#include <error.h>
#include <assert.h>

#define pipe_empty(pip) (pip->p_head == pip->p_tail)
#define pipe_full(pip) (pip->p_head == (pip->p_tail+1)%PIPE_BUFFER_SIZE)

static int
pipe_close(struct inode *node) {
#ifdef PIPE_DEBUG
    cprintf("pipe_close\n");
#endif
    return 0;
}

static int
pipe_read(struct inode *node, struct iobuf *iob) {
#ifdef PIPE_DEBUG
    cprintf("pipe_read <io_offset = %d, io_len = %d, io_resid = %d>\n",
        iob->io_offset, iob->io_len, iob->io_resid);
#endif
    struct pipe *pip = vop_info(node, pipe);
    int ret = 0;
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        for (; ret < iob->io_resid; ret ++, pip->p_head = (pip->p_head+1)%PIPE_BUFFER_SIZE) {
        try_again:
            if (!pipe_empty(pip)) {
                *(char *)((iob->io_base) ++) = pip->p_buffer[pip->p_head];
                if (!wait_queue_empty(&(pip->p_write_queue))) {
                    wakeup_queue(&(pip->p_write_queue), WT_IPC, 1);
                }
            }
            else {
                wait_t __wait, *wait = &__wait;
                wait_current_set(&(pip->p_read_queue), wait, WT_IPC);
                local_intr_restore(intr_flag);

                schedule();

                local_intr_save(intr_flag);
                wait_current_del(&(pip->p_read_queue), wait);
                if (wait->wakeup_flags == WT_IPC) {
                    goto try_again;
                }
                break;
            }
        }
    }
    local_intr_restore(intr_flag);
    iob->io_resid -= ret;
    return ret;
}

static int
pipe_write(struct inode *node, struct iobuf *iob) {
#ifdef PIPE_DEBUG
    cprintf("pipe_write <io_offset = %d, io_len = %d, io_resid = %d>\n",
        iob->io_offset, iob->io_len, iob->io_resid);
#endif
    struct pipe *pip = vop_info(node, pipe);
    int ret = 0;
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        for (; ret < iob->io_resid; ret ++, pip->p_tail = (pip->p_tail+1)%PIPE_BUFFER_SIZE) {
        try_again:
            if (!pipe_full(pip)) {
                pip->p_buffer[pip->p_tail] = *(char *)((iob->io_base) ++);
                if (!wait_queue_empty(&(pip->p_read_queue))) {
                    wakeup_queue(&(pip->p_read_queue), WT_IPC, 1);
                }
            }
            else {
                wait_t __wait, *wait = &__wait;
                wait_current_set(&(pip->p_write_queue), wait, WT_IPC);
                local_intr_restore(intr_flag);

                schedule();

                local_intr_save(intr_flag);
                wait_current_del(&(pip->p_write_queue), wait);
                if (wait->wakeup_flags == WT_IPC) {
                    goto try_again;
                }
                break;
            }
        }
    }
    local_intr_restore(intr_flag);
    iob->io_resid -= ret;
    return ret;
}

static int
pipe_reclaim(struct inode *node) {
#ifdef PIPE_DEBUG
    cprintf("pipe_reclaim\n");
#endif
    struct pipe *pip = vop_info(node, pipe);
    kfree(pip->p_buffer);
    vop_kill(node);
    return 0;
}

static const struct inode_ops pipe_node_ops = {
    .vop_magic                      = VOP_MAGIC,
    .vop_close                      = pipe_close,
    .vop_read                       = pipe_read,
    .vop_write                      = pipe_write,
    .vop_reclaim                    = pipe_reclaim
};

struct inode *
pipe_create_inode() {
    char *buffer;
    if ((buffer = kmalloc(PIPE_BUFFER_SIZE)) == NULL) {
        return NULL;
    }
    struct inode *node;
    if ((node = alloc_inode(pipe)) == NULL) {
        kfree(buffer);
        return NULL;
    }
    vop_init(node, &pipe_node_ops, NULL);
    struct pipe *pip = vop_info(node, pipe);
    pip->p_buffer = buffer;
    pip->p_head = 0;
    pip->p_tail = 0;
    wait_queue_init(&(pip->p_read_queue));
    wait_queue_init(&(pip->p_write_queue));
    return node;
}