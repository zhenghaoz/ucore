## 练习1：理解通过make生成执行文件的过程

1. 操作系统镜像文件ucore.img是如何一步一步生成的？

使用Makefile编译时，使用`make = "V="`可以查看Makefile执行的全部命令，可以了解ucore.imh的生成过程：

第一步：编译操作系统内核源代码kern/*以及公共库libs/*，然后链接是生成二进制内核；

第二步：编译bootloader源代码boot/*，链接生成二进制bootloader；

第三步：使用零值初始化磁盘，然后将bootloader写入第一个扇区（主引导扇区），再将内核写入从第二扇区开始的位置。

2. 一个被系统认为是符合规范的硬盘主引导扇区的特征是什么？

sign程序的工作就是将bootloader对齐到一个扇区的大小（512B），然后将主引导扇区的最后两个字节设为`0x55AA`，这是计算机判断主引导扇区是否有效的标志。

## 练习2：使用qemu执行并调试lab1中的软件

1. 从CPU加电后执行的第一条指令开始，单步跟踪BIOS的执行。


在实验文件夹下打开终端，将镜像文件加载到qemu中：

```bash
qemu -S -s -hda ./bin/ucore.img -monitor stdio
```

然后启动gdb后，开启远程调试并且显示汇编代码：

```bash
(gdb)  target remote 127.0.0.1:1234
(gdb)  layout asm
```

使用`stepi`命令可以单步跟踪BIOS的执行

![](https://okl2aaa54.qnssl.com/ucore-1-1.png)

2. 在初始化位置0x7c00设置实地址断点,测试断点正常。

接着设置断点并且继续执行：

```bash
(gdb)  b *0x7c00
(gdb)  c
```

断点设置成功，并且bootloader在断点处停了下来。

![](https://okl2aaa54.qnssl.com/ucore-1-2.png)

3. 从0x7c00开始跟踪代码运行,将单步跟踪反汇编得到的代码与bootasm.S和 bootblock.asm进行比较。

反汇编代码与源代码的差别如下：

- 所有的符号全部变成了实际值，所有和执行代码无关的内容不再存在（注释、标签等）
- 指令名称不同，不再指出操作数长度，少数命令的名称发生变化
- 一些16位的寄存器被32位寄存器替代

4. 自己找一个bootloader或内核中的代码位置，设置断点并进行测试。


## 练习3：分析bootloader进入保护模式的过程

#### 第一步：屏蔽中断

切换的时候当然不希望中断发生，需要使用`cli`来屏蔽中断。

#### 第二步：开启A20

Intel早期的8086 CPU提供了20根地址线，寻址范围就是1MB，但是8086字长为16位，直接使用一个字来表示地址就不够了，所以使用段+偏移地址的方式进行寻址。段+偏移地址的最大寻址范围就是0xFFFF0+0xFFFF=0x10FFEF，这个范围大于1MB，所以如果程序访问了大于1MB的地址空间，就会发生回卷。然而随后的CPU的地址线越来越多，同时为了保证软件的兼容性，A20在实模式下被禁止（永远为0），这样就可以正常回卷了。但是在保护模式下，我们希望能够正常访问所以的内存，就必须将A20开启。

由于历史原因，开启A20由键盘控制器"8042" PS/2 Controller负责[[OSDev](http://wiki.osdev.org/%228042%22_PS/2_Controller)]。A20的开启标志位于PS/2 Controller Output Port的第1位，程序要做的就是修改这一位。8042有两个常用的端口：

| 端口   | 访问方式 | 功能    |
| ---- | ---- | ----- |
| 0x60 | 读/写  | 数据端口  |
| 0x64 | 读    | 状态寄存器 |
| 0x64 | 写    | 命令寄存器 |

在发送命令或者写入数据之前，需要确认8042是否准备就绪，就绪标志在状态字的第1位。

| 位    | 意义                                       |
| ---- | ---------------------------------------- |
| 1    | 输入缓冲状态 (0 = 空, 1 = 满)(在向 0x60 或者 0x64 端口写入数据前需要确认为0) |

写PS/2 Controller Output Port的命令为0xd1，所以开启过程如下：

- 等待8042 Input buffer为空；
- 发送Write Controller Output Port ( 0xd1 ) 命令到命令端口；
- 等待8042 Input buffer为空；
- 将Controller Output Port对应状态字的第1位置1，然后写入8042 Input buffer。

#### 第三步：加载段表GDT

在保护模式下，CPU采用分段存储管理机制，初始情况下，GDT中只有内核代码段和内核数据段，这两个段在内存上的空间是相同的，只是段的权限不同。

####第四步：设置cr0上的保护位

crX寄存器是Intel x86处理器上用于控制处理器行为的寄存器，cr0的第0位用来设置CPU是否开启保护模式[[Wikipedia](https://en.wikipedia.org/wiki/Control_register)]。

#### 第五步：调转到保护模式代码

在本项目中，当控制掉转到保护模式代码之后，bootloader进行段寄存器的初始化后调用bootmain函数，进行内核加载过程。

## 练习4：分析bootloader加载ELF格式的OS的过程

1. bootloader如何读取硬盘扇区的？


bootloader采用PIO的方式从硬盘中读取内核所在的各个扇区。首先，PIO操作相关的端口一共有8个，地址通常为0x1F0~0x1F7[[OSDev](http://wiki.osdev.org/ATA_PIO_Mode)]，这里需要用到的端口如下：

| 端口   | 功能              | 描述          |
| ---- | --------------- | ----------- |
| 0    | 数据端口            | 读取/写入数据     |
| 2    | 扇区数量            | 读取或者写入的扇区数量 |
| s    | 扇区号/ LBA低字节     |             |
| 4    | 柱面号低字节/ LBA中字节  |             |
| 5    | 柱面号高字节 / LBA高字节 |             |
| 6    | 驱动器号            |             |
| 7    | 命令端口 / 状态端口     | 发送命令或者读取状态  |

**磁盘等待**

磁盘的速度显然慢于CPU，在对磁盘进行操作之前，需要检查磁盘是否空闲，这个时候就需要从状态端口读取状态，状态字相关的位如下：

| 位    | 名称   | 功能                   |
| ---- | ---- | -------------------- |
| 6    | RDY  | 当磁盘空闲或者发生错误之后清零，否则置一 |
| 7    | BSY  | 表示驱动器正在写入/读取数据       |

所以每次进行磁盘操作需要反复检查状态字中6,7位，直到BSY为0并且RDY为1时候才可以对磁盘进行操作。

**扇区读取**

每个扇区可以由LBA（逻辑区块地址）指定，28位LBA地址各个字节意义如下：

| 位     | 意义     |
| ----- | ------ |
| 0-7   | 扇区号    |
| 8-15  | 柱面号低字节 |
| 16-23 | 柱面号高字节 |
| 23-27 | 驱动器号   |

所以扇区的读取也就是：

- 等待磁盘空闲
- 将LBA的各个部分送入对应的端口，将读取命令0x20送入命令端口
- 等待磁盘读取完毕
- 从数据端口读取一个扇区的数据


2. bootloader是如何加载ELF格式的OS？


首先，bootloader从磁盘读取8个扇区到内存中，然后检查是否为有效的ELF文件，如果有效，那么根据ELF头中的program header表，将所有的程序段读取到program header中指定的内存偏移地址中。当内核文件加载完毕之后，程序将ELF中的入口偏移地址视为函数指针进行调用，实现向内核的调转。

## 练习5：实现函数调用堆栈跟踪函数

1. 在lab1中完成kdebug.c中函数print_stackframe的实现，可以通过函数print_stackframe来跟踪函数调用堆栈中记录的返回地址。

根据2.3.3.1中关于函数栈的描述，将栈中有意义的数据读取出来即可。

```c
void print_stackframe(void) {
    uint32_t ebp = read_ebp();
    uint32_t eip = read_eip();
    for (int i = 0; i < STACKFRAME_DEPTH; i++) {
        cprintf("ebp:0x%08x eip:0x%08x args:", ebp, eip);
        for (int j = 0; j < 4; j++)
            cprintf("0x%08x ", ((((uint32_t *)ebp)+2))[j]);
        cprintf("\n");
        print_debuginfo(eip-1);
        eip = *(((uint32_t *)ebp)+1);
        ebp = *((uint32_t *)ebp);
    }
}
```

## 练习6：完善中断初始化和处理

1. 中断描述符表（也可简称为保护模式下的中断向量表）中一个表项占多少字节？其中哪几位代表中断处理代码的入口？


终端描述符的结构体定义在mmu.h中：

```c
/* Gate descriptors for interrupts and traps */
struct gatedesc {
    unsigned gd_off_15_0 : 16;        // low 16 bits of offset in segment
    unsigned gd_ss : 16;            // segment selector
    unsigned gd_args : 5;            // # args, 0 for interrupt/trap gates
    unsigned gd_rsv1 : 3;            // reserved(should be zero I guess)
    unsigned gd_type : 4;            // type(STS_{TG,IG32,TG32})
    unsigned gd_s : 1;                // must be 0 (system)
    unsigned gd_dpl : 2;            // descriptor(meaning new) privilege level
    unsigned gd_p : 1;                // Present
    unsigned gd_off_31_16 : 16;        // high bits of offset in segment
};
```

显然占用64位，也就是8字节，中断处理代码的入口由offset和ss指定。

2. 编程完善kern/trap/trap.c中对中断向量表进行初始化的函数idt_init。

除了系统调用中断(T_SYSCALL)使用陷阱门描述符且权限为用户态权限以外，其它中断均使用特权级(DPL)为０的中断门描述符，权限为内核态权限。所以，系统调用中断(T_SYSCALL)的初始化方法就略有不同。

```c
void idt_init(void) {
    extern uintptr_t __vectors[];
    for (int i = 0; i < sizeof(idt) / sizeof(struct gatedesc); i++)
        SETGATE(idt[i], 0, GD_KTEXT, __vectors[i], DPL_KERNEL);
    SETGATE(id[T_SYSCALL], 1, GD_KTEXT, __vectors[T_SYSCALL], DPL_USER);
    lidt(&idt_pd);
}
```

3. 编程完善trap.c中的中断处理函数trap，在对时钟中断进行处理的部分填写trap函数中处理时钟中断的部分，使操作系统每遇到100次时钟中断后，调用print_ticks子程序，向屏幕上打印一行文字”100 ticks”。

```c
...
static int tick_count = 0;
...
static void trap_dispatch(struct trapframe *tf) {
	...
	    tick_count++;
	    if (tick_count == TICK_NUM) {
	        tick_count -= TICK_NUM;
	        print_ticks();
	    }
	    break;
	...
}
```
## 扩展练习 Challenge 1

和当期正在执行的代码的权限有关的字段是EFLAGS寄存器中的指令特权级IOPL、当期代码段选择子特段级CPL、段描述符中的特段级DPL以及段选择子中的特段级RPL。

如果想要正常访问一个段中的数据，必须要求$$MAX(CPL, RPL){\le}DPL$$。RPL背后的设计思想是：允许内核代码加载特权较低的段。但堆栈段寄存器是个例外，它要求CPL，RPL和DPL这3个值必须完全一致，才可以被加载。

当内核陷入中断之后，中断前的EFLAGS、DS、ES、CS、SS都保存在栈中，当中断处理结束之后，这些值都会恢复到相应的寄存器中，所以改变优先级的方法就是对保存在栈中的寄存器值进行修改：

```c
static void trap_dispatch(struct trapframe *tf) {
	...
    case T_SWITCH_TOU:
        if (tf->tf_cs != USER_CS) {
            tf->tf_cs = USER_CS;
            tf->tf_ds = tf->tf_es = tf->tf_ss = USER_DS;
            tf->tf_eflags |= FL_IOPL_MASK;
        }
        break;
    case T_SWITCH_TOK:
        if (tf->tf_cs != KERNEL_CS) {
            tf->tf_cs = KERNEL_CS;
            tf->tf_ds = tf->tf_es = KERNEL_DS;
            tf->tf_eflags &= ~FL_IOPL_MASK;
        }
        break;
	...
}
```

模式的切换通过中断来完成，如果是从内核态转换到用户态的切换，则需要从内核栈中弹出用户态栈的ss和esp，这样也意味着栈也被切换回原先使用的用户态的栈，在调用中断之前需要预留8字节的空间。在调用中断返回之后，恢复中断处理之前的栈指针。

```c
static void lab1_switch_to_user(void) {
    asm volatile (
	    "sub $0x8, %%esp \n"
	    "int %0 \n"
	    "movl %%ebp, %%esp"
	    : 
	    : "i"(T_SWITCH_TOU)
	);
}
```

```c
static void lab1_switch_to_kernel(void) {
    asm volatile (
	    "int %0 \n"
	    "movl %%ebp, %%esp \n"
	    : 
	    : "i"(T_SWITCH_TOK)
	);
}
```

为了能使T_SWITCH_TOK能在用户模式下被调用，需要设置DPL为3，并且设置陷阱标志。

```c
void idt_init(void) {
	...
    SETGATE(idt[T_SWITCH_TOK], 1, GD_KTEXT, __vectors[T_SWITCH_TOK], DPL_USER);
    ...
}
```

## 扩展练习 Challenge 2

方法和扩展练习1一样，使用`print_trapframe(tf)`来验证。

```c
static void trap_dispatch(struct trapframe *tf) {
  	...
    case IRQ_OFFSET + IRQ_KBD:
        c = cons_getc();
        cprintf("kbd [%03d] %c\n", c, c);
        switch (c) {
            case '0':
                if (tf->tf_cs != KERNEL_CS) {
                    tf->tf_cs = KERNEL_CS;
                    tf->tf_ds = tf->tf_es = KERNEL_DS;
                    tf->tf_eflags &= ~FL_IOPL_MASK;
                    print_trapframe(tf);
                }
                break;
            case '3':
                if (tf->tf_cs != USER_CS) {
                    tf->tf_cs = USER_CS;
                    tf->tf_ds = tf->tf_es = tf->tf_ss = USER_DS;
                    tf->tf_eflags |= FL_IOPL_MASK;
                    print_trapframe(tf);
                }
                break;
        }
        break;
	...
}
```

## 实验中遇到的问题

#### 关于GDT指针limit值的疑问

GDT指针需要提供16位的GDT limit值，32位GDT base值，limit在低位，base值在高位[[mouseOS](http://www.mouseos.com/arch/protected.html)]。那么limit可以认为是GDT的大小，但是在uCore的bootasm.S中，limit却是GDT长度减一，不太理解这个地方。

```assembly
gdtdesc:
    .word 0x17                                      # sizeof(gdt) - 1
    .long gdt                                       # address gdt
```

#### gcc编译器的奇怪问题

实验默认使用GCC编译器对内核进行编译，但是再编译完成后进行调试的时候，发现一个奇怪的现象：当内核进行GDT初始化最后加载GDT的时候，qemu总会关机重启。

关机重启前的最后一条指令：

![](https://okl2aaa54.qnssl.com/ucore-1-3.png)

执行这条指令之后：

![](https://okl2aaa54.qnssl.com/ucore-1-4.png)

最终我的解决方法是在Makefile中使用clang编译器来代替GCC：

```makefile
#need llvm/cang-3.5+
USELLVM := 1
```

问题成功解决，但是不清楚这背后的原因。

