## 练习1：实现 first-fit 连续物理内存分配算法

- default_init

创建一个空的双向链表即可。

```c
static void default_init(void) {
    list_init(&free_list);
    nr_free = 0;
}
```

- default_init_memmap


初始化每个物理页面记录，然后将全部的可分配物理页视为一大块空闲块加入空闲表。


```c
static void default_init_memmap(struct Page *base, size_t n) {
    assert(n > 0);
    struct Page *p = base;
    for (; p != base + n; p ++) {
        assert(PageReserved(p));
        p->flags = p->property = 0;
        set_page_ref(p, 0);
    }
    base->property = n;
    SetPageProperty(base);
    nr_free += n;
    list_add(&free_list, &(base->page_link));
}
```

- default_alloc_pages

首次适配算法要求按照地址从小到大查找空间，所以要求空闲表中的空闲空间按照地址从小到大排序。这样，首次适配算法查询空闲空间的方法就是从链表头部开始找到第一个符合要求的空间，将这个空间从空闲表中删除。空闲空间在分配完要求数量的物理页之后可能会有剩余，那么需要将剩余的部分作为新的空闲空间插入到原空间位置（这样才能保证空闲表中空闲空间地址递增）。

```c
static struct Page *default_alloc_pages(size_t n) {
    assert(n > 0);
    if (n > nr_free) {
        return NULL;
    }
    struct Page *page = NULL;
    list_entry_t *le = &free_list;
    while ((le = list_next(le)) != &free_list) {
        struct Page *p = le2page(le, page_link);
        if (p->property >= n) {
            page = p;
            break;
        }
    }
    if (page != NULL) {
        list_del(&(page->page_link));
        if (page->property > n) {
            struct Page *p = page + n;
            p->property = page->property - n;
            SetPageProperty(p);
            list_add(list_prev(le), &(p->page_link));
        }
        nr_free -= n;
        ClearPageProperty(page);
    }
    return page;
}
```

- default_free_pages

将需要释放的空间标记为空之后，需要找到空闲表中合适的位置。由于空闲表中的记录都是按照物理页地址排序的，所以如果插入位置的前驱或者后继刚好和释放后的空间邻接，那么需要将新的空间与前后邻接的空间合并形成更大的空间。

```c
static void default_free_pages(struct Page *base, size_t n) {
    assert(n > 0);
    struct Page *p = base;
    for (; p != base + n; p ++) {
        assert(!PageReserved(p) && !PageProperty(p));
        p->flags = 0;
        set_page_ref(p, 0);
    }
    base->property = n;
    SetPageProperty(base);
    // Find insert location
    list_entry_t *next_entry = list_next(&free_list);
    while (next_entry != &free_list && le2page(next_entry, page_link) < base)
        next_entry = list_next(next_entry);
    // Merge block
    list_entry_t *prev_entry = list_prev(next_entry);
    list_entry_t *insert_entry = prev_entry;
    if (prev_entry != &free_list) {
        p = le2page(prev_entry, page_link);
        if (p + p->property == base) {
            p->property += base->property;
            ClearPageProperty(base);
            base = p;
            insert_entry = list_prev(prev_entry);
            list_del(prev_entry);
        }
    }
    if (next_entry != &free_list) {
        p = le2page(next_entry, page_link);
        if (base + base->property == p) {
            base->property += p->property;
            ClearPageProperty(p);
            list_del(next_entry);
        }
    }
    // Insert into free list
    nr_free += n;
    list_add(insert_entry, &(base->page_link));
}
```

1. 你的first fit算法是否有进一步的改进空间？

在上面的first fit算法中，有两个地方需要$$O(n)$$时间复杂度：链表查找和有序链表插入。对于其中的有序链表插入，在特殊情况下是可以优化的。当一个刚被释放的内存块来说，如果它的邻接空间都是空闲的，那么就不需要进行线性时间复杂度的链表插入操作，而是直接并入邻接空间，时间复杂度为常数。为了判断邻接空间是否为空闲状态，空闲块的信息除了保存在第一个页面之外，还需要在最后一页保存信息，这样新的空闲块只需要检查邻接的两个页面就能判断邻接空间块的状态。

## 练习2：实现寻找虚拟地址对应的页表项

获取页表项的过程如下：

- 如果查询线性地址所在的页目录项不存在：
  - 申请一个内存物理页；
  - 设置内存页引用数目为1；
  - 获取页面对应的物理地址；
  - 将内存页内容初始化为零（memset使用内核虚拟地址）；
  - 将内存页地址加入页目录项；
- 从页目录项中获取页表项的地址返回。

```c
pte_t *get_pte(pde_t *pgdir, uintptr_t la, bool create) {
    if (!(pgdir[PDX(la)] & PTE_P)) {
        struct Page *page;
        if (!create || (page = alloc_page()) == NULL)
            return NULL;
        set_page_ref(page, 1);
        uintptr_t pa = page2pa(page);
        memset(KADDR(pa), 0, PGSIZE);
        pgdir[PDX(la)] = (pa & ~0xFFF) | PTE_P | PTE_W | PTE_U;
    }
    return (pte_t *)KADDR(PDE_ADDR(pgdir[PDX(la)])) + PTX(la);
}
```

1. 请描述页目录项（Pag Director Entry）和页表（Page Table Entry）中每个组成部分的含义和以及对ucore而言的潜在用处。

因为页的映射是以物理页面为单位进行，所以页面对应的物理地址总是按照4096字节对齐的，物理地址低0-11位总是零，所以在页目录项和页表项中，低0-11位可以用于作为标志字段使用。

| 位     | 意义                |
| ----- | ----------------- |
| 0     | 表项有效标志（PTE_U）     |
| 1     | 可写标志（PTE_W）       |
| 2     | 用户访问权限标志（PTE_P）   |
| 3     | 写入标志（PTE_PWT）     |
| 4     | 禁用缓存标志（PTE_PCD）   |
| 5     | 访问标志（PTE_A）       |
| 6     | 脏页标志（PTE_D）       |
| 7     | 页大小标志（PTE_PS）     |
| 8     | 零位标志（PTE_MBZ）     |
| 11    | 软件可用标志（PTE_AVAIL） |
| 12-31 | 页表起始物理地址/页起始物理地址  |

2. 如果ucore执行过程中访问内存，出现了页访问异常，请问硬件要做哪些事情？


如果出现了页访问异常，那么硬件将引发页访问异常的地址将被保存在cr2寄存器中，设置错误代码，然后触发Page Fault异常。


## 练习3：释放某虚地址所在的页并取消对应二级页表项的映射

取消页表映射过程如下：

- 将物理页的引用数目减一，如果变为零，那么释放页面；
- 将页目录项清零；
- 刷新TLB。

```c
static inline void page_remove_pte(pde_t *pgdir, uintptr_t la, pte_t *ptep) {
    if (*ptep & PTE_P) {
        struct Page *page = pte2page(*ptep);
        if (page_ref_dec(page) == 0)
            free_page(page);
        *ptep = 0;
        tlb_invalidate(pgdir, la);
    }
}
```

