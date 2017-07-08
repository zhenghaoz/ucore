## 练习1: 使用 Round Robin 调度算法

1. **请理解并分析sched_calss中各个函数指针的用法，并接合Round Robin 调度算法描述ucore的调度执行过程**

###### sched_class 结构体

```c
struct sched_class {
    // 调度器名称
    const char *name;
    // 队列数据结构
    void (*init)(struct run_queue *rq);
    // 将进程加入调度器队列
    void (*enqueue)(struct run_queue *rq, struct proc_struct *proc);
    // 将进程从调度器队列中移除
    void (*dequeue)(struct run_queue *rq, struct proc_struct *proc);
    // 获取调度器选择的进程
    struct proc_struct *(*pick_next)(struct run_queue *rq);
    // 更新调度器的时钟信息
    void (*proc_tick)(struct run_queue *rq, struct proc_struct *proc);
};
```

###### Round Robin 调度算法

RR算法就是将所有的进程加入到一个队列中，每个进程都拥有相同的运行时间。每次调度器都会从队列中取出一个进程，如果进程在规定运行时间内没有结束，那么需要重新分配运行时间并将进程重新加入队列尾部。为了能够使用不同调度算法实现的调度器，实验6增加了以下修改：

###### 调度器初始化

实验6增加了调度初始化函数`sched_init`，需要内核初始化过程中调用这个函数，这个函数负责选择调度器并且对选择的调度器进行初始化。

###### 将进程加入调度器

当进程被唤醒后，需要调用`sched_class_enqueue`将其加入到调度器中。

###### 进程调度

调度函数`schedule`变化如下：

- 在切换进程之前调用`sched_class_enqueue`将当前进程加入到RR的调度链表中；
- 调用`sched_class_pick_next`获取RR算法选取的下一个进程；
- 调用`sched_class_dequeue`将即将运行的进程从RR算法调度链表中删除。

###### 调度器时钟更新

每经过100个滴答之后，需要调用`sched_class_proc_tick`更新调度器中的时钟。

2. **请在实验报告中简要说明如何设计实现”多级反馈队列调度算法“，给出概要设计，鼓励给出详细设计**


**多级反馈队列调度算法**过程如下：

- 多级反馈队列调度算法维护多个队列，每个新的进程加入$$Q_0$$中；
- 每次选择进程执行的之后从$$Q_0$$开始向$$Q_n$$查找，如果某个队列非空，那么从这个队列中取出一个进程；
- 如果来自$$Q_i$$某个进程在时间片用完之后没结束，那么将这个进程加入$$Q_{i+1}$$，时间片加倍。

#### 数据结构

首先需要在run_queue中增加多个队列：

```c
struct run_queue {
	...
    // For Multi-Level Feedback Queue Scheduling ONLY
    list_entry_t multi_run_list[MULTI_QUEUE_NUM];
};
```

然后在proc_struct中增加进程的队列号（优先级）：

```c
struct proc_struct {
	...
    int multi_level;                            // FOR Multi-Level Feedback Queue Scheduling ONLY: the level of queue
};
```

#### 算法实现

###### multi_init

需要初始化每一个级别的队列。

```c
static void multi_init(struct run_queue *rq) {
    for (int i = 0; i < MULTI_QUEUE_NUM; i++)
        list_init(&(rq->multi_run_list[i]));
    rq->proc_num = 0;
}
```

###### multi_enqueue

- 如果进程上一个时间片用完了，考虑增加level（降低优先级）；
- 加入level对应的队列；
- 设置level对应的时间片；
- 增加计数值。

```c
static void multi_enqueue(struct run_queue *rq, struct proc_struct *proc) {
    int level = proc->multi_level;
    if (proc->time_slice == 0 && level < (MULTI_QUEUE_NUM-1))
        level ++;
    proc->multi_level = level;
    list_add_before(&(rq->multi_run_list[level]), &(proc->run_link));
    if (proc->time_slice == 0 || proc->time_slice > (rq->max_time_slice << level))
        proc->time_slice = (rq->max_time_slice << level);
    proc->rq = rq;
    rq->proc_num ++;
}
```

