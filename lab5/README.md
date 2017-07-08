## 练习1: 加载应用程序并执行（需要编码）

`load_icode`函数需要填写的部分为：

- 将`trapframe`的代码段设为`USER_CS`；
- 将`trapframe`的数据段、附加段、堆栈段设为`USER_DS`；
- 将`trapframe`的栈顶指针设为`USTACKTOP`；
- 将`trapframe`的代码段指针设为ELF的入口地址`elf->e_entry`；
- 将`trapframe`中EFLAGS的IF置为1。

```c
static int load_icode(unsigned char *binary, size_t size) {
	...
    tf->tf_cs = USER_CS;
    tf->tf_ds = tf->tf_es = tf->tf_ss = USER_DS;
    tf->tf_esp = USTACKTOP;
    tf->tf_eip = elf->e_entry;
    tf->tf_eflags = tf->tf_eflags | FL_IF;
	...
}
```

进程切换总是在内核态中发生，当内核选择一个进程执行的时候，首先切换内核态的上下文（EBX、ECX、EDX、ESI、EDI、ESP、EBP、EIP八个寄存器）以及内核栈。完成内核态切换之后，内核需要使用IRET指令将trapframe中的用户态上下文恢复出来，返回到进程态，在用户态中执行进程。

## 练习2: 父进程复制自己的内存空间给子进程（需要编码）

需要补充的操作为：

- 获取源页面和目标页面的内核虚拟地址；
- 使用`memset`将源页面的数据拷贝到目标页面；
- 建立目标页面和地址的映射关系。 

```c
int copy_range(pde_t *to, pde_t *from, uintptr_t start, uintptr_t end, bool share) {
	...
        uintptr_t src_kvaddr = page2kva(page);
        uintptr_t dst_kvaddr = page2kva(npage);
        memcpy(dst_kvaddr, src_kvaddr, PGSIZE);
        page_insert(to, npage, start, perm);
	...
}
```

## 练习3: 阅读分析源代码，理解进程执行 fork/exec/wait/exit 的实现，以及系统调用的实现（不需要编码）

#### fork实现

- 首先检查当前总进程数目是否到达限制，如果到达限制，那么返回`E_NO_FREE_PROC`；
- 调用`alloc_proc`来申请一个初始化后的进程控制块；
- 调用`setup_kstack`为内核进程（线程）建立栈空间；
- 调用`copy_mm`拷贝或者共享内存空间；
- 调用`copy_thread`建立trapframe以及上下文；
- 调用`get_pid()`为进程分配一个PID；
- 将进程控制块加入哈希表和链表；
- 最后，返回进程的PID。

#### exec实现

- 检查进程名称的地址和长度是否合法，如果合法，那么将名称暂时保存在函数栈中；
- 原先的内存内容不再需要，将进程的内存全部释放；
- 调用`load_icode`将代码加载进内存，如果加载错误，那么调用`panic`报错；
- 调用`set_proc_name`设置进程名称。

#### wait实现

- 首先检查用于保存返回码的`code_store`指针地址位于合法的范围内；
- 根据PID找到需要等待的子进程PCB：
  - 如果没有需要等待的子进程，那么返回`E_BAD_PROC`；
  - 如果子进程正在可执行状态中，那么将当前进程休眠，在被唤醒后再次尝试；
  - 如果子进程处于僵尸状态，那么回收PCB。

#### exit实现

- 释放进程的虚拟内存空间；
- 设置当期进程状态为`PROC_ZOMBIE`同时设置返回码；
- 如果父进程等待当期进程，那么将父进程唤醒；
- 将当前进程的所有子进程变为init的子进程；
- 主动调用调度函数进行调度。

#### 系统调用实现

**对于应用程序：**为了使用系统调用，应用程序指令需要将需要使用的系统调用编号放入EAX寄存器，系统调用最多支持5个参数，分别放在EDX、ECX、EBX、EDI、ESI这5个寄存器中，然后使用`INT 0x80`指令进入内核态。