1. 数据结构Page的全局变量（其实是一个数组）的每一项与页表中的页目录项和页表项有无对应关系？如果有，其对应关系是啥？


页目录项或者页表项中都保存着一个物理页面的地址，对于页目录项，这个物理页面用于保存耳机页表，对于页表来说，这个物理页面用于内核或者用户程序。同时，每一个物理页面在Page数组中都有对应的记录。


2. 如果希望虚拟地址与物理地址相等，则需要如何修改lab2，完成此事？ **鼓励通过编程来具体完成这个问题**


- 修改链接脚本，将内核起始虚拟地址修改为`0x100000`；


tools/kernel.ld

```
SECTIONS {
    /* Load the kernel at this address: "." means the current address */
    . = 0x100000;
...
```

- 修改虚拟内存空间起始地址为0；


kern/mm/memlayout.h

```c
/* All physical memory mapped at this address */
#define KERNBASE            0x00000000
```

- 注释掉取消0~4M区域内存页映射的代码

kern/mm/pmm.c

```c
//disable the map of virtual_addr 0~4M
// boot_pgdir[0] = 0;

//now the basic virtual memory map(see memalyout.h) is established.
//check the correctness of the basic virtual memory map.
// check_boot_pgdir();
```

## **扩展练习Challenge：Buddy System（伙伴系统）分配算法**

#### 初始化

在Buddy System中，空间块之间的关系形成一颗完全二叉树，对于一颗有着n叶子的完全二叉树来说，所有节点的总数为$$2n-1\approx2n$$。也就是说，如果Buddy System的可分配空间为n页的话，那么就需要额外保存2n-1个节点信息。

###### 初始化空闲链表

Buddy System并不需要链表，但是为了在调式的时候方便访问所有空闲空间，还是将所有的空闲空间加入链表中。

###### 确定分配空间大小

假设我们得到了大小为n的空间，我们需要在此基础上建立Buddy System，经过初始化后，Buddy System管理的页数为$$2^m$$，那么大小为n的实际空间可能分为两个或者三个部分。

**节点信息区**：节点信息区可以用来保存每个节点对应子树中可用空间的信息，用于在分配内存的时候便于检查子树中是否有足够的空间来满足请求大小。在32位操作系统中，最大页数不会超过4GB/4KB=1M，所有使用一个32位整数即可表示每个节点的信息。所以节点信息区的大小为$$2^m\times2\times4=2^{m+3}$$字节，每页大小为4KB，内存占用按照页面大小对齐，所以占用$$max\{1,2^{m-9}\}$$页。

**虚拟分配区**：占用$$2^m$$页。

**实际分配区**：显然实际可以得到的内存大小不大可能刚好等于节点信息区大小+分配空间区大小。如果节点信息区大小+分配空间区大小<=内存大小，那么实际可以分配的区域就等于$$2^m$$页。如果节点信息区大小+分配空间区大小>内存大小，那么实际可以分配的区域就等于$$n-max\{1,2^{m-9}\}$$页。

作为操作系统，自然希望实际使用的区域越大越好，不妨分类讨论。

**当内存小于等于512页**：此时无论如何节点信息都会占用一页，所以提高内存利率的方法就是将实际内存大小减一后向上取整（文中整数意为2的幂）。

**当内存大于512页**：不难证明，对于内存大小$$n$$来说，最佳虚拟分配区大小往往是n向下取整或者向上取整的数值，所以候选项也就是只有两个，所以可以先考虑向下取整。对于$$[2^m,2^{m+1}-1]$$中的数$$n$$，向下取整可以得到$$2^m$$:

- 当$$n\le2^{m-9}+2^m$$时，显然已经是最佳值；
- 当$$2^{m-9}+2^m<n\le2^{m-8}+2^m$$时，扩大虚拟分配区导致节点信息区增加却没有使得实际分配区增加，所以当期m还是最佳值；
- 当$$n>2^{m-8}+2^m$$时，$$m+1$$可以扩大实际分配区。

###### 初始化节点信息

虚拟分配区可能会大于实际分配区，所以一开始需要将虚拟分配区中没有实际分配区对应的空间标记为已经分配进行屏蔽。另当前区块的虚拟空间大小为$$v$$，实际空间大小为$$r$$，屏蔽的过程如下：

- 如果$$v=r$$，将空间初始化为一个空闲空间，屏蔽过程结束；
- 如果$$r=0$$，将空间初始化为一个已分配空间，屏蔽过程结束；
- 如果$$r{\le}v/2$$，将右半空间初始化为已分配空间，更新$$r=r/2$$后继续对左半空间进行操作；
- 如果$$r>v/2$$，将左半空间初始化为空闲空间，更新$$r=r-v/2,v=v/2$$后继续对左半空间进行操作。

以虚拟分配区16页、实际分配区14页为例，初始化后如下：

<center><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="211px" height="181px" version="1.1"><defs/><g transform="translate(0.5,0.5)"><g transform="translate(41.5,2.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="31" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">[0,16)</div></div></foreignObject><text x="16" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[0,16)</text></switch></g><g transform="translate(1.5,42.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="24" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">[0,8)</div></div></foreignObject><text x="12" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[0,8)</text></switch></g><g transform="translate(81.5,42.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="31" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">[8,16)</div></div></foreignObject><text x="16" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[8,16)</text></switch></g><g transform="translate(41.5,82.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="31" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">[8,12)</div></div></foreignObject><text x="16" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[8,12)</text></switch></g><g transform="translate(121.5,82.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="38" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">[12,16)</div></div></foreignObject><text x="19" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[12,16)</text></switch></g><g transform="translate(81.5,122.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="38" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">[12,14)</div></div></foreignObject><text x="19" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[12,14)</text></switch></g><g transform="translate(161.5,122.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="38" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">[14,16)</div></div></foreignObject><text x="19" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[14,16)</text></switch></g><path d="M 50 20 L 25.38 36.5" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 21.02 39.43 L 24.89 32.62 L 25.38 36.5 L 28.79 38.43 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 59.62 20.52 L 84.26 36.53" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 88.67 39.39 L 80.89 38.51 L 84.26 36.53 L 84.7 32.64 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 89.14 60 L 65.01 75.22" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 60.56 78.02 L 64.62 71.33 L 65.01 75.22 L 68.35 77.25 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 132 101 L 103.25 117.37" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 98.69 119.97 L 103.04 113.47 L 103.25 117.37 L 106.5 119.55 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 100.57 60.52 L 139.96 77.52" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 144.78 79.6 L 136.97 80.04 L 139.96 77.52 L 139.74 73.62 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 145.33 100.52 L 179.09 116.39" fill="none" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 183.85 118.62 L 176.02 118.81 L 179.09 116.39 L 179 112.48 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><rect x="0" y="160" width="40" height="20" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(16.5,163.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 8px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">8</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">8</text></switch></g><rect x="40" y="160" width="40" height="20" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(56.5,163.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 8px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">4</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">4</text></switch></g><rect x="80" y="160" width="60" height="20" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(106.5,163.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 8px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">2</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">2</text></switch></g><rect x="140" y="160" width="60" height="20" fill="#000000" stroke="#808080" pointer-events="none"/><g transform="translate(166.5,163.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 8px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><font color="#ffffff">2</font></div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><path d="M 20 60 L 20 153.63" fill="none" stroke="#000000" stroke-miterlimit="10" stroke-dasharray="3 3" pointer-events="none"/><path d="M 20 158.88 L 16.5 151.88 L 20 153.63 L 23.5 151.88 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 60 90 L 60 153.63" fill="none" stroke="#000000" stroke-miterlimit="10" stroke-dasharray="3 3" pointer-events="none"/><path d="M 60 158.88 L 56.5 151.88 L 60 153.63 L 63.5 151.88 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 100 140 L 100 153.63" fill="none" stroke="#000000" stroke-miterlimit="10" stroke-dasharray="3 3" pointer-events="none"/><path d="M 100 158.88 L 96.5 151.88 L 100 153.63 L 103.5 151.88 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 180 140 L 180 153.63" fill="none" stroke="#000000" stroke-miterlimit="10" stroke-dasharray="3 3" pointer-events="none"/><path d="M 180 158.88 L 176.5 151.88 L 180 153.63 L 183.5 151.88 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/></g></svg></center>

