#ifndef SCHEDULE_H
#define SCHEDULE_H
extern unsigned ticks;
extern struct pcb *idle;
/**if a process is prepared for running,we say it's 'active'.all active process
 * are stored in this linked-list in ascendsing order of 'prio'.
 */
struct pcb *list_active;

/**if a process uses out the time_slice,we say it's 'expire'.
 * an expire process will never be scheduled until it's time_slice renewed.
 */
struct pcb *list_expire;

void sleep_active(struct pcb *p);
void schedule(void);
#define __SAVE()\
	__asm__ __volatile__(\
	"pushl $0\n\t"\
	"pushl %%fs\n\t"\
	"pushl %%gs\n\t"\
	"pushl %%es\n\t"\
	"pushl %%ds\n\t"\
	"pushl %%eax\n\t"\
	"pushl %%ebp\n\t"\
	"pushl %%edi\n\t"\
	"pushl %%esi\n\t"\
	"pushl %%edx\n\t"\
	"pushl %%ecx\n\t"\
	"pushl %%ebx\n\t"\
	"movl %%esp, %0\n\t"\
	:"=m"(current->pregs)\
	:\
	)
#endif