**对于系统内核：**操作系统根据中断号0x80得知是系统调用时，根据系统调用号和参数执行相应的操作。

1. 请分析fork/exec/wait/exit在实现中是如何影响进程的执行状态的？


**fork：**创建了一个子进程，然后将子进程的状态从**UNINIT**态变为**RUNNABLE**态，但是不改变父进程的状态。

**exec：**不改变进程的状态。

**wait：**如果有已经结束的子进程或者没有子进程，那么调用会立刻结束，不影响进程状态；否则，进程需要等待子进程结束，进程从**RUNNIG**态变为**SLEEPING**态。

**exit：**进程从**RUNNIG**态变为**ZOMBIE**态。


2. 请给出ucore中一个用户态进程的执行状态生命周期图（包执行状态，执行状态之间的变换关系，以及产生变换的事件或函数调用）。


<center><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="461px" height="468px" version="1.1"><defs/><g transform="translate(0.5,0.5)"><path d="M 60 147 L 60 220.63" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 60 225.88 L 56.5 218.88 L 60 220.63 L 63.5 218.88 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><g transform="translate(20.5,184.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="72" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;background-color:#ffffff;"><div><span>wakeup_proc</span></div></div></div></foreignObject><text x="36" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><ellipse cx="60" cy="107" rx="60" ry="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(39.5,100.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="41" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 42px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><div>UNINIT</div></div></div></foreignObject><text x="21" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">&lt;div&gt;UNINIT&lt;/div&gt;</text></switch></g><ellipse cx="60" cy="427" rx="60" ry="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(36.5,420.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="46" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 47px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><div>ZOMBIE</div></div></div></foreignObject><text x="23" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">&lt;div&gt;ZOMBIE&lt;/div&gt;</text></switch></g><path d="M 60 307 Q 60 347 60 380.63" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 60 385.88 L 56.5 378.88 L 60 380.63 L 63.5 378.88 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><g transform="translate(63.5,331.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="34" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;background-color:#ffffff;"><div><span>do_kill</span></div></div></div></foreignObject><text x="17" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><path d="M 107.9 297.4 Q 107.9 297.4 352.1 396.6" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 103.04 295.42 L 110.84 294.81 L 107.9 297.4 L 108.2 301.3 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 356.96 398.58 L 349.16 399.19 L 352.1 396.6 L 351.8 392.7 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><g transform="translate(225.5,321.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="49" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;background-color:#ffffff;"><div><span>schedule</span></div></div></div></foreignObject><text x="25" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><ellipse cx="60" cy="267" rx="60" ry="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(26.5,260.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="66" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 67px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><div>RUNNABLE</div></div></div></foreignObject><text x="33" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">&lt;div&gt;RUNNABLE&lt;/div&gt;</text></switch></g><path d="M 340 267 L 126.37 267" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 121.12 267 L 128.12 263.5 L 126.37 267 L 128.12 270.5 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><g transform="translate(204.5,251.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="72" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;background-color:#ffffff;"><div><span>wakeup_proc</span></div></div></div></foreignObject><text x="36" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><ellipse cx="400" cy="267" rx="60" ry="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(369.5,260.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="61" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 62px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><div>SLEEPING</div></div></div></foreignObject><text x="31" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">&lt;div&gt;SLEEPING&lt;/div&gt;</text></switch></g><path d="M 340 427 L 126.37 427" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 121.12 427 L 128.12 423.5 L 126.37 427 L 128.12 430.5 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><g transform="translate(209.5,431.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="39" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;background-color:#ffffff;"><div><span>do_exit</span></div></div></div></foreignObject><text x="20" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><path d="M 393 390 L 393.92 315.37" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 393.99 310.12 L 397.4 317.16 L 393.92 315.37 L 390.4 317.07 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><ellipse cx="400" cy="427" rx="60" ry="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(371.5,420.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="57" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 57px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><div>RUNNING</div></div></div></foreignObject><text x="29" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">&lt;div&gt;RUNNING&lt;/div&gt;</text></switch></g><path d="M 60 7 L 60 60.63" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 60 65.88 L 56.5 58.88 L 60 60.63 L 63.5 58.88 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><g transform="translate(72.5,39.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="56" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;background-color:#ffffff;"><div><span>alloc_proc</span></div></div></div></foreignObject><text x="28" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><g transform="translate(341.5,339.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="42" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><div><span>do_wait</span></div></div></div></foreignObject><text x="21" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g></g></svg></center>