#### 分配过程

Buddy System要求分配空间为2的幂，所以首先将请求的页数向上对齐到2的幂。

接下来从二叉树的根节点（1号节点）开始查找满足要求的节点。对于每次检查的节点：

- 如果子树的最大可用空间小于请求空间，那么分配失败；
- 如果子树的最大可用空间大于等于请求空间，并且总空间大小等于请求空间，说明这个节点对应的空间没有被分割和分配，并且满足请求空间大小，那么分配这个空间；
- 如果子树的最大可用空间大于等于请求空间，并且总空间大小大于请求空间，那么在这个节点的子树中查找：
  - 如果这个节点对应的空间没有被分割过（最大可用空间等于总空间大小），那么分割空间，在左子树（左半部分）继续查找；
  - **如果左子树包含大小等于请求空间的可用空间，那么在左子树中继续查找；**
  - **如果右子树包含大小等于请求空间的可用空间，那么在右子树中继续查找；**


- 如果左子树的最大可用空间大于等于请求空间，那么在左子树中继续查找；
  - 如果右子树的最大可用空间大于等于请求空间，那么在右子树中继续查找。

算法中**加粗的部分**主要为了减少碎片而增加的额外优化。

当一个空间被分配之后，这个空间对应节点的所有父节点的可用空间表都会受到影响，需要自地向上重新更新可用空间信息。

#### 释放过程

Buddy System要求分配空间为2的幂，所以同样首先将请求的页数向上对齐到2的幂。

在进行释放之前，需要确定要释放的空间对应的节点，然后将空间标记为可用。接下来进行自底向上的操作：

- 如果某节点的两个子节点对应的空间都未分割和分配，那么合并这两个空间，形成一个更大的空间；
- 否则，根据子节点的可用空间信息更新父节点的可用空间信息。

## **扩展练习Challenge：任意大小的内存单元slub分配算法**

实际上Slub分配算法是非常复杂的，需要考虑缓存对齐、NUMA等非常多的问题，作为实验性质的操作系统就不考虑这些复杂因素了。简化的Slub算法结合了Slab算法和Slub算法的部分特征，使用了一些比较右技巧性的实现方法。具体的简化为：

- Slab大小为一页，不允许创建大对象仓库
- 复用Page数据结构，将Slab元数据保存在Page结构体中

#### 数据结构

在操作系统中经常会用到大量相同的数据对象，例如互斥锁、条件变量等等，同种数据对象的初始化方法、销毁方法、占用内存大小都是一样的，如果操作系统能够将所有的数据对象进行统一管理，可以提高内存利用率，同时也避免了反复初始化对象的开销。

###### 仓库

每种对象由仓库（感觉cache在这里翻译为仓库更好）进行统一管理：

```c
struct kmem_cache_t {
    list_entry_t slabs_full;	// 全满Slab链表
    list_entry_t slabs_partial;	// 部分空闲Slab链表
    list_entry_t slabs_free;	// 全空闲Slab链表
    uint16_t objsize;		// 对象大小
    uint16_t num;			// 每个Slab保存的对象数目
    void (*ctor)(void*, struct kmem_cache_t *, size_t);	// 构造函数
    void (*dtor)(void*, struct kmem_cache_t *, size_t);	// 析构函数
    char name[CACHE_NAMELEN];	// 仓库名称
    list_entry_t cache_link;	// 仓库链表
};
```

由于限制Slab大小为一页，所以数据对象和每页对象数据不会超过$$4096=2^{12}$$，所以使用16位整数保存足够。然后所有的仓库链接成一个链表，方便进行遍历。

###### Slab

在上面的Buddy System中，一个物理页被分配之后，Page结构中除了ref之外的成员都没有其他用处了，可以把Slab的元数据保存在这些内存中：

```c
struct slab_t {
    int ref;				// 页的引用次数（保留）
    struct kmem_cache_t *cachep;	// 仓库对象指针
    uint16_t inuse;			// 已经分配对象数目
    int16_t free;			// 下一个空闲对象偏移量
    list_entry_t slab_link;		// Slab链表
};
```

为了方便空闲区域的管理，Slab对应的内存页分为两部分：保存空闲信息的bufcnt以及可用内存区域buf。