###### multi_dequeue

将进程从对应的链表删除。

```c
static void multi_dequeue(struct run_queue *rq, struct proc_struct *proc) {
    list_del_init(&(proc->run_link));
    rq->proc_num --;
}
```

###### multi_pick_next

按照优先级顺序检查每个队列，如果队列存在进程，那么选择这个进程。

```c
static struct proc_struct *multi_pick_next(struct run_queue *rq) {
    for (int i = 0; i < MULTI_QUEUE_NUM; i++)
        if (!list_empty(&(rq->multi_run_list[i])))
            return le2proc(list_next(&(rq->multi_run_list[i])), run_link);
    return NULL;
}
```

multi_proc_tick

这和RR算法是一样的。

## 练习2: 实现 Stride Scheduling 调度算法

###### stride_init

Stride Scheduling需要使用优先队列来决定下一个需要调度的进程，所以需要：

- 将优先队列置为空（NULL）；
- 将进程数目初始化为0。

```c
static void stride_init(struct run_queue *rq) 
    rq->lab6_run_pool = NULL;
    rq->proc_num = 0;
}
```

###### stride_enqueue

- 将进程插入到优先队列中；
- 更新进程的剩余时间片；
- 设置进程的队列指针；
- 增加进程计数值。

```c
static void stride_enqueue(struct run_queue *rq, struct proc_struct *proc) {
    rq->lab6_run_pool = skew_heap_insert(rq->lab6_run_pool, &(proc->lab6_run_pool), proc_stride_comp_f);
    if (proc->time_slice == 0 || proc->time_slice > rq->max_time_slice)
        proc->time_slice = rq->max_time_slice;
    proc->rq = rq;
    rq->proc_num ++;
}
```

###### stride_dequeue

- 将进程从优先队列中移除；
- 将进程计数值减一。

```c
static void stride_dequeue(struct run_queue *rq, struct proc_struct *proc) {
    rq->lab6_run_pool = skew_heap_remove(rq->lab6_run_pool, &(proc->lab6_run_pool), proc_stride_comp_f);
    rq->proc_num --;
}
```
###### stride_pick_next

- 如果队列为空，返回空指针；
- 从优先队列中获得一个进程（就是指针所指的进程控制块）；
- 更新stride值。

```c
static struct proc_struct *stride_pick_next(struct run_queue *rq) {
    if (rq->lab6_run_pool == NULL)
        return NULL;
    skew_heap_entry_t *le = rq->lab6_run_pool;
    struct proc_struct * p = le2proc(le, lab6_run_pool);
    p->lab6_stride += BIG_STRIDE / p->lab6_priority;
    return p;
}
```
###### stride_proc_tick

这和RR算法是一样的。

## 扩展练习 Challenge :实现 Linux 的 CFS 调度算法

CFS算法的基本思路就是尽量使得每个进程的运行时间相同，所以需要记录每个进程已经运行的时间：

```c
struct proc_struct {
	...
    int fair_run_time;                          // FOR CFS ONLY: run time
};
```

每次调度的时候，选择已经运行时间最少的进程。所以，也就需要一个数据结构来快速获得最少运行时间的进程，CFS算法选择的是红黑树，但是项目中的斜堆也可以实现，只是性能不及红黑树。CFS是对于**优先级**的实现方法就是让优先级低的进程的时间过得很快。

#### 数据结构

首先需要在run_queue增加一个斜堆：

```c
struct run_queue {
	...
    skew_heap_entry_t *fair_run_pool;
};
```

在proc_struct中增加三个成员：

- 虚拟运行时间
- 优先级系数：从1开始，数值越大，时间过得越快
- 斜堆

```c
struct proc_struct {
	...
    int fair_run_time;                          // FOR CFS ONLY: run time
    int fair_priority;                          // FOR CFS ONLY: priority
    skew_heap_entry_t fair_run_pool;            // FOR CFS ONLY: run pool
};
```

#### 算法实现

###### proc_fair_comp_f

