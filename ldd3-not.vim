ch6. 高级字符驱动操作
  6.1 ioctl接口
    user space: int ioctl(int fd, unsigned long cmd, ...);
    kernel space: int (*ioctl) (struct inode *inode, struct file *filp, unsigned int cmd, unsigned long arg);
    inode 和 filp 指针是对应应用程序传递的文件描述符 fd 的值, 和传递给 open 方法的相同参数.
    6.1.1 选择ioctl命令
      根据 Linux 内核惯例来为你的驱动选择 ioctl 号, 你应当首先检查 include/asm/ioctl.h 和
    Documentation/ioctl-number.txt. 这个头文件定义你将使用的位段: type(魔数), 序号, 传输方向, 和参数大小. ioctl-number.txt 文件列举了在内核中使用的魔数,[20] 因此你将可选择你自己的魔数并且避免交叠. 这个文本文件也列举了为什么应当使用惯例的原因.
      ioctl 命令号　４个位段
      type

      number

      direction

      size
    ** 地址校验，<asm/uaccess.h> access_ok():
      (API) int access_ok(int type, const void *addr, unsigned long size) first para is VERIFY_READ or VERIFY_WRITE 在需要读写操作 VERIFY_WRITE.
      return value: 1 success, 0 failed 驱动则返回-EFAULT给调用者。
    (API) put_user(datum, ptr) 写datum到用户空间
    __put_user(datum, ptr) 此接口用在已经进行access_ok检查过的时候
    作为一个通用的规则, 当你实现一个 read 方法时, 调用 __put_user 来节省几个周期, 或者当你拷贝几个项时, 因此, 在第一次数据传送之前调用 access_ok 一次。
    (API) get_user(local, ptr) 从用户空间接收单个数据
    __get_user(local, ptr)
    6.1.5 能力和受限操作
      (API) capget or capset系统调用使用能力
      全部能力可在 <linux/capability.h> 中找到. 如下面所示：
      CAP_DAC_OVERRIDE
      这个能力来推翻在文件和目录上的存取的限制(数据存取控制, 或者 DAC).

      CAP_NET_ADMIN
      进行网络管理任务的能力, 包括那些能够影响网络接口的.

      CAP_SYS_MODULE
      加载或去除内核模块的能力.

      CAP_SYS_RAWIO
      进行 "raw" I/O 操作的能力. 例子包括存取设备端口或者直接和 USB 设备通讯.

      CAP_SYS_ADMIN
      一个捕获-全部的能力, 提供对许多系统管理操作的存取.

      CAP_SYS_TTY_CONFIG
      进行 tty 配置任务的能力.
      能力检查是通过 capable 函数来进行的(定义在 <linux/sched.h>):
      (API)  int capable(int capability);
      在 scull 例子驱动中, 任何用户被许可来查询 quantum 和 quantum 集的大小. 只有特权用户, 但是, 可改变这些值, 因为不适当的值可能很坏地影响系统性能. 当需要时, ioctl 的 scull 实现检查用户的特权级别, 如下:
        if (! capable (CAP_SYS_ADMIN))
          return -EPERM;
    6.1.6. ioctl 命令的实现
      if (! capable (CAP_SYS_ADMIN))
        return -EPERM;
      int quantum;
      ioctl(fd,SCULL_IOCSQUANTUM, &quantum);/* Set by pointer */
      ioctl(fd,SCULL_IOCTQUANTUM, quantum); 	/* Set by value */
      ioctl(fd,SCULL_IOCGQUANTUM, &quantum);/* Get by pointer */
      quantum = ioctl(fd,SCULL_IOCQQUANTUM);	/* Get by return value */
      ioctl(fd,SCULL_IOCXQUANTUM, &quantum);/* Exchange by pointer */
      quantum = ioctl(fd,SCULL_IOCHQUANTUM, quantum); /* Exchange by value */
  6.2 阻塞ＩＯ
    6.2.1 睡眠
      以安全的方式编码睡眠,有几个规则必须记住:
        1:)  当你运行在原子上下文时不能睡眠.如spinlock,seqlock,RCU lock.关中断.信号量.
        2:)  你不能关于你醒后的系统状态做任何的假设, 并且你必须检查来确保你在等待的条件是, 确实, 真的.
        3:)  是你的进程不能睡眠除非确信其他人, 在某处的, 将唤醒它.
      一个等待队列由一个"等待队列头"来管理, 一个 wait_queue_head_t 类型的结构, 定义在<linux/wait.h>中. 一个等待队列头可被定义和初始化, 使用:

    (API) DECLARE_WAIT_QUEUE_HEAD(name); 
    或者动态地, 如下:

    wait_queue_head_t my_queue;
    (API) init_waitqueue_head(&my_queue);
    6.2.2 简单睡眠
      睡眠的最简单方式是一个宏定义, 称为 wait_event(有几个变体)
      (API) wait_event(queue, condition)
            wait_event_interruptible(queue, condition)
            wait_event_timeout(queue, condition, timeout)
            wait_event_interruptible_timeout(queue, condition, timeout)
      另一半就是唤醒，
      (API) void wake_up(wait_queue_head_t *queue);
            void wake_up_interruptible(wait_queue_head_t *queue);
    6.2.3 阻塞和非阻塞操作
      明确的非阻塞 I/O 由 filp->f_flags 中的 O_NONBLOCK 标志来指示. 这个标志定义于 <linux/fcntl.h>, 被 <linux/fs.h>自动包含. 
    6.2.5. 高级睡眠
      使用至今我们已涉及到的函数,许多驱动能够满足它们的睡眠要求.
    6.2.5.1. 一个进程如何睡眠
      深入 <linux/wait.h>, wait_queue_head_t,它包含一个自旋锁和一个链表.这个链表是一个等待队列入口, 它被声明做 wait_queue_t.
      第一步常常是分配和初始化一个 wait_queue_t 结构, 随后将其添加到正确的等待队列.
      下一步是设置进程的状态来标志它为睡眠. <linux/sched.h> 中定义有几个任务状态:
        TASK_RUNNING, 有 2 个状态指示一个进程是在睡眠: TASK_INTERRUPTIBLE 和 TASK_UNTINTERRUPTIBLE;
      void set_current_state(int new_state);
      if (!condition)
        schedule();
    6.2.5.2. 手动睡眠
      (API)
      1. DEFINE_WAIT(my_wait); or wati_queue_t my_wait; init_wait(&my_wait);
      2. void prepare_to_wait(wait_queue_head_t *queue,
                              wait_queue_t *wait,
                              int state);  //state is TASK_INTERRUPTIBLE or TASK_UNTINTERRUPTIBLE;
      3.检查趋势需要睡眠等待，则调用schedule();
      4. finish_wait(wait_queue_head_t *queuq, wait_queue_t *wait); 
      5. 检查状态，看是否需要再次睡眠等待。if (signal_pending(current)) return -ERESTARTSYS;
    6.2.5.3. 互斥等待
      1. 当一个等待队列入口有 WQ_FLAG_EXCLUSEVE 标志置位, 它被添加到等待队列的尾部. 没有这个标志的入口项, 相反, 添加到开始.
      2. 当 wake_up 被在一个等待队列上调用, 它在唤醒第一个有 WQ_FLAG_EXCLUSIVE 标志的进程后停止.
      (API) void prepare_to_wait_exclusive(wait_queue_head_t *queue, wait_queue_t *wait, int state); 
    6.2.5.4. 唤醒的细节
      <linux/wait.h>
      (API)   wake_up(wait_queue_head_t *queue);
              wake_up_interruptible(wait_queue_head_t *queue);
              wake_up_nr(wait_queue_head_t *queue, int nr);
              wake_up_interruptible_nr(wait_queue_head_t *queue, int nr);
              wake_up_all(wait_queue_head_t *queue);
              wake_up_interruptible_all(wait_queue_head_t *queue);
              wake_up_interruptible_sync(wait_queue_head_t *queue);
    6.3 poll 和　select
      (API)   unsigned int (*poll) (struct file *filp, poll_table *wait);
              void poll_wait (struct file *, wait_queue_head_t *, poll_table *);
      在 <linux/poll.h>中声明, 这个文件必须被驱动源码包含. 几个标志(通过 <linux/poll.h> 定义)用来指示可能的操作:
      POLLIN
      如果设备可被不阻塞地读, 这个位必须设置.

      ***POLLRDNORM
      这个位必须设置, 如果"正常"数据可用来读. 一个可读的设备返回( POLLIN|POLLRDNORM ).

      **POLLRDBAND
      这个位指示带外数据可用来从设备中读取. 当前只用在 Linux 内核的一个地方( DECnet 代码 )并且通常对设备驱动不可用.

      POLLPRI
      高优先级数据(带外)可不阻塞地读取. 这个位使 select 报告在文件上遇到一个异常情况, 因为 selct 报告带外数据作为一个异常情况.

      POLLHUP
      当读这个设备的进程见到文件尾, 驱动必须设置 POLLUP(hang-up). 一个调用 select 的进程被告知设备是可读的, 如同 selcet 功能所规定的.

      POLLERR
      一个错误情况已在设备上发生. 当调用 poll, 设备被报告位可读可写, 因为读写都返回一个错误码而不阻塞.

      POLLOUT
      这个位在返回值中设置, 如果设备可被写入而不阻塞.

      POLLWRNORM
      这个位和 POLLOUT 有相同的含义, 并且有时它确实是相同的数. 一个可写的设备返回( POLLOUT|POLLWRNORM).

      **POLLWRBAND
      如同 POLLRDBAND , 这个位意思是带有零优先级的数据可写入设备. 只有 poll 的数据报实现使用这个位, 因为一个数据报看传送带外数据.
      **应当重复一下 POLLRDBAND 和 POLLWRBAND 仅仅对关联到 socket 的文件描述符有意义: 通常设备驱动不使用这些标志.
    6.4. 异步通知
      2 个步骤来使能来自输入文件的异步通知. 
      1. 指定一个进程作为文件的拥有者.一个进程使用 fcntl 系统调用发出 F_SETOWN 命令, 这个拥有者进程的 ID 被保存在 filp->f_owner 给以后使用.
      2. 用户程序必须设置 FASYNC 标志在设备中, 通过 F_SETFL fcntl 命令.
      如, 下面的用户程序中的代码行使能了异步的通知到当前进程, 给 stdin 输入文件:
      (API)
        signal(SIGIO, &input_handler); /* dummy sample; sigaction() is better */
        fcntl(STDIN_FILENO, F_SETOWN, getpid());
        oflags = fcntl(STDIN_FILENO, F_GETFL);
        fcntl(STDIN_FILENO, F_SETFL, oflags | FASYNC);
      输入通知有一个剩下的问题. 当一个进程收到一个 SIGIO, 它不知道哪个输入文件有新数据提供. 如果多于一个文件被使能异步地通知挂起输入的进程, 应用程序必须仍然靠 poll 或者 select 来找出发生了什么.
    6.5.1. llseek 实现
      更新filp->f_ops;
     设备不支持 llseek , 通过调用 nonseekable_open 在你的 open 方法中.
      (API)  int nonseekable_open(struct inode *inode; struct file *filp); 
          完整起见, 你也应该在你的 file_operations 结构中设置 llseek 方法到一个特殊的帮忙函数 no_llseek, 它定义在 <linux/fs.h>.
    6.6. 在一个设备文件上的存取控制
    6.6.1. 单 open 设备
    6.6.2. 一次对一个用户限制存取
      spin_lock(&scull_u_lock);
      if (scull_u_count &&
          (scull_u_owner != current->uid) && /* allow user */
          (scull_u_owner != current->euid) && /* allow whoever did su */
          !capable(CAP_DAC_OVERRIDE)) { /* still allow root */
        spin_unlock(&scull_u_lock);
        return -EBUSY; /* -EPERM would confuse the user */
      }

      if (scull_u_count = = 0)
          scull_u_owner = current->uid; /* grab it */
      scull_u_count++;
      spin_unlock(&scull_u_lock); 
    6.6.3. 阻塞 open 作为对 EBUSY 的替代
      spin_lock(&scull_w_lock);
      while (! scull_w_available( )) {
        spin_unlock(&scull_w_lock);
        if (filp->f_flags & O_NONBLOCK) return -EAGAIN;
        if (wait_event_interruptible (scull_w_wait, scull_w_available( )))
          return -ERESTARTSYS; /* tell the fs layer to handle it */
        spin_lock(&scull_w_lock);
      }
      if (scull_w_count = = 0)
        scull_w_owner = current->uid; /* grab it */
      scull_w_count++;
      spin_unlock(&scull_w_lock); 
      release 方法, 接着, 负责唤醒任何挂起的进程:

      static int scull_w_release(struct inode *inode, struct file *filp)
      {

        int temp;
        spin_lock(&scull_w_lock);
        scull_w_count--;
        temp = scull_w_count;
        spin_unlock(&scull_w_lock); 
        if (temp == 0)
          wake_up_interruptible_sync(&scull_w_wait); /* awake other uid's */
        return 0;
      }
      这是一个例子, 这里调用 wake_up_interruptible_sync 是有意义的. 当我们做这个唤醒, 我们只是要返回到用户空间, 这对于系统是一个自然的调度点. 当我们做这个唤醒时不是潜在地重新调度, 最好只是调用 "sync" 版本并且完成我们的工作.
    6.6.4. 在 open 时复制设备

                                                第 7 章 时间, 延时, 和延后工作
    7.1.1. 使用 jiffies 计数器
       <linux/jiffies.h>, 尽管你会常常只是包含 <linux/sched.h>, jiffies 和 jiffies_64 必须当作只读的.
      (API) include <linux/jiffies.h>
            int time_after(unsigned long a, unsigned long b);
            int time_before(unsigned long a, unsigned long b);
            int time_after_eq(unsigned long a, unsigned long b);
            int time_before_eq(unsigned long a, unsigned long b);
      msec = diff * 1000 / HZ; 
      #include <linux/time.h> 
      unsigned long timespec_to_jiffies(struct timespec *value);
      void jiffies_to_timespec(unsigned long jiffies, struct timespec *value);
      unsigned long timeval_to_jiffies(struct timeval *value);
      void jiffies_to_timeval(unsigned long jiffies, struct timeval *value);
      (API) #include <linux/jiffies.h> 
            u64 get_jiffies_64(void);
    7.1.2 处理特定的寄存器
      TSC:(timestamp counter) x86平台使用的寄存器.
        including <asm/msr.h>,
        use three macros:
        (API)
        rdtsc(low32,high32);
        rdtscl(low32);
        rdtscll(var64);
      对每个平台定义
      #include <linux/timex.h>
      cycles_t get_cycles(void);
    7.2. 获知当前时间
      
    7.3. 延后执行
      7.3.1. 长延时
      7.3.1.1. 忙等待
        最容易的( 尽管不推荐 ) 的实现是一个监视 jiffy 计数器的循环. 这里 j1 是 jiffies 的在延时超时的值:
          while (time_before(jiffies, j1))
            cpu_relax();
      7.3.1.2. 让出处理器
        while (time_before(jiffies, j1)) {/* <linux/sched.h>*/
          schedule();
        }
      7.3.1.3. 超时
        (API) wait_event_timeout 或者 wait_event_interruptible_timeout: #include <linux/wait.h>
              long wait_event_timeout(wait_queue_head_t q, condition, long timeout);
              long wait_event_interruptible_timeout(wait_queue_head_t q, condition, long timeout);
      7.3.2. 短延时
        #include <linux/delay.h>
        (API)
          void ndelay(unsigned long nsecs);
          void udelay(unsigned long usecs);
          void mdelay(unsigned long msecs);
    7.4 内核定时器
      内核自身使用定时器在几个情况下, 包括实现 schedule_timeout(). <linux/timer.h> kernel/timer.c
      当你在进程上下文之外(即, 在中断上下文), 你必须遵守下列规则:
        1.没有允许存取用户空间. 因为没有进程上下文, 没有和任何特定进程相关联的到用户空间的途径.
        2.这个 current 指针在原子态没有意义, 并且不能使用因为相关的代码没有和已被中断的进程的联系.
        3.进行睡眠或者调度. 原子代码不能调用 schedule 或者某种 wait_event, 也不能调用任何其他可能睡眠的函数. 例如, 调用 kmalloc(..., GFP_KERNEL) 是违犯规则的. 信号量也必须不能使用因为它们可能睡眠.
      (API)   in_interrupt(), 报告是否为中断上下文，是则返回非零。
              in_atomatic(); 无论调度被禁止时，返回非零。这包含硬件和软件中断上下文以及任何持有自旋锁的时候. 2 个函数都在 <asm/hardirq.h>
      内核定时器的另一个重要特性是一个任务可以注册它本身在后面时间重新运行.也值得了解在一个 SMP 系统, 定时器函数被注册时相同的 CPU 来执行, 为在任何可能的时候获得更好的缓存局部特性. 因此, 一个重新注册它自己的定时器一直运行在同一个 CPU.
      定时器的一个重要特性是, 它们是一个潜在的竞争条件的源, 即便在一个单处理器系统. 这是它们与其他代码异步运行的一个直接结果. 因此, 任何被定时器函数存取的数据结构应当保护避免并发存取, 要么通过原子类型( 在第 1 章的"原子变量"一节) 要么使用自旋锁( 在第 9 章讨论 ).
    7.4.1. 定时器 API
      #include <linux/timer.h>
      struct timer_list
      {
        /* ... */
        unsigned long expires;
        void (*function)(unsigned long);
        unsigned long data;
      };
      void init_timer(struct timer_list *timer);
      struct timer_list TIMER_INITIALIZER(_function, _expires, _data);

      void add_timer(struct timer_list * timer);
      int del_timer(struct timer_list * timer); 
      这个数据结构包含比曾展示过的更多的字段, 但是这 3 个是打算从定时器代码自身以外被存取的. 这个 expires 字段表示定时器期望运行的 jiffies 值; 在那个时间, 这个 function 函数被调用使用 data 作为一个参数. 如果你需要在参数中传递多项, 你可以捆绑它们作为一个单个数据结构并且传递一个转换为 unsigned long 的指针, 在所有支持的体系上的一个安全做法并且在内存管理中相当普遍( 如同 15 章中讨论的 ). expires 值不是一个 jiffies_64 项因为定时器不被期望在将来很久到时, 并且 64-位操作在 32-位平台上慢.
      int mod_timer(struct timer_list *timer, unsigned long expires);
        
      int mod_timer(struct timer_list *timer, unsigned long expires);
   7.5. Tasklets 机制
      它大部分用在中断管理.它们一直在中断时间运行, 它们一直运行在调度它们的同一个 CPU 上, 并且它们接收一个 unsigned long 参数.
      #include <linux/interrupt.h> 
      struct tasklet_struct {
       /* ... */

        void (*func)(unsigned long);
        unsigned long data;
      };

      void tasklet_init(struct tasklet_struct *t,
            void (*func)(unsigned long), unsigned long data);
      DECLARE_TASKLET(name, func, data);
      DECLARE_TASKLET_DISABLED(name, func, data);
      tasklet 提供了许多有趣的特色:

        一个 tasklet 能够被禁止并且之后被重新使能; 它不会执行直到它被使能与被禁止相同的的次数.

        如同定时器, 一个 tasklet 可以注册它自己.

        一个 tasklet 能被调度来执行以正常的优先级或者高优先级. 后一组一直是首先执行.

        taslet 可能立刻运行, 如果系统不在重载下, 但是从不会晚于下一个时钟嘀哒.

        一个 tasklet 可能和其他 tasklet 并发, 但是对它自己是严格地串行的 -- 同样的 tasklet 从不同时运行在超过一个处理器上. 同样, 如已经提到的, 一个 tasklet 常常在调度它的同一个 CPU 上运行.
      (API)  void tasklet_disable(struct tasklet_struct *t);
             void tasklet_disable_nosync(struct tasklet_struct *t);
                禁止这个 tasklet, 但是没有等待任何当前运行的函数退出. 当它返回, 这个 tasklt 被禁止并且不会在以后被调度直到重新使能, 但是它可能仍然运行在另一个 CPU 当这个函数返回时.
             void tasklet_enable(struct tasklet_struct *t);
                一个对 tasklet_enable 的调用必须匹配每个对 tasklet_disable 的调用, 因为内核跟踪每个 tasklet 的"禁止次数".
             void tasklet_schedule(struct tasklet_struct *t);
                调度 tasklet 执行. 如果一个 tasklet 在它有机会运行前被再次调度, 它只运行一次. 但是, 如果他在运行中被调度, 它在完成后再次运行; 
                这保证了在其他事件被处理当中发生的事件收到应有的注意. 这个做法也允许一个 tasklet 重新调度它自己.
      	     void tasklet_hi_schedule(struct tasklet_struct *t);
              调度一个 tasklet 运行, 或者作为一个"正常" tasklet 或者一个高优先级的. 当软中断被执行, 高优先级 tasklets 被首先处理, 而正常 tasklet 最后执行.

             void tasklet_kill(struct tasklet_struct *t);
              从激活的链表中去掉 tasklet, 如果它被调度执行. 如同 tasklet_disable, 这个函数可能在 SMP 系统中阻塞等待 tasklet 终止, 如果它当前在另一个 CPU 上运行.
    7.7.5. 工作队列
  第 8 章 分配内存
    8.1.1. flags 参数

    记住 kmalloc 原型是:
    (API)
    #include <linux/slab.h> 
    void *kmalloc(size_t size, gfp_t flags);给 kmalloc 的第一个参数是要分配的块的大小. 第 2 个参数, 分配标志, 非常有趣, 因为它以几个方式控制 kmalloc 的行为.
      Linux 内核知道最少 3 个内存区: DMA内存, 普通内存, 和高端内存.
      GFP_ATOMIC
        用来从中断处理和进程上下文之外的其他代码中分配内存. 从不睡眠.

      GFP_KERNEL
        内核内存的正常分配. 可能睡眠.

      GFP_USER
        用来为用户空间页来分配内存; 它可能睡眠.
      GFP_HIGHUSER
        如同 GFP_USER, 但是从高端内存分配
    *** 同样, 程序员应当记住 kmalloc 能够处理的最小分配是 32 或者 64 字节, 依赖系统的体系所使用的页大小.它不能指望可以分配任何大于 128 KB.
    8.2. 后备缓存
	    (API)
      struct kmem_cache *kmem_cache_create(const char *name, size_t size,
          size_t offset,
          unsigned long flags,
          void (*)(void *));
      
    8.3 get_free_page
      <linux/gfp.h>
      (API) get_zeroed_page(unsigned gfp_t gfp_mask);
            unsigned long __get_free_page(unsigned gfp_t gfp_mask);
            unsigned long __get_free_pages(unsigned gfp_t gfp_mask, unsigned int order); 分配并返回一个指向内存区第一个字节的指针，内存区是几个页长未清零的内存。order 是页长的log2(N).
         /proc/buddyinfo 告诉你系统中每个内存区中的每个 order 有多少块可用
      void free_page(unsigned long addr);
      void free_pages(unsigned long addr, unsigned int order); *** 不能释放分配的页数不同的页数。
    8.3.2. alloc_pages 接口
      <linux/gfp.h>
      (API) struct page *alloc_pages_node(int nid, gfp_t gfp_mask,
                                          unsigned int order);
            alloc_pages(gfp_t gfp_mask, unsigned int order);
            alloc_page(gfp_t gfp_mask);

            void __free_page(struct page *page);
            void __free_pages(struct page *page, unsigned int order);
            void free_hot_cold_page(struct page *page, bool cold); cold = true ? free a cold page : free a hot page
    8.3.3 vmalloc
