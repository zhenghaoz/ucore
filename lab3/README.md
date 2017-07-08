## 练习1：给未被映射的地址映射上物理页（需要编程）

- 首先检查页表中是否有相应的表项，如果表项为空，那么说明没有映射过；
- 然后使用`pgdir_alloc_page`获取一个物理页，同时进行错误检查即可。

```c
...
if ((ptep = get_pte(mm->pgdir, addr, 1)) == NULL)
    goto failed;
if (*ptep == 0) {
    struct Page *page = pgdir_alloc_page(mm->pgdir, addr, perm);
    if (page == NULL)
        goto failed;
} else {
...
```

1. 请描述页目录项（Pag Director Entry）和页表（Page Table Entry）中组成部分对ucore实现页替换算法的潜在用处。

表项中`PTE_A`表示内存页是否被访问过，`PTE_D`表示内存页是否被修改过，借助着两位标志位可以实现Enhanced Clock算法。

2. 如果ucore的缺页服务例程在执行过程中访问内存，出现了页访问异常，请问硬件要做哪些事情？

如果出现了页访问异常，那么硬件将引发页访问异常的地址将被保存在cr2寄存器中，设置错误代码，然后触发Page Fault异常。

## 练习2：补充完成基于FIFO的页面替换算法（需要编程）

由于FIFO基于双向链表实现，所以只需要将元素插入到头节点之前。

```c
static int _fifo_map_swappable(struct mm_struct *mm, uintptr_t addr, struct Page *page, int swap_in) {
    list_entry_t *head=(list_entry_t*) mm->sm_priv;
    list_entry_t *entry=&(page->pra_page_link);
 
    assert(entry != NULL && head != NULL);
    list_add_before(head, entry);
    return 0;
}
```

将双向链表中头部节点后面的第一个节点删除，返回对应的页地址（虚拟地址）。

```c
static int _fifo_swap_out_victim(struct mm_struct *mm, struct Page ** ptr_page, int in_tick) {
     list_entry_t *head=(list_entry_t*) mm->sm_priv;
         assert(head != NULL);
     assert(in_tick==0);
     list_entry_t *first = list_next(head);
     list_del(first);
     *ptr_page = le2page(first, pra_page_link);
     return 0;
}
```

如果PTE存在，那么说明这一页已经映射过了但是被保存在磁盘中，需要将这一页内存交换出来：

- 调用`swap_in`将内存页从磁盘中载入内存；
- 调用`page_insert`建立物理地址与线性地址之间的映射；
- 设置页对应的虚拟地址，方便交换出内存时将正确的内存数据保存在正确的磁盘位置；
- 调用`swap_map_swappable`将物理页框加入FIFO。

```c
...
} else {
    if(swap_init_ok) {
        struct Page *page = NULL;
        swap_in(mm, addr, &page);
        page_insert(mm->pgdir, page, addr, perm);
        page->pra_vaddr = addr;
        swap_map_swappable(mm, addr, page, 0);
    }
...
}
...
```

如果要在ucore上实现"extended clock页替换算法"请给你的设计方案，现有的swap_manager框架是否足以支持在ucore中实现此算法？如果是，请给你的设计方案。如果不是，请给出你的新的扩展和基此扩展的设计方案。并需要回答如下问题：

1. 需要被换出的页的特征是什么？


对于每个页面都有两个标志位，分别为使用位和修改位，记为`<使用,修改>`。换出页的使用位必须为0，并且算法优先考虑换出修改位为零的页面。


2. 在ucore中如何判断具有这样特征的页？


当内存页被访问后，MMU将在对应的页表项的`PTE_A`这一位设为1；

当内存页被修改后，MMU将在对应的页表项的`PTE_D`这一位设为1。


3. 何时进行换入和换出操作？

当保存在磁盘中的内存需要被访问时，需要进行**换入**操作；

当位于物理页框中的内存被页面替换算法选择时，需要进行**换出**操作。

## 扩展练习 Challenge：实现识别dirty bit的 extended clock页替换算法（需要编程）

#### 数据结构

Enhanced Clock算法需要一个环形链表和一个指针，这个可以在原有的双向链表基础上实现。为了方便进行循环访问，将原先的头部哨兵删除，这样所有的页面形成一个环形链表。指向环形链表指针也就是Enhanced Clock算法中指向下个页面的指针。