首先需要一个比较函数，同样根据$$MAX\_RUNTIME-MIN\_RUNTIE<MAX\_PRIORITY$$完全不需要考虑虚拟运行时溢出的问题。

```c
static int proc_fair_comp_f(void *a, void *b)
{
     struct proc_struct *p = le2proc(a, fair_run_pool);
     struct proc_struct *q = le2proc(b, fair_run_pool);
     int32_t c = p->fair_run_time - q->fair_run_time;
     if (c > 0) return 1;
     else if (c == 0) return 0;
     else return -1;
}
```

###### fair_init

```c
static void fair_init(struct run_queue *rq) {
    rq->fair_run_pool = NULL;
    rq->proc_num = 0;
}
```

###### fair_enqueue

和Stride Scheduling类型，但是不需要更新stride。

```c
static void fair_enqueue(struct run_queue *rq, struct proc_struct *proc) {
    rq->fair_run_pool = skew_heap_insert(rq->fair_run_pool, &(proc->fair_run_pool), proc_fair_comp_f);
    if (proc->time_slice == 0 || proc->time_slice > rq->max_time_slice)
        proc->time_slice = rq->max_time_slice;
    proc->rq = rq;
    rq->proc_num ++;
}
```

###### fair_dequeue

```c
static void fair_dequeue(struct run_queue *rq, struct proc_struct *proc) {
    rq->fair_run_pool = skew_heap_remove(rq->fair_run_pool, &(proc->fair_run_pool), proc_fair_comp_f);
    rq->proc_num --;
}
```

###### fair_pick_next

```c
static struct proc_struct * fair_pick_next(struct run_queue *rq) {
    if (rq->fair_run_pool == NULL)
        return NULL;
    skew_heap_entry_t *le = rq->fair_run_pool;
    struct proc_struct * p = le2proc(le, fair_run_pool);
    return p;
}
```

###### fair_proc_tick

需要更新虚拟运行时，增加的量为优先级系数。

```c
static void
fair_proc_tick(struct run_queue *rq, struct proc_struct *proc) {
    if (proc->time_slice > 0) {
        proc->time_slice --;
        proc->fair_run_time += proc->fair_priority;
    }
    if (proc->time_slice == 0) {
        proc->need_resched = 1;
    }
}
```

#### 兼容调整

为了保证测试可以通过，需要将Stride Scheduling的优先级对应到CFS的优先级：

```c
void lab6_set_priority(uint32_t priority)
{
    ...
    // FOR CFS ONLY
    current->fair_priority = 60 / current->lab6_priority + 1;
    if (current->fair_priority < 1)
        current->fair_priority = 1;
}
```

由于调度器需要通过虚拟运行时间确定下一个进程，如果虚拟运行时间最小的进程需要yield，那么必须增加虚拟运行时间，例如可以增加一个时间片的运行时。

```c
int do_yield(void) {
    ...
    // FOR CFS ONLY
    current->fair_run_time += current->rq->max_time_slice * current->fair_priority;
    return 0;
}
```

## 遇到的问题

1. **为什么 CFS 调度算法使用红黑树而不使用堆来获取最小运行时进程？（已经自行解决）**

查阅了网上的资料以及自己分析，得到如下结论：

- 堆基于数组，但是对于调度器来说进程数量不确定，无法使用定长数组实现的堆；
- uCore中的 Stride Scheduling 调度算法使用了斜堆，但是斜堆没有维护平衡的要求，可能导致斜堆退化成为有序链表，影响性能。

综上所示，红黑树因为平衡性以及非连续所以是CFS算法最佳选择。

## 参考资料

- [Stride Scheduling: Deterministic Proportional-Share Resource Management (1995)](http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.138.3502&rank=1)
- [G53OPS : Process Scheduling](http://www.cs.nott.ac.uk/~pszgxk/courses/g53ops/Scheduling/sched09-mlfqs.html)
- [Linux 2.6 Completely Fair Scheduler 内幕](https://www.ibm.com/developerworks/cn/linux/l-completely-fair-scheduler/)
- [斜堆 - 维基百科，自由的百科全书](https://zh.wikipedia.org/wiki/%E6%96%9C%E5%A0%86)