#include <linux/init.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/stat.h>
#include <linux/sched.h>
MODULE_LICENSE("Dual BSD/GPL");

static char *whom = "world";
static int howmany = 1;
module_param(whom, charp, S_IRUGO);
module_param(howmany, int, S_IRUGO);
static int __init hello_init(void)
{
	int i;
	for (i = 0;i < howmany; i++) {
		printk(KERN_ALERT"(%d)Hello, %s.\n", i, whom);
	}
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
