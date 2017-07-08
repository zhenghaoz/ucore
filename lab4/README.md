## 练习1：分配并初始化一个进程控制块（需要编码）

对于刚分配的进程控制块：

- state为PROC_UNINIT，表示未初始化；
- pid为-1，表示未分配；
- cr3为boot_cr3；
- 对于其他的成员，将指针置为NULL，将结构体和进程名称使用`memset`清零。

```c
static struct proc_struct *alloc_proc(void) {
    ...
        proc->state = PROC_UNINIT;
        proc->pid = -1;
        proc->runs = 0;
        proc->kstack = NULL;
        proc->need_resched = 0;
        proc->parent = NULL;
        proc->mm = NULL;
        memset(&(proc->context), 0, sizeof(struct context));
        proc->tf = NULL;
        proc->cr3 = boot_cr3;
        proc->flags = 0;
        memset(proc->name, 0, PROC_NAME_LEN+1);
	...
}
```

1. 请说明proc_struct中`struct context context`和`struct trapframe *tf`成员变量含义和在本实验中的作用是啥？


**context**：上下文，用于在上下文切换时保存当前EBX、ECX、EDX、ESI、EDI、ESP、EBP、EIP八个寄存器；

**tf**：中断帧，调度往往发生在时钟中断的时候，所以调度执行进程的时候，需要进行中断返回。


## 练习2：为新创建的内核线程分配资源（需要编码）

新创建的内核线程分配资源的过程如下：

- 首先调用`alloc_proc`来申请一个初始化后的进程控制块；
- 调用`setup_kstack`为内核进程（线程）建立栈空间；
- 调用`copy_mm`拷贝或者共享内存空间；
- 调用`copy_thread`建立trapframe以及上下文；
- 调用`get_pid()`为进程分配一个PID；
- 将进程控制块加入哈希表和链表；
- 最后，返回进程的PID。

```c
int do_fork(uint32_t clone_flags, uintptr_t stack, struct trapframe *tf) {
	...
    if ((proc = alloc_proc()) == NULL)
        goto fork_out;
    if ((ret = setup_kstack(proc)) != 0)
        goto fork_out;
    if ((ret = copy_mm(clone_flags, proc)) != 0)
        goto fork_out;
    copy_thread(proc, stack, tf);
    ret = proc->pid = get_pid();
    hash_proc(proc);
    list_add(&proc_list, &(proc->list_link));
    wakeup_proc(proc);
	...
}
```

1. 请说明ucore是否做到给每个新fork的线程一个唯一的id？


线程的PID由`get_pid`函数产生，该函数中包含了两个静态变量`last_pid`以及`next_safe`。`last_pid`变量保存上一次分配的PID，而next_safe和last_pid一起表示一段可以使用的PID取值范围$$(last\_pid,next\_safe)$$，同时要求PID的取值范围为$$[1,MAX\_PID]$$，`last_pid`和`next_safe`被初始化为`MAX_PID`。每次调用`get_pid`时，除了确定一个可以分配的PID外，还需要确定`next_safe`来实现均摊以此优化时间复杂度，PID的确定过程中会检查所有进程的PID来确保PID是唯一的。

## 练习3：阅读代码，理解 proc_run 函数和它调用的函数如何完成进程切换的。（无编码工作）

`proc_run`的执行过程为：

- 保存IF位并且禁止中断；
- 将current指针指向将要执行的进程；
- 更新TSS中的栈顶指针；
- 加载新的页表；
- 调用switch_to进行上下文切换；
- 当执行proc_run的进程恢复执行之后，需要恢复IF位。

1. 在本实验的执行过程中，创建且运行了几个内核线程？

一共有两个内核线程：

**idleproc**，线程的功能是不断寻找可以调度的任务执行；

**initproc**，本实验中的功能为输出一段字符串。

2. 语句`local_intr_save(intr_flag);....local_intr_restore(intr_flag);`在这里有何作用?请说明理由

在进行进程切换的时候，需要避免出现中断干扰这个过程，所以需要在上下文切换期间清除IF位屏蔽中断，并且在进程恢复执行后恢复IF位。

## 扩展练习Challenge：实现支持任意大小的内存分配算法

通过少量的修改，即可使用实验2扩展练习实现的Slub算法。

- 初始化Slub算法：在初始化物理内存最后初始化Slub；

```c
void pmm_init(void) {
	...
    kmem_int();
}
```

- 在vmm.c中使用Slub算法：

为了使用Slub算法，需要声明仓库的指针。

```c
struct kmem_cache_t *vma_cache = NULL;
struct kmem_cache_t *mm_cache = NULL;
```

在虚拟内存初始化时创建仓库。

```c
void vmm_init(void) {
    mm_cache = kmem_cache_create("mm", sizeof(struct mm_struct), NULL, NULL);
    vma_cache = kmem_cache_create("vma", sizeof(struct vma_struct), NULL, NULL);
	...
}
```

在mm_create和vma_create中使用Slub算法。

```c
struct mm_struct *mm_create(void) {
    struct mm_struct *mm = kmem_cache_alloc(mm_cache);
	...
}

struct vma_struct *vma_create(uintptr_t vm_start, uintptr_t vm_end, uint32_t vm_flags) {
    struct vma_struct *vma = kmem_cache_alloc(vma_cache);
	...
}
```

在mm_destroy中释放内存。

```c
void
mm_destroy(struct mm_struct *mm) {
	...
    while ((le = list_next(list)) != list) {
		...
        kmem_cache_free(mm_cache, le2vma(le, list_link));  //kfree vma        
    }
    kmem_cache_free(mm_cache, mm); //kfree mm
	...
}
```

- 在proc.c中使用Slub算法：

声明仓库指针。

```c
struct kmem_cache_t *proc_cache = NULL;
```

在初始化函数中创建仓库。

```c
void proc_init(void) {
 	...
    proc_cache = kmem_cache_create("proc", sizeof(struct proc_struct), NULL, NULL);
  	...
}
```

在alloc_proc中使用Slub算法。

```c
static struct proc_struct *alloc_proc(void) {
    struct proc_struct *proc = kmem_cache_alloc(proc_cache);
  	...
}
```

本实验没有涉及进程结束后PCB回收，不需要回收内存。

## 遇到的问题

#### 关于uCore中TSS的使用

在uCore中，上下文的切换通过替换EBX、ECX、EDX、ESI、EDI、ESP、EBP、EIP八个寄存器的值实现，而在上学期的《30天自制操作系统》中，上下文切换通过跳转到TSS所在地址进行任务切换。这两种任务切换方式有什么区别？