#include <linux/init.h>
#include <linux/module.h>
#include <linux/sched.h>
MODULE_LICENSE("Dual BSD/GPL");

static int __init hello_init(void)
{
	printk(KERN_ALERT"Hello, world.\n");
	/* print current process name and pid */
	printk(KERN_INFO "The process is \"%s\" (pid %i)\n", current->comm, current->pid);
	return 0;
}

static void __exit hello_exit(void)
{
	printk(KERN_ALERT"Goodbye, crule world.\n");
}

module_init(hello_init);
module_exit(hello_exit);