#### 插入

如果环形链表为空，那么这个页面就是整个链表，将指针指向这个页面。否则，只需要将页面插入指针指向的页面之前即可。

#### 换出

Enhanced Clock算法最多需要遍历环形链表四次（规定标记为`<访问,修改>`）：

- 首先，查找标记为`<0,0>`的页面；
- 如果上一步没有找到，查找标记`<0,1>`，并将访问过的页面的访问位清零；
- 如果上一步没有找到，再次查找标记为`<0,0>`的页面；
- 如果上一步没有找到，再次查找标记为`<0,1>`的页面；

> 将PTE中的PTE_A清除后，需要调用`tlb_invalidate`刷新TLB，否则当页面被再次访问的时候，PTE中的PTE_A不会被设置。

## 参考资料

- [page-rep3.dvi](http://courses.cs.tamu.edu/bart/cpsc410/Supplements/Slides/page-rep3.pdf)
- [Paging - OSDev Wiki](http://wiki.osdev.org/Paging)

## 附录：Enhanced Clock源代码

swap_clock.h

```c
#ifndef __KERN_MM_SWAP_CLOCK_H__
#define __KERN_MM_SWAP_CLOCK_H__

#include <swap.h>
extern struct swap_manager swap_manager_clock;

#endif
```

swap_clock.c

```c
#include <x86.h>
#include <stdio.h>
#include <string.h>
#include <swap.h>
#include <swap_clock.h>
#include <list.h>

#define GET_LIST_ENTRY_PTE(pgdir, le)  (get_pte((pgdir), le2page((le), pra_page_link)->pra_vaddr, 0))
#define GET_DIRTY_FLAG(pgdir, le)      (*GET_LIST_ENTRY_PTE((pgdir), (le)) & PTE_D)
#define GET_ACCESSED_FLAG(pgdir, le)   (*GET_LIST_ENTRY_PTE((pgdir), (le)) & PTE_A)
#define CLEAR_ACCESSED_FLAG(pgdir, le) do {\
    struct Page *page = le2page((le), pra_page_link);\
    pte_t *ptep = get_pte((pgdir), page->pra_vaddr, 0);\
    *ptep = *ptep & ~PTE_A;\
    tlb_invalidate((pgdir), page->pra_vaddr);\
} while (0)

static int
_clock_init_mm(struct mm_struct *mm)
{     
     mm->sm_priv = NULL;
     return 0;
}

static int
_clock_map_swappable(struct mm_struct *mm, uintptr_t addr, struct Page *page, int swap_in)
{
    list_entry_t *head=(list_entry_t*) mm->sm_priv;
    list_entry_t *entry=&(page->pra_page_link);
    assert(entry != NULL);

    // Insert before pointer
    if (head == NULL) {
        list_init(entry);
        mm->sm_priv = entry;
    } else {
        list_add_before(head, entry);
    }
    return 0;
}

static int
_clock_swap_out_victim(struct mm_struct *mm, struct Page ** ptr_page, int in_tick)
{
     list_entry_t *head=(list_entry_t*) mm->sm_priv;
     assert(head != NULL);
     assert(in_tick==0);

     list_entry_t *selected = NULL, *p = head;
     // Search <0,0>
     do {
        if (GET_ACCESSED_FLAG(mm->pgdir, p) == 0 && GET_DIRTY_FLAG(mm->pgdir, p) == 0) {
            selected = p;
            break;
        }
        p = list_next(p);
     } while (p != head);
     // Search <0,1> and set 'accessed' to 0
     if (selected == NULL)
        do {
            if (GET_ACCESSED_FLAG(mm->pgdir, p) == 0 && GET_DIRTY_FLAG(mm->pgdir, p)) {
                selected = p;
                break;
            }
            CLEAR_ACCESSED_FLAG(mm->pgdir, p);
            p = list_next(p);
        } while (p != head);
     // Search <0,0> again
     if (selected == NULL)
        do {
            if (GET_ACCESSED_FLAG(mm->pgdir, p) == 0 && GET_DIRTY_FLAG(mm->pgdir, p) == 0) {
                selected = p;
                break;
            }
            p = list_next(p);
        } while (p != head);
     // Search <0,1> again
     if (selected == NULL)
        do {
            if (GET_ACCESSED_FLAG(mm->pgdir, p) == 0 && GET_DIRTY_FLAG(mm->pgdir, p)) {
                selected = p;
                break;
            }
            p = list_next(p);
        } while (p != head);
     // Remove pointed element
     head = selected;
     if (list_empty(head)) {
        mm->sm_priv = NULL;
     } else {
         mm->sm_priv = list_next(head);
        list_del(head);
     }
     *ptr_page = le2page(head, pra_page_link);
     return 0;
}

static int
_clock_check_swap(void) {
    cprintf("write Virt Page c in fifo_check_swap\n");
    *(unsigned char *)0x3000 = 0x0c;
    assert(pgfault_num==4);
    cprintf("write Virt Page a in fifo_check_swap\n");
    *(unsigned char *)0x1000 = 0x0a;
    assert(pgfault_num==4);
    cprintf("write Virt Page d in fifo_check_swap\n");
    *(unsigned char *)0x4000 = 0x0d;
    assert(pgfault_num==4);
    cprintf("write Virt Page b in fifo_check_swap\n");
    *(unsigned char *)0x2000 = 0x0b;
    assert(pgfault_num==4);
    cprintf("write Virt Page e in fifo_check_swap\n");
    *(unsigned char *)0x5000 = 0x0e;
    assert(pgfault_num==5);
    cprintf("write Virt Page b in fifo_check_swap\n");
    *(unsigned char *)0x2000 = 0x0b;
    assert(pgfault_num==5);
    cprintf("write Virt Page a in fifo_check_swap\n");
    *(unsigned char *)0x1000 = 0x0a;
    assert(pgfault_num==6);
    cprintf("write Virt Page b in fifo_check_swap\n");
    *(unsigned char *)0x2000 = 0x0b;
    assert(pgfault_num==6);
    cprintf("write Virt Page c in fifo_check_swap\n");
    *(unsigned char *)0x3000 = 0x0c;
    assert(pgfault_num==7);
    cprintf("write Virt Page d in fifo_check_swap\n");
    *(unsigned char *)0x4000 = 0x0d;
    assert(pgfault_num==8);
    cprintf("write Virt Page e in fifo_check_swap\n");
    *(unsigned char *)0x5000 = 0x0e;
    assert(pgfault_num==9);
    cprintf("write Virt Page a in fifo_check_swap\n");
    assert(*(unsigned char *)0x1000 == 0x0a);
    *(unsigned char *)0x1000 = 0x0a;
    assert(pgfault_num==9);
    cprintf("read Virt Page b in fifo_check_swap\n");
    assert(*(unsigned char *)0x2000 == 0x0b);
    assert(pgfault_num==10);
    cprintf("read Virt Page c in fifo_check_swap\n");
    assert(*(unsigned char *)0x3000 == 0x0c);
    assert(pgfault_num==11);
    cprintf("read Virt Page a in fifo_check_swap\n");
    assert(*(unsigned char *)0x1000 == 0x0a);
    assert(pgfault_num==12);
    cprintf("read Virt Page d in fifo_check_swap\n");
    assert(*(unsigned char *)0x4000 == 0x0d);
    assert(pgfault_num==13);
    cprintf("read Virt Page b in fifo_check_swap\n");
    *(unsigned char *)0x1000 = 0x0a;
    assert(*(unsigned char *)0x3000 == 0x0c);
    assert(*(unsigned char *)0x4000 == 0x0d);
    assert(*(unsigned char *)0x5000 == 0x0e);
    assert(*(unsigned char *)0x2000 == 0x0b);
    assert(pgfault_num==14);
    return 0;
}

static int
_clock_init(void)
{
    return 0;
}

static int
_clock_set_unswappable(struct mm_struct *mm, uintptr_t addr)
{
    return 0;
}

_clock_tick_event(struct mm_struct *mm)
{ return 0; }

struct swap_manager swap_manager_clock =
{
     .name            = "clock swap manager",
     .init            = &_clock_init,
     .init_mm         = &_clock_init_mm,
     .tick_event      = &_clock_tick_event,
     .map_swappable   = &_clock_map_swappable,
     .set_unswappable = &_clock_set_unswappable,
     .swap_out_victim = &_clock_swap_out_victim,
     .check_swap      = &_clock_check_swap,
};
```