<center><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="339px" height="232px" version="1.1"><defs/><g transform="translate(0.5,0.5)"><rect x="8" y="80" width="80" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(32.5,93.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="29" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 30px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><div>bufctl</div></div></div></foreignObject><text x="15" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><rect x="88" y="80" width="240" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(199.5,93.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="16" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 18px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><div>buf</div></div></div></foreignObject><text x="8" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><path d="M 7.38 122.72 L 7.89 153.63" fill="none" stroke="#000000" stroke-miterlimit="10" stroke-dasharray="3 3" pointer-events="none"/><path d="M 7.98 158.88 L 4.37 151.94 L 7.89 153.63 L 11.36 151.82 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 89 124 L 321.07 157" fill="none" stroke="#000000" stroke-miterlimit="10" stroke-dasharray="3 3" pointer-events="none"/><path d="M 326.27 157.74 L 318.85 160.22 L 321.07 157 L 319.83 153.29 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><rect x="8" y="160" width="40" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(24.5,173.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 8px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">1</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">1</text></switch></g><rect x="48" y="160" width="40" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(64.5,173.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 8px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">2</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">2</text></switch></g><rect x="88" y="160" width="40" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(104.5,173.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 8px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">3</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">3</text></switch></g><rect x="288" y="160" width="40" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(301.5,173.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="11" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 12px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">-1</div></div></foreignObject><text x="6" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">-1</text></switch></g><rect x="8" y="0" width="60" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(15.5,13.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="43" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 44px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">object 0</div></div></foreignObject><text x="22" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">object 0</text></switch></g><rect x="68" y="0" width="60" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(75.5,13.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="43" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 44px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><span>object 1</span></div></div></foreignObject><text x="22" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><rect x="128" y="160" width="160" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(202.5,173.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="10" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 11px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">...</div></div></foreignObject><text x="5" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">...</text></switch></g><rect x="128" y="0" width="60" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(135.5,13.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="43" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 44px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><span>object 2</span></div></div></foreignObject><text x="22" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><rect x="268" y="0" width="60" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(270.5,13.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="54" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 55px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;"><span>object n-1</span></div></div></foreignObject><text x="27" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">[Not supported by viewer]</text></switch></g><rect x="188" y="0" width="80" height="40" fill="#ffffff" stroke="#000000" pointer-events="none"/><g transform="translate(222.5,13.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="10" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; width: 11px; white-space: nowrap; word-wrap: normal; text-align: center;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">...</div></div></foreignObject><text x="5" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">...</text></switch></g><path d="M 330 80 L 330 49.37" fill="none" stroke="#000000" stroke-miterlimit="10" stroke-dasharray="3 3" pointer-events="none"/><path d="M 330 44.12 L 333.5 51.12 L 330 49.37 L 326.5 51.12 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><path d="M 89.45 77.21 L 18.04 45.97" fill="none" stroke="#000000" stroke-miterlimit="10" stroke-dasharray="3 3" pointer-events="none"/><path d="M 13.23 43.86 L 21.05 43.46 L 18.04 45.97 L 18.24 49.87 Z" fill="#000000" stroke="#000000" stroke-miterlimit="10" pointer-events="none"/><g transform="translate(19.5,212.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">0</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">0</text></switch></g><g transform="translate(60.5,212.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">1</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">1</text></switch></g><g transform="translate(99.5,212.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="6" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">2</div></div></foreignObject><text x="3" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">2</text></switch></g><g transform="translate(299.5,212.5)"><switch><foreignObject style="overflow:visible;" pointer-events="all" width="18" height="12" requiredFeatures="http://www.w3.org/TR/SVG11/feature#Extensibility"><div xmlns="http://www.w3.org/1999/xhtml" style="display: inline-block; font-size: 12px; font-family: Helvetica; color: rgb(0, 0, 0); line-height: 1.2; vertical-align: top; white-space: nowrap;"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;text-align:inherit;text-decoration:inherit;">n-1</div></div></foreignObject><text x="9" y="12" fill="#000000" text-anchor="middle" font-size="12px" font-family="Helvetica">n-1</text></switch></g></g></svg></center>

对象数据不会超过2048，所以bufctl中每个条目为16位整数。bufctl中每个“格子”都对应着一个对象内存区域，不难发现，bufctl保存的是一个隐式链表，格子中保存的内容就是下一个空闲区域的偏移，-1表示不存在更多空闲区，slab_t中的free就是链表头部。

###### 内置仓库

除了可以自行管理仓库之外，操作系统往往也提供了一些常见大小的仓库，本文实现中内置了8个仓库，仓库对象大小为：8B、16B、32B、64B、128B、256B、512B、1024B。

#### 操作函数

###### 私有函数

- `void *kmem_cache_grow(struct kmem_cache_t *cachep);`

申请一页内存，初始化空闲链表bufctl，构造buf中的对象，更新Slab元数据，最后将新的Slab加入到仓库的空闲Slab表中。

- `void kmem_slab_destroy(struct kmem_cache_t *cachep, struct slab_t *slab);`

析构buf中的对象后将内存页归还。

###### 公共函数

- `void kmem_int();`

**初始化kmem_cache_t仓库**：由于kmem_cache_t也是由Slab算法分配的，所以需要预先手动初始化一个kmem_cache_t仓库；

**初始化内置仓库**：初始化8个固定大小的内置仓库。

- `kmem_cache_create(const char *name, size_t size, void (*ctor)(void*, struct kmem_cache_t *, size_t),void (*dtor)(void*, struct kmem_cache_t *, size_t));`

从kmem_cache_t仓库中获得一个对象，初始化成员，最后将对象加入仓库链表。其中需要注意的就是计算Slab中对象的数目，由于空闲表每一项占用2字节，所以每个Slab的对象数目就是：4096字节/(2字节+对象大小)。

- `void kmem_cache_destroy(struct kmem_cache_t *cachep);`

释放仓库中所有的Slab，释放kmem_cache_t。

- `void *kmem_cache_alloc(struct kmem_cache_t *cachep);`

先查找slabs_partial，如果没找到空闲区域则查找slabs_free，还是没找到就申请一个新的slab。从slab分配一个对象后，如果slab变满，那么将slab加入slabs_full。

- `void *kmem_cache_zalloc(struct kmem_cache_t *cachep);`

使用kmem_cache_alloc分配一个对象之后将对象内存区域初始化为零。

- `void kmem_cache_free(struct kmem_cache_t *cachep, void *objp);`

将对象从Slab中释放，也就是将对象空间加入空闲链表，更新Slab元信息。如果Slab变空，那么将Slab加入slabs_partial链表。

- `size_t kmem_cache_size(struct kmem_cache_t *cachep);`

获得仓库中对象的大小。

- `const char *kmem_cache_name(struct kmem_cache_t *cachep);`

获得仓库的名称。

- `int kmem_cache_shrink(struct kmem_cache_t *cachep);`

将仓库中slabs_free中所有Slab释放。

- `int kmem_cache_reap();`

遍历仓库链表，对每一个仓库进行kmem_cache_shrink操作。

- `void *kmalloc(size_t size);`

找到大小最合适的内置仓库，申请一个对象。

- `void kfree(const void *objp);`

释放内置仓库对象。

- `size_t ksize(const void *objp);`

获得仓库对象大小。

## 参考资料

- [伙伴分配器的一个极简实现 \| \| 酷 壳 - CoolShell](http://coolshell.cn/articles/10427.html)
- [Slab Allocator](https://www.kernel.org/doc/gorman/html/understand/understand011.html)
- [The Slab Allocator: An Object-Caching Kernel Memory Allocator](https://www.usenix.org/legacy/publications/library/proceedings/bos94/full_papers/bonwick.a)

## 附录：Buddy System分配算法源代码

buddy.h

```c
#ifndef __KERN_MM_BUDDY_H__
#define  __KERN_MM_BUDDY_H__

#include <pmm.h>

extern const struct pmm_manager buddy_pmm_manager;

#endif /* ! __KERN_MM_BUDDY_H__ */
```

buddy.c

```c
#include <pmm.h>
#include <list.h>
#include <string.h>
#include <buddy.h>

free_area_t free_area;

#define free_list (free_area.free_list)
#define nr_free (free_area.nr_free)

// Global block
static size_t buddy_physical_size;
static size_t buddy_virtual_size;
static size_t buddy_segment_size;
static size_t buddy_alloc_size;
static size_t *buddy_segment;
static struct Page *buddy_physical;
static struct Page *buddy_alloc;

#define MIN(a,b)                ((a)<(b)?(a):(b))

// Buddy operate
#define BUDDY_ROOT              (1)
#define BUDDY_LEFT(a)           ((a)<<1)
#define BUDDY_RIGHT(a)          (((a)<<1)+1)
#define BUDDY_PARENT(a)         ((a)>>1)
#define BUDDY_LENGTH(a)         (buddy_virtual_size/UINT32_ROUND_DOWN(a))
#define BUDDY_BEGIN(a)          (UINT32_REMAINDER(a)*BUDDY_LENGTH(a))
#define BUDDY_END(a)            ((UINT32_REMAINDER(a)+1)*BUDDY_LENGTH(a))
#define BUDDY_BLOCK(a,b)        (buddy_virtual_size/((b)-(a))+(a)/((b)-(a)))
#define BUDDY_EMPTY(a)          (buddy_segment[(a)] == BUDDY_LENGTH(a))

// Bitwise operate
#define UINT32_SHR_OR(a,n)      ((a)|((a)>>(n)))   
#define UINT32_MASK(a)          (UINT32_SHR_OR(UINT32_SHR_OR(UINT32_SHR_OR(UINT32_SHR_OR(UINT32_SHR_OR(a,1),2),4),8),16))    
#define UINT32_REMAINDER(a)     ((a)&(UINT32_MASK(a)>>1))
#define UINT32_ROUND_UP(a)      (UINT32_REMAINDER(a)?(((a)-UINT32_REMAINDER(a))<<1):(a))
#define UINT32_ROUND_DOWN(a)    (UINT32_REMAINDER(a)?((a)-UINT32_REMAINDER(a)):(a))

static void
buddy_init_size(size_t n) {
    assert(n > 1);
    buddy_physical_size = n;
    if (n < 512) {
        buddy_virtual_size = UINT32_ROUND_UP(n-1);
        buddy_segment_size = 1;
    } else {
        buddy_virtual_size = UINT32_ROUND_DOWN(n);
        buddy_segment_size = buddy_virtual_size*sizeof(size_t)*2/PGSIZE;
        if (n > buddy_virtual_size + (buddy_segment_size<<1)) {
            buddy_virtual_size <<= 1;
            buddy_segment_size <<= 1;
        }
    }
    buddy_alloc_size = MIN(buddy_virtual_size, buddy_physical_size-buddy_segment_size);
}

static void
buddy_init_segment(struct Page *base) {
    // Init address
    buddy_physical = base;
    buddy_segment = KADDR(page2pa(base));
    buddy_alloc = base + buddy_segment_size;
    memset(buddy_segment, 0, buddy_segment_size*PGSIZE);
    // Init segment
    nr_free += buddy_alloc_size;
    size_t block = BUDDY_ROOT;
    size_t alloc_size = buddy_alloc_size;
    size_t virtual_size = buddy_virtual_size;
    buddy_segment[block] = alloc_size;
    while (alloc_size > 0 && alloc_size < virtual_size) {
        virtual_size >>= 1;
        if (alloc_size > virtual_size) {
            // Add left to free list
            struct Page *page = &buddy_alloc[BUDDY_BEGIN(block)];
            page->property = virtual_size;
            list_add(&(free_list), &(page->page_link));
            buddy_segment[BUDDY_LEFT(block)] = virtual_size;
            // Switch ro right
            alloc_size -= virtual_size;
            buddy_segment[BUDDY_RIGHT(block)] = alloc_size;
            block = BUDDY_RIGHT(block);
        } else {
            // Switch to left
            buddy_segment[BUDDY_LEFT(block)] = alloc_size;
            buddy_segment[BUDDY_RIGHT(block)] = 0;
            block = BUDDY_LEFT(block);
        }
    }
    if (alloc_size > 0) {
        struct Page *page = &buddy_alloc[BUDDY_BEGIN(block)];
        page->property = alloc_size;
        list_add(&(free_list), &(page->page_link));
    }
}

static void
buddy_init(void) {
    list_init(&free_list);
    nr_free = 0;
}

static void
buddy_init_memmap(struct Page *base, size_t n) {
    assert(n > 0);
    // Init pages
    for (struct Page *p = base; p < base + n; p++) {
        assert(PageReserved(p));
        p->flags = p->property = 0;
    }
    // Init size
    buddy_init_size(n);
    // Init segment
    buddy_init_segment(base);
}

static struct Page *
buddy_alloc_pages(size_t n) {
    assert(n > 0);
    struct Page *page;
    size_t block = BUDDY_ROOT;
    size_t length = UINT32_ROUND_UP(n);
    // Find block
    while (length <= buddy_segment[block] && length < BUDDY_LENGTH(block)) {
        size_t left = BUDDY_LEFT(block);
        size_t right = BUDDY_RIGHT(block);
        if (BUDDY_EMPTY(block)) {                   // Split
            size_t begin = BUDDY_BEGIN(block);
            size_t end = BUDDY_END(block);
            size_t mid = (begin+end)>>1;
            list_del(&(buddy_alloc[begin].page_link));
            buddy_alloc[begin].property >>= 1;
            buddy_alloc[mid].property = buddy_alloc[begin].property;
            buddy_segment[left] = buddy_segment[block]>>1;
            buddy_segment[right] = buddy_segment[block]>>1;
            list_add(&free_list, &(buddy_alloc[begin].page_link));
            list_add(&free_list, &(buddy_alloc[mid].page_link));
            block = left;
        } else if (length & buddy_segment[left]) {  // Find in left (optimize)
            block = left;
        } else if (length & buddy_segment[right]) { // Find in right (optimize)
            block = right;
        } else if (length <= buddy_segment[left]) { // Find in left
            block = left;
        } else if (length <= buddy_segment[right]) {// Find in right
            block = right;
        } else {                                    // Shouldn't be here
            assert(0);
        }
    }
    // Allocate
    if (length > buddy_segment[block])
        return NULL;
    page = &(buddy_alloc[BUDDY_BEGIN(block)]);
    list_del(&(page->page_link));
    buddy_segment[block] = 0;
    nr_free -= length;
    // Update buddy segment
    while (block != BUDDY_ROOT) {
        block = BUDDY_PARENT(block);
        buddy_segment[block] = buddy_segment[BUDDY_LEFT(block)] | buddy_segment[BUDDY_RIGHT(block)];
    }
    return page;
}

static void
buddy_free_pages(struct Page *base, size_t n) {
    assert(n > 0);
    struct Page *p = base;
    size_t length = UINT32_ROUND_UP(n);
    // Find buddy id 
    size_t begin = (base-buddy_alloc);
    size_t end = begin + length;
    size_t block = BUDDY_BLOCK(begin, end);
    // Release block
    for (; p != base + n; p ++) {
        assert(!PageReserved(p));
        p->flags = 0;
        set_page_ref(p, 0);
    }
    base->property = length;
    list_add(&(free_list), &(base->page_link));
    nr_free += length;
    buddy_segment[block] = length;
    // Upadte & merge
    while (block != BUDDY_ROOT) {
        block = BUDDY_PARENT(block);
        size_t left = BUDDY_LEFT(block);
        size_t right = BUDDY_RIGHT(block);
        if (BUDDY_EMPTY(left) && BUDDY_EMPTY(right)) {  // Merge
            size_t lbegin = BUDDY_BEGIN(left);
            size_t rbegin = BUDDY_BEGIN(right);
            list_del(&(buddy_alloc[lbegin].page_link));
            list_del(&(buddy_alloc[rbegin].page_link));
            buddy_segment[block] = buddy_segment[left]<<1;
            buddy_alloc[lbegin].property = buddy_segment[left]<<1;
            list_add(&(free_list), &(buddy_alloc[lbegin].page_link));
        } else {                                        // Update
            buddy_segment[block] = buddy_segment[BUDDY_LEFT(block)] | buddy_segment[BUDDY_RIGHT(block)];
        }
    }
}

static size_t
buddy_nr_free_pages(void) {
    return nr_free;
}

static void
macro_check(void) {

    // Block operate check
    assert(BUDDY_ROOT == 1);
    assert(BUDDY_LEFT(3) == 6);
    assert(BUDDY_RIGHT(3) == 7);
    assert(BUDDY_PARENT(6) == 3);
    assert(BUDDY_PARENT(7) == 3);
    size_t buddy_virtual_size_store = buddy_virtual_size;
    size_t buddy_segment_root_store = buddy_segment[BUDDY_ROOT];
    buddy_virtual_size = 16;
    buddy_segment[BUDDY_ROOT] = 16;
    assert(BUDDY_LENGTH(6) == 4);
    assert(BUDDY_BEGIN(6) == 8);
    assert(BUDDY_END(6) == 12);
    assert(BUDDY_BLOCK(8, 12) == 6);
    assert(BUDDY_EMPTY(BUDDY_ROOT));
    buddy_virtual_size = buddy_virtual_size_store;
    buddy_segment[BUDDY_ROOT] = buddy_segment_root_store;

    // Bitwise operate check
    assert(UINT32_SHR_OR(0xCC, 2) == 0xFF);
    assert(UINT32_MASK(0x4000) == 0x7FFF);
    assert(UINT32_REMAINDER(0x4321) == 0x321);
    assert(UINT32_ROUND_UP(0x2321) == 0x4000);
    assert(UINT32_ROUND_UP(0x2000) == 0x2000);
    assert(UINT32_ROUND_DOWN(0x4321) == 0x4000);
    assert(UINT32_ROUND_DOWN(0x4000) == 0x4000);

}

static void
size_check(void) {

    size_t buddy_physical_size_store = buddy_physical_size;
    buddy_init_size(200);
    assert(buddy_virtual_size == 256);
    buddy_init_size(1024);
    assert(buddy_virtual_size == 1024);
    buddy_init_size(1026);
    assert(buddy_virtual_size == 1024);
    buddy_init_size(1028);    
    assert(buddy_virtual_size == 1024);
    buddy_init_size(1030);    
    assert(buddy_virtual_size == 2048);
    buddy_init_size(buddy_physical_size_store);   

}

static void
segment_check(void) {

    // Check buddy segment
    size_t total = 0, count = 0;
    for (size_t block = BUDDY_ROOT; block < (buddy_virtual_size<<1); block++)
        if (BUDDY_EMPTY(block))
            total += BUDDY_LENGTH(block);
        else if (block < buddy_virtual_size)
            assert(buddy_segment[block] == (buddy_segment[BUDDY_LEFT(block)] | buddy_segment[BUDDY_RIGHT(block)]));
    assert(total == nr_free_pages());

    // Check free list 
    total = 0, count = 0;
    list_entry_t *le = &free_list;
    while ((le = list_next(le)) != &free_list) {
        struct Page *p = le2page(le, page_link);
        count ++, total += p->property;
    }
    assert(total == nr_free_pages());

}

static void
alloc_check(void) {

    // Build buddy system for test
    size_t buddy_physical_size_store = buddy_physical_size;
    for (struct Page *p = buddy_physical; p < buddy_physical + 1026; p++)
        SetPageReserved(p);
    buddy_init();
    buddy_init_memmap(buddy_physical, 1026);

    // Check allocation
    struct Page *p0, *p1, *p2, *p3;
    p0 = p1 = p2 = NULL;
    assert((p0 = alloc_page()) != NULL);
    assert((p1 = alloc_page()) != NULL);
    assert((p2 = alloc_page()) != NULL);
    assert((p3 = alloc_page()) != NULL);

    assert(p0 + 1 == p1);
    assert(p1 + 1 == p2);
    assert(p2 + 1 == p3);
    assert(page_ref(p0) == 0 && page_ref(p1) == 0 && page_ref(p2) == 0 && page_ref(p3) == 0);

    assert(page2pa(p0) < npage * PGSIZE);
    assert(page2pa(p1) < npage * PGSIZE);
    assert(page2pa(p2) < npage * PGSIZE);
    assert(page2pa(p3) < npage * PGSIZE);

    list_entry_t *le = &free_list;
    while ((le = list_next(le)) != &free_list) {
        struct Page *p = le2page(le, page_link);
        assert(buddy_alloc_pages(p->property) != NULL);
    }

    assert(alloc_page() == NULL);

    // Check release
    free_page(p0);
    free_page(p1);
    free_page(p2);
    assert(nr_free == 3);

    assert((p1 = alloc_page()) != NULL);
    assert((p0 = alloc_pages(2)) != NULL);
    assert(p0 + 2 == p1);

    assert(alloc_page() == NULL);

    free_pages(p0, 2);
    free_page(p1);
    free_page(p3);

    struct Page *p;
    assert((p = alloc_pages(4)) == p0);
    assert(alloc_page() == NULL);

    assert(nr_free == 0);

    // Restore buddy system
    for (struct Page *p = buddy_physical; p < buddy_physical + buddy_physical_size_store; p++)
        SetPageReserved(p);
    buddy_init();
    buddy_init_memmap(buddy_physical, buddy_physical_size_store);

}

static void
default_check(void) {

    // Check buddy system
    macro_check();
    size_check();
    segment_check();
    alloc_check();
    
}

const struct pmm_manager buddy_pmm_manager = {
    .name = "buddy_pmm_manager",
    .init = buddy_init,
    .init_memmap = buddy_init_memmap,
    .alloc_pages = buddy_alloc_pages,
    .free_pages = buddy_free_pages,
    .nr_free_pages = buddy_nr_free_pages,
    .check = default_check,
};
```

## 附录：slub分配算法源代码

slub.h

```c
#ifndef __KERN_MM_SLUB_H__
#define  __KERN_MM_SLUB_H__

#include <pmm.h>
#include <list.h>

#define CACHE_NAMELEN 16

struct kmem_cache_t {
    list_entry_t slabs_full;
    list_entry_t slabs_partial;
    list_entry_t slabs_free;
    uint16_t objsize;
    uint16_t num;
    void (*ctor)(void*, struct kmem_cache_t *, size_t);
    void (*dtor)(void*, struct kmem_cache_t *, size_t);
    char name[CACHE_NAMELEN];
    list_entry_t cache_link;
};

struct kmem_cache_t *
kmem_cache_create(const char *name, size_t size,
                       void (*ctor)(void*, struct kmem_cache_t *, size_t),
                       void (*dtor)(void*, struct kmem_cache_t *, size_t));
void kmem_cache_destroy(struct kmem_cache_t *cachep);
void *kmem_cache_alloc(struct kmem_cache_t *cachep);
void *kmem_cache_zalloc(struct kmem_cache_t *cachep);
void kmem_cache_free(struct kmem_cache_t *cachep, void *objp);
size_t kmem_cache_size(struct kmem_cache_t *cachep);
const char *kmem_cache_name(struct kmem_cache_t *cachep);
int kmem_cache_shrink(struct kmem_cache_t *cachep);
int kmem_cache_reap();
void *kmalloc(size_t size);
void kfree(void *objp);
size_t ksize(void *objp);

void kmem_int();

#endif /* ! __KERN_MM_SLUB_H__ */
```

slub.c

```c
#include <slub.h>
#include <list.h>
#include <defs.h>
#include <string.h>
#include <stdio.h>

struct slab_t {
    int ref;                       
    struct kmem_cache_t *cachep;              
    uint16_t inuse;
    uint16_t free;
    list_entry_t slab_link;
};

// The number of sized cache : 16, 32, 64, 128, 256, 512, 1024, 2048
#define SIZED_CACHE_NUM     8
#define SIZED_CACHE_MIN     16
#define SIZED_CACHE_MAX     2048

#define le2slab(le,link)    ((struct slab_t*)le2page((struct Page*)le,link))
#define slab2kva(slab)      (page2kva((struct Page*)slab))

static list_entry_t cache_chain;
static struct kmem_cache_t cache_cache;
static struct kmem_cache_t *sized_caches[SIZED_CACHE_NUM];
static char *cache_cache_name = "cache";
static char *sized_cache_name = "sized";

// kmem_cache_grow - add a free slab
static void *
kmem_cache_grow(struct kmem_cache_t *cachep) {
    struct Page *page = alloc_page();
    void *kva = page2kva(page);
    // Init slub meta data
    struct slab_t *slab = (struct slab_t *) page;
    slab->cachep = cachep;
    slab->inuse = slab->free = 0;
    list_add(&(cachep->slabs_free), &(slab->slab_link));
    // Init bufctl
    int16_t *bufctl = kva;
    for (int i = 1; i < cachep->num; i++)
        bufctl[i-1] = i;
    bufctl[cachep->num-1] = -1;
    // Init cache 
    void *buf = bufctl + cachep->num;
    if (cachep->ctor) 
        for (void *p = buf; p < buf + cachep->objsize * cachep->num; p += cachep->objsize)
            cachep->ctor(p, cachep, cachep->objsize);
    return slab;
}

// kmem_slab_destroy - destroy a slab
static void
kmem_slab_destroy(struct kmem_cache_t *cachep, struct slab_t *slab) {
    // Destruct cache
    struct Page *page = (struct Page *) slab;
    int16_t *bufctl = page2kva(page);
    void *buf = bufctl + cachep->num;
    if (cachep->dtor)
        for (void *p = buf; p < buf + cachep->objsize * cachep->num; p += cachep->objsize)
            cachep->dtor(p, cachep, cachep->objsize);
    // Return slub page 
    page->property = page->flags = 0;
    list_del(&(page->page_link));
    free_page(page);
}

static int 
kmem_sized_index(size_t size) {
    // Round up 
    size_t rsize = ROUNDUP(size, 2);
    if (rsize < SIZED_CACHE_MIN)
        rsize = SIZED_CACHE_MIN;
    // Find index
    int index = 0;
    for (int t = rsize / 32; t; t /= 2)
        index ++;
    return index;
}

// ! Test code
#define TEST_OBJECT_LENTH 2046
#define TEST_OBJECT_CTVAL 0x22
#define TEST_OBJECT_DTVAL 0x11

static const char *test_object_name = "test";

struct test_object {
    char test_member[TEST_OBJECT_LENTH];
};

static void
test_ctor(void* objp, struct kmem_cache_t * cachep, size_t size) {
    char *p = objp;
    for (int i = 0; i < size; i++)
        p[i] = TEST_OBJECT_CTVAL;
}

static void
test_dtor(void* objp, struct kmem_cache_t * cachep, size_t size) {
    char *p = objp;
    for (int i = 0; i < size; i++)
        p[i] = TEST_OBJECT_DTVAL;
}

static size_t 
list_length(list_entry_t *listelm) {
    size_t len = 0;
    list_entry_t *le = listelm;
    while ((le = list_next(le)) != listelm)
        len ++;
    return len;
}

static void 
check_kmem() {

    assert(sizeof(struct Page) == sizeof(struct slab_t));

    size_t fp = nr_free_pages();

    // Create a cache 
    struct kmem_cache_t *cp0 = kmem_cache_create(test_object_name, sizeof(struct test_object), test_ctor, test_dtor);
    assert(cp0 != NULL);
    assert(kmem_cache_size(cp0) == sizeof(struct test_object));
    assert(strcmp(kmem_cache_name(cp0), test_object_name) == 0);
    // Allocate six objects
    struct test_object *p0, *p1, *p2, *p3, *p4, *p5;
    char *p;
    assert((p0 = kmem_cache_alloc(cp0)) != NULL);
    assert((p1 = kmem_cache_alloc(cp0)) != NULL);
    assert((p2 = kmem_cache_alloc(cp0)) != NULL);
    assert((p3 = kmem_cache_alloc(cp0)) != NULL);
    assert((p4 = kmem_cache_alloc(cp0)) != NULL);
    p = (char *) p4;
    for (int i = 0; i < sizeof(struct test_object); i++)
        assert(p[i] == TEST_OBJECT_CTVAL);
    assert((p5 = kmem_cache_zalloc(cp0)) != NULL);
    p = (char *) p5;
    for (int i = 0; i < sizeof(struct test_object); i++)
        assert(p[i] == 0);
    assert(nr_free_pages()+3 == fp);
    assert(list_empty(&(cp0->slabs_free)));
    assert(list_empty(&(cp0->slabs_partial)));
    assert(list_length(&(cp0->slabs_full)) == 3);
    // Free three objects 
    kmem_cache_free(cp0, p3);
    kmem_cache_free(cp0, p4);
    kmem_cache_free(cp0, p5);
    assert(list_length(&(cp0->slabs_free)) == 1);
    assert(list_length(&(cp0->slabs_partial)) == 1);
    assert(list_length(&(cp0->slabs_full)) == 1);
    // Shrink cache 
    assert(kmem_cache_shrink(cp0) == 1);
    assert(nr_free_pages()+2 == fp);
    assert(list_empty(&(cp0->slabs_free)));
    p = (char *) p4;
    for (int i = 0; i < sizeof(struct test_object); i++)
        assert(p[i] == TEST_OBJECT_DTVAL);
    // Reap cache 
    kmem_cache_free(cp0, p0);
    kmem_cache_free(cp0, p1);
    kmem_cache_free(cp0, p2);
    assert(kmem_cache_reap() == 2);
    assert(nr_free_pages() == fp);
    // Destory a cache 
    kmem_cache_destroy(cp0);

    // Sized alloc 
    assert((p0 = kmalloc(2048)) != NULL);
    assert(nr_free_pages()+1 == fp);
    kfree(p0);
    assert(kmem_cache_reap() == 1);
    assert(nr_free_pages() == fp);

    cprintf("check_kmem() succeeded!\n");

}
// ! End of test code

// kmem_cache_create - create a kmem_cache
struct kmem_cache_t *
kmem_cache_create(const char *name, size_t size,
                       void (*ctor)(void*, struct kmem_cache_t *, size_t),
                       void (*dtor)(void*, struct kmem_cache_t *, size_t)) {
    assert(size <= (PGSIZE - 2));
    struct kmem_cache_t *cachep = kmem_cache_alloc(&(cache_cache));
    if (cachep != NULL) {
        cachep->objsize = size;
        cachep->num = PGSIZE / (sizeof(int16_t) + size);
        cachep->ctor = ctor;
        cachep->dtor = dtor;
        memcpy(cachep->name, name, CACHE_NAMELEN);
        list_init(&(cachep->slabs_full));
        list_init(&(cachep->slabs_partial));
        list_init(&(cachep->slabs_free));
        list_add(&(cache_chain), &(cachep->cache_link));
    }
    return cachep;
}

// kmem_cache_destroy - destroy a kmem_cache
void 
kmem_cache_destroy(struct kmem_cache_t *cachep) {
    list_entry_t *head, *le;
    // Destory full slabs
    head = &(cachep->slabs_full);
    le = list_next(head);
    while (le != head) {
        list_entry_t *temp = le;
        le = list_next(le);
        kmem_slab_destroy(cachep, le2slab(temp, page_link));
    }
    // Destory partial slabs 
    head = &(cachep->slabs_partial);
    le = list_next(head);
    while (le != head) {
        list_entry_t *temp = le;
        le = list_next(le);
        kmem_slab_destroy(cachep, le2slab(temp, page_link));
    }
    // Destory free slabs 
    head = &(cachep->slabs_free);
    le = list_next(head);
    while (le != head) {
        list_entry_t *temp = le;
        le = list_next(le);
        kmem_slab_destroy(cachep, le2slab(temp, page_link));
    }
    // Free kmem_cache 
    kmem_cache_free(&(cache_cache), cachep);
}   

// kmem_cache_alloc - allocate an object
void *
kmem_cache_alloc(struct kmem_cache_t *cachep) {
    list_entry_t *le = NULL;
    // Find in partial list 
    if (!list_empty(&(cachep->slabs_partial)))
        le = list_next(&(cachep->slabs_partial));
    // Find in empty list 
    else {
        if (list_empty(&(cachep->slabs_free)) && kmem_cache_grow(cachep) == NULL)
            return NULL;
        le = list_next(&(cachep->slabs_free));
    }
    // Alloc 
    list_del(le);
    struct slab_t *slab = le2slab(le, page_link);
    void *kva = slab2kva(slab);
    int16_t *bufctl = kva;
    void *buf = bufctl + cachep->num;
    void *objp = buf + slab->free * cachep->objsize;
    // Update slab
    slab->inuse ++;
    slab->free = bufctl[slab->free];
    if (slab->inuse == cachep->num)
        list_add(&(cachep->slabs_full), le);
    else 
        list_add(&(cachep->slabs_partial), le);
    return objp;
}

// kmem_cache_zalloc - allocate an object and fill it with zero
void *
kmem_cache_zalloc(struct kmem_cache_t *cachep) {
    void *objp = kmem_cache_alloc(cachep);
    memset(objp, 0, cachep->objsize);
    return objp;
}

// kmem_cache_free - free an object
void 
kmem_cache_free(struct kmem_cache_t *cachep, void *objp) {
    // Get slab of object 
    void *base = page2kva(pages);
    void *kva = ROUNDDOWN(objp, PGSIZE);
    struct slab_t *slab = (struct slab_t *) &pages[(kva-base)/PGSIZE];
    // Get offset in slab
    int16_t *bufctl = kva;
    void *buf = bufctl + cachep->num;
    int offset = (objp - buf) / cachep->objsize;
    // Update slab 
    list_del(&(slab->slab_link));
    bufctl[offset] = slab->free;
    slab->inuse --;
    slab->free = offset;
    if (slab->inuse == 0)
        list_add(&(cachep->slabs_free), &(slab->slab_link));
    else 
        list_add(&(cachep->slabs_partial), &(slab->slab_link));
}

// kmem_cache_size - get object size
size_t 
kmem_cache_size(struct kmem_cache_t *cachep) {
    return cachep->objsize;
}

// kmem_cache_name - get cache name
const char *
kmem_cache_name(struct kmem_cache_t *cachep) {
    return cachep->name;
}

// kmem_cache_shrink - destroy all slabs in free list 
int 
kmem_cache_shrink(struct kmem_cache_t *cachep) {
    int count = 0;
    list_entry_t *le = list_next(&(cachep->slabs_free));
    while (le != &(cachep->slabs_free)) {
        list_entry_t *temp = le;
        le = list_next(le);
        kmem_slab_destroy(cachep, le2slab(temp, page_link));
        count ++;
    }
    return count;
}

// kmem_cache_reap - reap all free slabs 
int 
kmem_cache_reap() {
    int count = 0;
    list_entry_t *le = &(cache_chain);
    while ((le = list_next(le)) != &(cache_chain))
        count += kmem_cache_shrink(to_struct(le, struct kmem_cache_t, cache_link));
    return count;
}

void *
kmalloc(size_t size) {
    assert(size <= SIZED_CACHE_MAX);
    return kmem_cache_alloc(sized_caches[kmem_sized_index(size)]);
}

void 
kfree(void *objp) {
    void *base = slab2kva(pages);
    void *kva = ROUNDDOWN(objp, PGSIZE);
    struct slab_t *slab = (struct slab_t *) &pages[(kva-base)/PGSIZE];
    kmem_cache_free(slab->cachep, objp);
}

void
kmem_int() {

    // Init cache for kmem_cache
    cache_cache.objsize = sizeof(struct kmem_cache_t);
    cache_cache.num = PGSIZE / (sizeof(int16_t) + sizeof(struct kmem_cache_t));
    cache_cache.ctor = NULL;
    cache_cache.dtor = NULL;
    memcpy(cache_cache.name, cache_cache_name, CACHE_NAMELEN);
    list_init(&(cache_cache.slabs_full));
    list_init(&(cache_cache.slabs_partial));
    list_init(&(cache_cache.slabs_free));
    list_init(&(cache_chain));
    list_add(&(cache_chain), &(cache_cache.cache_link));

    // Init sized cache 
    for (int i = 0, size = 16; i < SIZED_CACHE_NUM; i++, size *= 2)
        sized_caches[i] = kmem_cache_create(sized_cache_name, size, NULL, NULL); 

    check_kmem();
}
```