## 扩展练习 Challenge ：实现 Copy on Write 机制

#### 设置共享标志

在vmm.c中将dup_mmap中的share变量的值改为1，启用共享：

```c
int dup_mmap(struct mm_struct *to, struct mm_struct *from) {
		...
        bool share = 1;
		...
}
```

#### 映射共享页面

在pmm.c中为copy_range添加对共享的处理，如果share为1，那么将子进程的页面映射到父进程的页面。由于两个进程共享一个页面之后，无论任何一个进程修改页面，都会影响另外一个页面，所以需要子进程和父进程对于这个共享页面都保持只读。

```c
int copy_range(pde_t *to, pde_t *from, uintptr_t start, uintptr_t end, bool share) {
	...
        if (*ptep & PTE_P) {
            if ((nptep = get_pte(to, start, 1)) == NULL) {
                return -E_NO_MEM;
            }
            uint32_t perm = (*ptep & PTE_USER);
            //get page from ptep
            struct Page *page = pte2page(*ptep);
            assert(page!=NULL);
            int ret=0;
            if (share) {	
              	// share page
                page_insert(from, page, start, perm & (~PTE_W));
                ret = page_insert(to, page, start, perm & (~PTE_W));
            } else {
                // alloc a page for process B
                struct Page *npage=alloc_page();
                assert(npage!=NULL);
                uintptr_t src_kvaddr = page2kva(page);
                uintptr_t dst_kvaddr = page2kva(npage);
                memcpy(dst_kvaddr, src_kvaddr, PGSIZE);
                ret = page_insert(to, npage, start, perm);
            }
            assert(ret == 0);
        }
		...
    return 0;
}
```

#### 修改时拷贝

当程序尝试修改只读的内存页面的时候，将触发Page Fault中断，在错误代码中P=1,、W/R=1[[OSDev](http://wiki.osdev.org/Page_Fault)]。因此，当错误代码最低两位都为1的时候，说明进程访问了共享的页面，内核需要重新分配页面、拷贝页面内容、建立映射关系：

```c
int do_pgfault(struct mm_struct *mm, uint32_t error_code, uintptr_t addr) {
	...
    if (*ptep == 0) {
        ...
    } else if (error_code & 3 == 3) {	// copy on write
        struct Page *page = pte2page(*ptep);
        struct Page *npage = pgdir_alloc_page(mm->pgdir, addr, perm);
        uintptr_t src_kvaddr = page2kva(page);
        uintptr_t dst_kvaddr = page2kva(npage);
        memcpy(dst_kvaddr, src_kvaddr, PGSIZE);
    } else {
		...
   	}
	...
}
```

## 遇到的问题

#### 如何让uCore支持更大的内存

由于uCore中使用两级页表，一个进程能够使用的内存总大小为：一级页表（页目录）项数×二级页表项数×页大小=1024×1024×4096B=4GB。如果需要支持更大的内存，是否需要引入三级页表？虚拟页面管理机制需要做那些修改？

#### 如何实现waitpid系统调用

在Linux系统中，waitpid不但可以等待父进程的子进程，还能等待子进程创建的子进程，如果想要uCore来实现，需要做那些修改？

## 参考资料

- [Page Fault - OSDev Wiki](http://wiki.osdev.org/Page_Fault)

