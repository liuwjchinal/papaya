#include"printf.h"

/* 测试程序不是随便写的．
 * lib1要引用lib3和lib4的函数和变量．
 * lib1要导出变量和函数给主程序。
 * 每个模块都定义一个未初始化的名叫common_var的变量，来测试弱类型
 
 * 依赖关系:lib1 <== lib3, lib4
 *			lib2 <== lib5, lib6
 *          lib*　都依赖于printf.so
 */
int global_var;
int global_var1 = 1;
extern int global_var3, global_var4;

int foobar3(void);
int foobar4(void);

int foobar1(void){
	print("foobar1 invoked\n"); 
	//extern void write(char *str, int len);
	//write("abcde", 5);
	print("taste global_var3: %d, global_var4: %d\n", global_var3, global_var4);
	foobar3();
	foobar4();
	return 1;
}
